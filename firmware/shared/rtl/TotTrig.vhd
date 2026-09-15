-- Description: Time over threshold trigger
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

entity TotTrig is
    generic (
        TPD_G           : time                   := 1 ns;
        DATA_WIDTH_G    : positive range 1 to 32 := 32;
        SAFE_HYST_EN_G  : boolean                := true;  -- Set bounds check for hyst computations
        NUM_ADDR_BITS_G : positive);  -- Number of AXI-Lite address bits in the Subordinate
    port (
        -- ADC data lines
        adcClk          : in  sl;
        adcRst          : in  sl := '0';
        adcDat          : in  slv(DATA_WIDTH_G-1 downto 0);
        -- Trigger output
        trigOut         : out sl;
        -- AXI-Lite Interface (top module appClk domain, this module axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl := '0';
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType);
end entity TotTrig;

architecture rtl of TotTrig is

    type StateType is (
        IDLE_S,
        ARMD_S,
        CNT_S);

    type RegType is record
        dat            : slv(DATA_WIDTH_G-1 downto 0);
        thr            : slv(DATA_WIDTH_G-1 downto 0);
        hyst           : slv(DATA_WIDTH_G-1 downto 0);
        thrTotChk      : slv(DATA_WIDTH_G-1 downto 0);
        dir            : sl;
        hystEn         : sl;
        cnt            : slv(31 downto 0);  -- Counter to measure TOT
        cntTrig        : slv(31 downto 0);  -- Counter value at which to trigger
        arm            : sl;
        keepArm        : sl;
        forceTrig      : sl;
        trig           : sl;
        state          : StateType;
        stateReg       : slv(7 downto 0);
        axilReadSlave  : AxiLiteReadSlaveType;
        axilWriteSlave : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        dat            => (others => '0'),
        thr            => (others => '0'),
        hyst           => (others => '0'),
        thrTotChk      => (others => '0'),
        dir            => '0',
        hystEn         => '0',
        cnt            => (others => '0'),
        cntTrig        => (others => '0'),
        arm            => '0',
        keepArm        => '0',
        forceTrig      => '0',
        trig           => '0',
        state          => IDLE_S,
        stateReg       => (others => '0'),
        axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal axilAdcReadMaster  : AxiLiteReadMasterType;
    signal axilAdcReadSlave   : AxiLiteReadSlaveType  := AXI_LITE_READ_SLAVE_EMPTY_DECERR_C;
    signal axilAdcWriteMaster : AxiLiteWriteMasterType;
    signal axilAdcWriteSlave  : AxiLiteWriteSlaveType := AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C;

begin

-- Easiest to synchronize the whole AXI interface to the adcClk domain and to
-- all the register definitions there
    U_AxiLiteAsync : entity surf.AxiLiteAsync
        generic map (
            TPD_G           => TPD_G,
            COMMON_CLK_G    => false,
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
            mAxiClkRst      => adcRst,
            mAxiReadMaster  => axilAdcReadMaster,
            mAxiReadSlave   => axilAdcReadSlave,
            mAxiWriteMaster => axilAdcWriteMaster,
            mAxiWriteSlave  => axilAdcWriteSlave);

    comb : process (axilAdcReadMaster, axilAdcWriteMaster, r, adcRst, adcDat) is
        variable v          : RegType;
        variable axilEp     : AxiLiteEndPointType;
        variable thrHystExt : slv(DATA_WIDTH_G downto 0);
    begin

        -- Latch the current value
        v := r;

        -- Register ADC value to possibly help with timing
        v.dat := adcDat;

        -- Reset strobes
        v.trig      := '0';
        v.forceTrig := '0';

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilAdcWriteMaster, axilAdcReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.thr);  -- Threshold
        axiSlaveRegister (axilEp, x"04", 0, v.hyst);  -- Hysteresis
        axiSlaveRegister (axilEp, x"08", 0, v.dir);  -- Direction (0=above 1=below)
        axiSlaveRegister (axilEp, x"08", 1, v.hystEn);   -- Hysteresis enable
        axiSlaveRegister (axilEp, x"08", 2, v.arm);  -- Trigger arm
        axiSlaveRegister (axilEp, x"08", 3, v.keepArm);  -- Set to keep armed after triggered
        axiSlaveRegister (axilEp, x"08", 4, v.forceTrig);  -- Force trigger from software
        axiSlaveRegisterR(axilEp, x"08", 5, r.trig);  -- Trigger signal readback
        axiSlaveRegisterR(axilEp, x"0C", 0, r.stateReg);   -- FSM state
        axiSlaveRegister (axilEp, x"14", 0, v.cntTrig);  -- Count at which to trigger
        axiSlaveRegisterR(axilEp, x"18", 0, r.cnt);  -- TOT counter readback

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Trigger FSM
        case r.state is

            when IDLE_S =>
                -- Check for re-arming the trigger
                if r.arm = '1' then
                    -- Transition to armed state
                    v.state := ARMD_S;
                end if;

            when ARMD_S =>
                -- Return to idle if user de-asserts arm flag.
                if r.arm = '0' then
                    v.state := IDLE_S;
                    -- Reset arm flag
                    v.arm   := '0';
                elsif ((r.dir = '0') and (r.dat >= r.thr)) or
                    ((r.dir = '1') and (r.dat <= r.thr)) then

                    -- Prepare hysteresis. With TOT we always need hysteresis
                    -- for the TOT abort condition and thus cannot shortcut
                    -- back to idle if keepArm is disabled.
                    -- hyst=0 is equivalent to hysteresis disabled.
                    if r.hystEn = '1' then
                        -- Set the threshold we want to wait for being
                        -- crossed to abort TOT count.
                        if r.dir = '0' then
                            if SAFE_HYST_EN_G then
                                -- Add but prevent underflow
                                if r.thr >= r.hyst then
                                    v.thrTotChk := r.thr - r.hyst;
                                else
                                    v.thrTotChk := (others => '0');
                                end if;
                            else
                                v.thrTotChk := r.thr - r.hyst;
                            end if;
                        else
                            if SAFE_HYST_EN_G then
                                -- Add but prevent overflow
                                thrHystExt := ('0' & r.thr) + ('0' & r.hyst);
                                if thrHystExt(DATA_WIDTH_G) = '1' then
                                    v.thrTotChk := (others => '1');
                                else
                                    v.thrTotChk := thrHystExt(DATA_WIDTH_G-1 downto 0);
                                end if;
                            else
                                v.thrTotChk := r.thr + r.hyst;
                            end if;
                        end if;
                    else
                        -- The second threshold to check is the same as the
                        -- initial one if there is no hysteresis.
                        v.thrTotChk := r.thr;
                    end if;

                    -- Preset the TOT counter
                    v.cnt := r.cntTrig;

                    -- Move to count TOT state
                    v.state := CNT_S;
                end if;

            when CNT_S =>
                -- Return to idle if user de-asserts arm flag.
                if r.arm = '0' then
                    v.state := IDLE_S;
                    -- Reset arm flag
                    v.arm   := '0';
                elsif ((r.dir = '0') and (r.dat <= r.thrTotChk)) or
                    ((r.dir = '1') and (r.dat >= r.thrTotChk)) then
                    -- If signal below threshold (possibly with hysteresis),
                    -- abort TOT count and return to armed state.
                    v.state := ARMD_S;
                -- Trigger case comes last to make any abort condition
                -- take precedence (as a convention).
                elsif r.cnt = 0 then
                    -- Strobe trigger output if counter reaches zero
                    v.trig := '1';

                    -- Return to idle state if keep arm is disabled,
                    -- otherwise return to armed state.
                    if r.keepArm = '0' then
                        v.state := IDLE_S;
                        -- Reset arm flag
                        v.arm   := '0';
                    else
                        -- Move back to armed state if should stay armed
                        v.state := ARMD_S;
                    end if;
                end if;

                -- Decrement TOT counter
                v.cnt := r.cnt - 1;

        end case;

        -- Update state register
        v.stateReg := conv_std_logic_vector(StateType'pos(v.state), v.stateReg'length);

        ----------------------------------------------------------------------

        -- Force trigger when commanded from software, independent of
        -- state of the FSM, which also will remain in current state.
        if r.forceTrig = '1' then
            v.trig := '1';
        end if;

        ----------------------------------------------------------------------

        -- Outputs
        axilAdcWriteSlave <= r.axilWriteSlave;
        axilAdcReadSlave  <= r.axilReadSlave;
        trigOut           <= r.trig;

        -- Synchronous Reset
        if adcRst = '1' then
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

end architecture rtl;
