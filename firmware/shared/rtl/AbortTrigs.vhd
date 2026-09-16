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
        TPD_G            : time := 1 ns;
        AXIL_BASE_ADDR_G : slv(31 downto 0));
    port (
        -- ADC data lines
        adcClk          : in  sl;
        adcRst          : in  sl := '0';
        adcDat          : in  Slv16Array(1 downto 0);
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

    constant NUM_AXIL_MASTERS_C       : natural := 1 + 2 * 2;
    constant AXIL_REG_INDEX           : natural := 0;
    constant AXIL_THR_TRIG_INDEX_BASE : natural := 1;  -- 1 and 2
    constant AXIL_TOT_TRIG_INDEX_BASE : natural := 3;  -- 3 and 4

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 20, 16);

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    type RegType is record
        enMask         : slv(1 downto 0);  -- Two trigger types
        chMask         : slv(1 downto 0);  -- Two channels
        axilReadSlave  : AxiLiteReadSlaveType;
        axilWriteSlave : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        enMask         => (others => '0'),
        chMask         => (others => '0'),
        axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal thrTrigs : slv(1 downto 0);
    signal totTrigs : slv(1 downto 0);

begin

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
            axiClk              => axilClk,
            axiClkRst           => axilRst,
            sAxiWriteMasters(0) => axilWriteMaster,
            sAxiWriteSlaves(0)  => axilWriteSlave,
            sAxiReadMasters(0)  => axilReadMaster,
            sAxiReadSlaves(0)   => axilReadSlave,
            mAxiWriteMasters    => axilWriteMasters,
            mAxiWriteSlaves     => axilWriteSlaves,
            mAxiReadMasters     => axilReadMasters,
            mAxiReadSlaves      => axilReadSlaves);


    --------------------------------------------
    -- Instantiate the available trigger modules
    --------------------------------------------

    gen_trigs : for i in 0 to 1 generate
        -- Threshold Trigger
        ThrTrig_inst : entity work.ThrTrig
            generic map(
                TPD_G           => TPD_G,
                DATA_WIDTH_G    => 16,
                SAFE_HYST_EN_G  => true,
                NUM_ADDR_BITS_G => 16)
            port map(
                adcClk          => adcClk,
                adcRst          => adcRst,
                adcDat          => adcDat(i),
                trigOut         => thrTrigs(i),
                axilClk         => axilClk,
                axilRst         => axilRst,
                axilWriteMaster => axilWriteMasters(AXIL_THR_TRIG_INDEX_BASE+i),
                axilWriteSlave  => axilWriteSlaves(AXIL_THR_TRIG_INDEX_BASE+i),
                axilReadMaster  => axilReadMasters(AXIL_THR_TRIG_INDEX_BASE+i),
                axilReadSlave   => axilReadSlaves(AXIL_THR_TRIG_INDEX_BASE+i));

        -- Time-Over-Threshold Trigger
        TotTrig_inst : entity work.TotTrig
            generic map(
                TPD_G           => TPD_G,
                DATA_WIDTH_G    => 16,
                SAFE_HYST_EN_G  => true,
                NUM_ADDR_BITS_G => 16)
            port map(
                adcClk          => adcClk,
                adcRst          => adcRst,
                adcDat          => adcDat(i),
                trigOut         => totTrigs(i),
                axilClk         => axilClk,
                axilRst         => axilRst,
                axilWriteMaster => axilWriteMasters(AXIL_TOT_TRIG_INDEX_BASE+i),
                axilWriteSlave  => axilWriteSlaves(AXIL_TOT_TRIG_INDEX_BASE+i),
                axilReadMaster  => axilReadMasters(AXIL_TOT_TRIG_INDEX_BASE+i),
                axilReadSlave   => axilReadSlaves(AXIL_TOT_TRIG_INDEX_BASE+i));

    -- TODO: Revsig synchronized average trigger
    end generate gen_trigs;

    -----------------------
    -- Trigger output logic
    -----------------------

    -- For now same channel mask for all trigger types. 
    -- Can extend this to per-type mask if required later.
    -- Enable mask idx 0: Threshold trigger
    -- Enable mask idx 1: Time-over-threshold trigger
    abortTrig <= (
        (uOr(thrTrigs and r.chMask) and r.enMask(0))
        or
        (uOr(totTrigs and r.chMask) and r.enMask(1))
        );


    --------------------------
    -- Configuration registers
    --------------------------

    comb : process (axilReadMasters(AXIL_REG_INDEX), axilWriteMasters(AXIL_REG_INDEX), r, axilRst) is
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin

        -- Latch the current value
        v := r;

        --------------------------
        -- AXI-Lite Register Logic
        --------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMasters(AXIL_REG_INDEX), axilReadMasters(AXIL_REG_INDEX),
                        v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.enMask);  -- Trigger type enable mask
        axiSlaveRegister (axilEp, x"00", 2, v.chMask);  -- Channel enable mask

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Outputs
        axilWriteSlaves(AXIL_REG_INDEX) <= r.axilWriteSlave;
        axilReadSlaves(AXIL_REG_INDEX)  <= r.axilReadSlave;

        -- Synchronous Reset
        if axilRst = '1' then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (axilClk) is
    begin
        if rising_edge(axilClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end architecture mapping;
