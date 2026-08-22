-- Description: Simple threshold trigger
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

entity ThrTrig is
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
end entity ThrTrig;

architecture rtl of ThrTrig is

    type StateType is (
        IDLE_S,
        ARMD_S,
        HYST_S);

    type RegType is record
        dat            : slv(DATA_WIDTH_G-1 downto 0);
        thr            : slv(DATA_WIDTH_G-1 downto 0);
        hyst           : slv(DATA_WIDTH_G-1 downto 0);
        thrHyst        : slv(DATA_WIDTH_G-1 downto 0);
        dir            : sl;
        hystEn         : sl;
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
        thrHyst        => (others => '0'),
        dir            => '0',
        hystEn         => '0',
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
                    -- Strobe trigger output
                    v.trig                    := '1';

                    -- Return to idle state if keep arm is disabled.
                    -- Return to idle if user de-asserts arm flag.
                    if r.keepArm = '0' then
                        v.state := IDLE_S;
                        -- Reset arm flag
                        v.arm   := '0';
                    -- Prepare and move to hysteresis state if enabled.
                    -- Do not have to bother with hysteresis if keep
                    -- arm is disabled, so use the else branch here.
                    elsif r.hystEn = '1' then
                        -- Set the threshold we want to wait for being
                        -- crossed in the hysteresis wait state.
                        if r.dir = '0' then
                            if SAFE_HYST_EN_G then
                                -- Add but prevent underflow
                                if r.thr >= r.hyst then
                                    v.thrHyst := r.thr - r.hyst;
                                else
                                    v.thrHyst := (others => '0');
                                end if;
                            else
                                v.thrHyst := r.thr - r.hyst;
                            end if;
                        else
                            if SAFE_HYST_EN_G then
                                -- Add but prevent overflow
                                thrHystExt := ('0' & r.thr) + ('0' & r.hyst);
                                if thrHystExt(DATA_WIDTH_G) = '1' then
                                    v.thrHyst := (others => '1');
                                else
                                    v.thrHyst := thrHystExt(DATA_WIDTH_G-1 downto 0);
                                end if;
                            else
                                v.thrHyst := r.thr + r.hyst;
                            end if;
                        end if;
                        -- Set next state
                        v.state := HYST_S;
                    end if;
                end if;

            when HYST_S =>
                -- Return to idle if user de-asserts arm flag.
                if r.arm = '0' then
                    v.state := IDLE_S;
                    -- Reset arm flag
                    v.arm   := '0';
                elsif ((r.dir = '0') and (r.dat <= r.thrHyst)) or
                    ((r.dir = '1') and (r.dat >= r.thrHyst)) then
                    -- This state is only reachable when keep arm is
                    -- set so in any case return to the armed state.
                    v.state := ARMD_S;
                end if;

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
