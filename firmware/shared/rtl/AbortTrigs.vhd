-- Description: Module to collect multiple trigger logic blocks and allow for
-- selection of a trigger signal provided by those. This is deliberately
-- opinionated and tailored to the SuperKEKB abort trigger application.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiPkg.all;

library axi_soc_7000_core;
use axi_soc_7000_core.AxiSoc7000Pkg.all;

entity AbortTrigs is
    generic (
        TPD_G            : time    := 1 ns;
        COMMON_CLK_G     : boolean := false;
        AXIL_BASE_ADDR_G : slv(31 downto 0);
        NUM_ADDR_BITS_G  : positive);  -- Number of AXI-Lite address bits in the Subordinate
    port (
        -- ADC data lines
        adcClk          : in  sl;
        adcRst          : in  sl := '0';
        adcDat          : in  Slv16Array(1 downto 0);
        -- Revolution signal input
        revSig          : in  sl;
        -- Injection signal input (use for veto)
        -- TODO: Implement veto functionality in this module.
        -- Should have window and delay setting.
        injSig          : in  sl;
        -- Trigger output
        abortTrig       : out sl;
        -- AXI-Lite Interface (axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl := '0';
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType);
end entity AbortTrigs;

architecture mapping of AbortTrigs is

    constant DATA_WIDTH_C : positive := 16;

    constant BASE_BOT_C      : positive := 20;
    constant NUM_ADDR_BITS_C : positive := 16;

    constant NUM_CH_C         : positive := 2;  -- Two channels
    constant NUM_TRIG_TYPES_C : positive := 3;  -- Three trigger types

    constant NUM_AXIL_MASTERS_C           : natural := 1 + NUM_CH_C * NUM_TRIG_TYPES_C;  -- 1 + 2 * 3  = 7
    constant AXIL_REG_INDEX               : natural := 0;
    constant AXIL_THR_TRIG_INDEX_BASE     : natural := 1;  -- 1 and 2
    constant AXIL_TOT_TRIG_INDEX_BASE     : natural := 3;  -- 3 and 4
    constant AXIL_REVSYNC_TRIG_INDEX_BASE : natural := 5;  -- 5 and 6

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0)
        := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, BASE_BOT_C, NUM_ADDR_BITS_C);

    -- Count corrections to get cycle accurate behaviour wrt. the register values.
    -- Required as some cycles are mandatory given the register based logic.
    constant INJ_SIG_DLY_CYLCOMP_C     : positive := 2;  -- Make number correct wrt. signal at revSig port!
    constant INJ_VET_WND_LNG_CYLCOMP_C : positive := 1;

    signal axilAdcReadMasters : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilAdcReadSlaves  : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)
        := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilAdcWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilAdcWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)
        := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    type RegType is record
        enMask          : slv(NUM_TRIG_TYPES_C-1 downto 0);
        chMask          : slv(NUM_CH_C-1 downto 0);
        injSig          : sl;
        injSigDly       : slv(31 downto 0);  -- Initial delay from injSig until veto window
        injSigDlyCnt    : slv(31 downto 0);  -- Counter to measure time for injSig delay
        injSigDlyCntRun : sl;           -- Counter running flag
        injVetWndLen    : slv(31 downto 0);  -- Set injection veto window length
        injVetWndCnt    : slv(31 downto 0);  -- Counter to measure injection veto window
        injVetActive    : sl;           -- Veto active flag
        injVetEn        : sl;           -- Injection veto enable register
        axilReadSlave   : AxiLiteReadSlaveType;
        axilWriteSlave  : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        enMask          => (others => '0'),
        chMask          => (others => '0'),
        injSig          => '0',
        injSigDly       => (others => '0'),
        injSigDlyCnt    => (others => '0'),
        injSigDlyCntRun => '0',
        injVetWndLen    => (others => '0'),
        injVetWndCnt    => (others => '0'),
        injVetActive    => '0',
        injVetEn        => '0',
        axilReadSlave   => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave  => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    -- AXI-Lite but synchronized to the adc clock domain
    signal axilAdcReadMaster  : AxiLiteReadMasterType;
    signal axilAdcReadSlave   : AxiLiteReadSlaveType  := AXI_LITE_READ_SLAVE_EMPTY_DECERR_C;
    signal axilAdcWriteMaster : AxiLiteWriteMasterType;
    signal axilAdcWriteSlave  : AxiLiteWriteSlaveType := AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C;

    signal revSigSyncOneshot : sl;

    signal thrTrigs     : slv(NUM_CH_C-1 downto 0);
    signal totTrigs     : slv(NUM_CH_C-1 downto 0);
    signal revSyncTrigs : slv(NUM_CH_C-1 downto 0);

    signal axilAdcRst : sl := '0';

begin


    -----------------
    -- AXI-Lite Async
    -----------------
    -- Easiest to synchronize the whole AXI interface to the adcClk domain and to
    -- all the register definitions there. As we use the async here, the optional
    -- async modules in the individual trigger modules should be disabled by
    -- setting COMMON_CLK_G=true for them and running on the adc clock.

    -- Want the axil reset but synchronized to the adc clock to reset the axil
    -- modules when upstream axil is reset. Don't really care about the ADC.
    U_RstSync : entity surf.RstSync
        generic map(
            TPD_G => TPD_G)
        port map(
            clk      => adcClk,
            asyncRst => axilRst,
            syncRst  => axilAdcRst);

    U_AxiLiteAsync : entity surf.AxiLiteAsync
        generic map (
            TPD_G           => TPD_G,
            COMMON_CLK_G    => COMMON_CLK_G,
            NUM_ADDR_BITS_G => NUM_ADDR_BITS_G)
        port map (
            -- Slave Interface (axiClk domain)
            sAxiClk         => axilClk,
            sAxiClkRst      => axilRst,
            sAxiReadMaster  => axilReadMaster,
            sAxiReadSlave   => axilReadSlave,
            sAxiWriteMaster => axilWriteMaster,
            sAxiWriteSlave  => axilWriteSlave,
            -- Master Interface (dspClk domain)
            mAxiClk         => adcClk,
            mAxiClkRst      => axilAdcRst,
            mAxiReadMaster  => axilAdcReadMaster,
            mAxiReadSlave   => axilAdcReadSlave,
            mAxiWriteMaster => axilAdcWriteMaster,
            mAxiWriteSlave  => axilAdcWriteSlave);

    --------------------
    -- AXI-Lite Crossbar
    --------------------

    U_XBAR : entity surf.AxiLiteCrossbar
        generic map (
            TPD_G              => TPD_G,
            NUM_SLAVE_SLOTS_G  => 1,
            NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
            MASTERS_CONFIG_G   => AXIL_CONFIG_C)
        port map (
            axiClk              => adcClk,
            axiClkRst           => axilAdcRst,
            sAxiWriteMasters(0) => axilAdcWriteMaster,
            sAxiWriteSlaves(0)  => axilAdcWriteSlave,
            sAxiReadMasters(0)  => axilAdcReadMaster,
            sAxiReadSlaves(0)   => axilAdcReadSlave,
            mAxiWriteMasters    => axilAdcWriteMasters,
            mAxiWriteSlaves     => axilAdcWriteSlaves,
            mAxiReadMasters     => axilAdcReadMasters,
            mAxiReadSlaves      => axilAdcReadSlaves);

    --------------------------------------------
    -- Synchronize revSig to adc clock (oneshot)
    --------------------------------------------
    -- RevSyncIntTrig requires this.

    U_SoftTrigSync : entity surf.SynchronizerOneShot
        generic map(
            TPD_G         => TPD_G,
            PULSE_WIDTH_G => 1)
        port map(
            clk     => adcClk,
            rst     => adcRst,
            dataIn  => revSig,
            dataOut => revSigSyncOneshot);

    --------------------------------------------
    -- Instantiate the available trigger modules
    --------------------------------------------

    gen_trigs : for i in 0 to 1 generate
        -- Threshold Trigger
        U_ThrTrig : entity work.ThrTrig
            generic map(
                TPD_G           => TPD_G,
                COMMON_CLK_G    => true,  -- Async already in this module
                DATA_WIDTH_G    => DATA_WIDTH_C,
                SAFE_HYST_EN_G  => true,
                NUM_ADDR_BITS_G => NUM_ADDR_BITS_C)
            port map(
                adcClk          => adcClk,
                adcRst          => adcRst,
                adcDat          => adcDat(i),
                trigOut         => thrTrigs(i),
                -- AXI-Lite Interface (here already on adcClk domain)
                axilClk         => adcClk,
                axilRst         => axilAdcRst,
                axilWriteMaster => axilAdcWriteMasters(AXIL_THR_TRIG_INDEX_BASE+i),
                axilWriteSlave  => axilAdcWriteSlaves(AXIL_THR_TRIG_INDEX_BASE+i),
                axilReadMaster  => axilAdcReadMasters(AXIL_THR_TRIG_INDEX_BASE+i),
                axilReadSlave   => axilAdcReadSlaves(AXIL_THR_TRIG_INDEX_BASE+i));

        -- Time-Over-Threshold Trigger
        U_TotTrig : entity work.TotTrig
            generic map(
                TPD_G           => TPD_G,
                COMMON_CLK_G    => true,  -- Async already in this module
                DATA_WIDTH_G    => DATA_WIDTH_C,
                SAFE_HYST_EN_G  => true,
                NUM_ADDR_BITS_G => NUM_ADDR_BITS_C)
            port map(
                adcClk          => adcClk,
                adcRst          => adcRst,
                adcDat          => adcDat(i),
                trigOut         => totTrigs(i),
                -- AXI-Lite Interface (here already on adcClk domain)
                axilClk         => adcClk,
                axilRst         => axilAdcRst,
                axilWriteMaster => axilAdcWriteMasters(AXIL_TOT_TRIG_INDEX_BASE+i),
                axilWriteSlave  => axilAdcWriteSlaves(AXIL_TOT_TRIG_INDEX_BASE+i),
                axilReadMaster  => axilAdcReadMasters(AXIL_TOT_TRIG_INDEX_BASE+i),
                axilReadSlave   => axilAdcReadSlaves(AXIL_TOT_TRIG_INDEX_BASE+i));

        -- Revsig synchronized integral trigger
        U_RevSyncIntTrig : entity work.RevSyncIntTrig
            generic map(
                TPD_G           => TPD_G,
                COMMON_CLK_G    => true,  -- Async already in this module
                NUM_WNDS_G      => 2,
                NUM_ADDR_BITS_G => NUM_ADDR_BITS_C)
            port map(
                adcClk          => adcClk,
                adcRst          => adcRst,
                adcDat          => adcDat(i),
                -- Revolution signal input
                revSig          => revSigSyncOneshot,
                -- Trigger outputs
                trigOut         => revSyncTrigs(i),
                thrCrsOut       => open,  -- Not required for now
                -- AXI-Lite Interface (here already on adcClk domain)
                axilClk         => adcClk,
                axilRst         => axilAdcRst,
                axilWriteMaster => axilAdcWriteMasters(AXIL_REVSYNC_TRIG_INDEX_BASE+i),
                axilWriteSlave  => axilAdcWriteSlaves(AXIL_REVSYNC_TRIG_INDEX_BASE+i),
                axilReadMaster  => axilAdcReadMasters(AXIL_REVSYNC_TRIG_INDEX_BASE+i),
                axilReadSlave   => axilAdcReadSlaves(AXIL_REVSYNC_TRIG_INDEX_BASE+i)
                );

    end generate gen_trigs;

    -----------------------
    -- Trigger output logic
    -----------------------

    -- For now same channel mask for all trigger types.
    -- Can extend this to per-type mask if required later.
    -- Enable mask idx 0: Threshold trigger
    -- Enable mask idx 1: Time-over-threshold trigger
    -- Enable mask idx 2: Revolution signal synchronized integral trigger
    abortTrig <= (
        (uOr(thrTrigs and r.chMask) and r.enMask(0))
        or
        (uOr(totTrigs and r.chMask) and r.enMask(1))
        or
        (uOr(revSyncTrigs and r.chMask) and r.enMask(2))
        ) and not (r.injVetActive and r.injVetEn);  -- Apply the veto if enabled

    --------------------------
    -- Configuration registers
    --------------------------

    comb : process (axilAdcReadMasters(AXIL_REG_INDEX),
                    axilAdcWriteMasters(AXIL_REG_INDEX),
                    r, axilAdcRst, injSig) is
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin

        -- Latch the current value
        v := r;

        -- Register injSig value
        v.injSig := injSig;

        -----------------------
        -- Injection Veto Logic
        -----------------------

        -- TODO: make cycle accurate (if required)
        if r.injSig = '1' then
            v.injSigDlyCnt    := (others => '0');  -- Reset delay counter
            v.injSigDlyCntRun := '1';
        end if;

        if r.injSigDlyCntRun = '1' then
            if r.injSigDlyCnt >= r.injSigDly - INJ_SIG_DLY_CYLCOMP_C then
                v.injSigDlyCntRun := '0';  -- Stop counter
                v.injVetWndCnt    := (others => '0');  -- Reset veto window counter
                v.injVetActive    := '1';  -- Set injection veto active
            else
                v.injSigDlyCnt := r.injSigDlyCnt + 1;  -- Increment
            end if;
        end if;

        if r.injVetActive = '1' then
            if r.injVetWndCnt >= r.injVetWndLen - INJ_VET_WND_LNG_CYLCOMP_C then
                v.injVetActive := '0';  -- Set injection veto inactive
            else
                v.injVetWndCnt := r.injVetWndCnt + 1;  -- Increment
            end if;
        end if;

        --------------------------
        -- AXI-Lite Register Logic
        --------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp,
                        axilAdcWriteMasters(AXIL_REG_INDEX),
                        axilAdcReadMasters(AXIL_REG_INDEX),
                        v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.enMask);  -- Trigger type enable mask
        axiSlaveRegister (axilEp, x"04", 0, v.chMask);  -- Channel enable mask
        axiSlaveRegisterR(axilEp, x"08", 0, v.injSig);  -- Injection signal input readback
        axiSlaveRegisterR(axilEp, x"08", 1, v.injSigDlyCntRun);  -- Injection signal delay counter running flag readback
        axiSlaveRegisterR(axilEp, x"08", 2, v.injVetActive);  -- Injection veto active readback
        axiSlaveRegister (axilEp, x"0C", 0, v.injSigDly);  -- Injection signal delay count max value
        axiSlaveRegisterR(axilEp, x"10", 0, v.injSigDlyCnt);  -- Injection signal delay count readback
        axiSlaveRegister (axilEp, x"14", 0, v.injVetWndLen);  -- Injection veto window length
        axiSlaveRegisterR(axilEp, x"18", 0, v.injVetWndCnt);  -- Injection veto window length counter readback
        axiSlaveRegister (axilEp, x"1C", 0, v.injVetEn);  -- Injection veto enable (i.e. actually veto the trigger outputs)

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        -----------------------------------
        -- Force registers in allowed range
        -----------------------------------
        if (v.injSigDly < INJ_SIG_DLY_CYLCOMP_C) then
            -- toSlv only works with up to 31 bits...
            v.injSigDly := conv_std_logic_vector(INJ_SIG_DLY_CYLCOMP_C, 32);
        end if;

        if (v.injVetWndLen < INJ_VET_WND_LNG_CYLCOMP_C) then
            -- toSlv only works with up to 31 bits...
            v.injVetWndLen := conv_std_logic_vector(INJ_VET_WND_LNG_CYLCOMP_C, 32);
        end if;

        ----------------------------------------------------------------------

        -- Outputs
        axilAdcWriteSlaves(AXIL_REG_INDEX) <= r.axilWriteSlave;
        axilAdcReadSlaves(AXIL_REG_INDEX)  <= r.axilReadSlave;

        -- Synchronous Reset
        if axilAdcRst = '1' then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (adcClk) is
    begin
        if rising_edge(adcClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end architecture mapping;
