-- Description: Revolution signal synchronized integral value trigger.
-- Integrate over one full bunch train synchronized with the revolution such
-- that the trigger decision happens just at the 'deadline' required to abort
-- at the next abort gap.
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

entity RevSyncIntTrig is
    generic (
        TPD_G           : time                   := 1 ns;
        DATA_WIDTH_G    : positive range 1 to 32 := 16;
        NUM_PRST_VALS_G : positive range 1 to 8  := 2;  -- Hard limit on number of preset values
        NUM_ADDR_BITS_G : positive);  -- Number of AXI-Lite address bits in the Subordinate
    port (
        -- ADC data lines
        adcClk          : in  sl;
        adcRst          : in  sl := '0';
        adcDat          : in  slv(DATA_WIDTH_G-1 downto 0);
        -- Revolution signal input
        revSig          : in  sl;
        -- Trigger output
        revSyncTrigOut  : out sl;
        thrCrossOut     : out sl;
        -- AXI-Lite Interface (axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl := '0';
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType);
end entity RevSyncIntTrig;

architecture rtl of RevSyncIntTrig is

    type StateType is (
        IDLE_S,
        ARMD_S);

    type RegType is record
        cnt              : slv(31 downto 0);  -- 16 might suffice but align with axil registers for convenience
        prstVals         : slv32Array(NUM_PRST_VALS_G-1 downto 0);  -- Counter preset values
        prstValIdx       : slv(31 downto 0);  -- Currently used preset value
        prstValIdxMax    : slv(31 downto 0);  -- Index at which to wrap back to 0. Must be < NUM_PRST_VALS_G.
        revSig           : sl;          -- Registered revolution signal
        dat              : slv(DATA_WIDTH_G-1 downto 0);
        datInt           : slv(DATA_WIDTH_G*2-1 downto 0);  -- Integrated data
        datIntPrev       : slv(DATA_WIDTH_G*2-1 downto 0);  -- Integrated data
        datIntThr        : slv(DATA_WIDTH_G*2-1 downto 0);
        arm              : sl;
        keepArm          : sl;
        forceThrCross    : sl;
        thrCross         : sl;  -- Strobed on integral exceeds threshold (when armed)
        cntAtThrCross    : slv(31 downto 0);  -- 16 might suffice but align with axil registers for convenience
        forceRevSyncTrig : sl;
        revSyncTrig      : sl;
        state            : StateType;
        stateReg         : slv(7 downto 0);
        axilReadSlave    : AxiLiteReadSlaveType;
        axilWriteSlave   : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        cnt              => (others => '0'),
        prstVals         => (others => (others => '0')),
        prstValIdx       => (others => '0'),
        prstValIdxMax    => (others => '0'),
        revSig           => '0',
        dat              => (others => '0'),
        datInt           => (others => '0'),
        datIntPrev       => (others => '0'),
        datIntThr        => (others => '0'),
        arm              => '0',
        keepArm          => '1',  -- The usual use case would require re-arming so set here just in case
        forceThrCross    => '0',
        thrCross         => '0',
        cntAtThrCross    => (others => '0'),
        forceRevSyncTrig => '0',
        revSyncTrig      => '0',
        state            => IDLE_S,
        stateReg         => (others => '0'),
        axilReadSlave    => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave   => AXI_LITE_WRITE_SLAVE_INIT_C);

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

    comb : process (axilAdcReadMaster, axilAdcWriteMaster, r, adcRst, adcDat, revSig) is
        variable v                : RegType;
        variable axilEp           : AxiLiteEndPointType;
        variable trigConditionMet : boolean;
    begin

        -- Latch the current value
        v := r;

        -- Register ADC and revSig value to possibly help with timing
        v.dat    := adcDat;
        v.revSig := revSig;

        -- Reset strobes
        v.thrCross       := '0';
        v.forceThrCross  := '0';
        v.revSyncTrig    := '0';
        -- forceRevSyncTrig reset only once deadline reached so not here!
        trigConditionMet := false;

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilAdcWriteMaster, axilAdcReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.datIntThr(minimum(DATA_WIDTH_G*2, 32)-1 downto 0));  -- Lower bits
        if DATA_WIDTH_G > 32 then
            axiSlaveRegister (axilEp, x"04", 0, v.datIntThr(DATA_WIDTH_G*2-32-1 downto 32));  -- Upper bits if required
        end if;

        axiSlaveRegisterR(axilEp, x"08", 0, v.revSig);  -- revSig readback

        axiSlaveRegister (axilEp, x"08", 2, v.arm);      -- Trigger arm
        axiSlaveRegister (axilEp, x"08", 3, v.keepArm);  -- Set to keep armed after triggered

        axiSlaveRegister (axilEp, x"08", 4, v.forceRevSyncTrig);  -- Force trigger from software
        axiSlaveRegisterR(axilEp, x"08", 5, r.revSyncTrig);  -- Trigger signal readback
        axiSlaveRegister (axilEp, x"08", 6, v.forceThrCross);  -- Force threshold cross strobe from software
        axiSlaveRegisterR(axilEp, x"08", 7, v.thrCross);  -- Threshold cross strobe readback

        axiSlaveRegisterR(axilEp, x"0C", 0, r.stateReg);  -- FSM state

        for i in 0 to NUM_PRST_VALS_G-1 loop  -- Reserve 8 registers which is the max for NUM_PRST_VALS_G
            axiSlaveRegister (axilEp, x"10" + toSlv(i*4, 8), 0, v.prstVals(i));  -- Counter preset values
        end loop;
        axiSlaveRegisterR(axilEp, x"30", 0, r.prstValIdx);  -- Preset value index readback
        axiSlaveRegisterR(axilEp, x"34", 0, r.prstValIdxMax);  -- Preset value index after which to wrap back to 1

        axiSlaveRegister (axilEp, x"38", 0, v.datInt(minimum(DATA_WIDTH_G*2, 32)-1 downto 0));  -- Current integral lower bits
        if DATA_WIDTH_G > 32 then
            axiSlaveRegister (axilEp, x"3C", 0, v.datInt(DATA_WIDTH_G*2-32-1 downto 32));  -- Current integral upper bits if required
        end if;
        axiSlaveRegister (axilEp, x"40", 0, v.datIntPrev(minimum(DATA_WIDTH_G*2, 32)-1 downto 0));  -- Integral at last deadline lower bits
        if DATA_WIDTH_G > 32 then
            axiSlaveRegister (axilEp, x"44", 0, v.datIntPrev(DATA_WIDTH_G*2-32-1 downto 32));  -- Integral at last deadline upper bits if required
        end if;

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Force prstValIdxWrp in allowed range
        if (v.prstValIdxMax > NUM_PRST_VALS_G) then
            v.prstValIdxMax := toSlv(NUM_PRST_VALS_G, 32);
        elsif (v.prstValIdxMax < 1) then
            -- Minimum is 1 as we always wrap around to 1.
            -- Make this explicit by not allowing 0 rather than silently
            -- wrapping to 1 even if the max is set to 0.
            v.prstValIdxMax := toSlv(1, 32);
        end if;

        -- Counters and integration always run/synchronize to revSig
        -- independent of the state. The FSM only governs whether the
        -- trigger is output or not.
        if r.revSig = '1' then          -- revSig sync takes precedence!
            -- Reset the preset value index to 0 to get the initial
            -- delay until the first deadline.
            -- The integral at the very first deadline after reset will
            -- read low due to a shorter integration window, but this
            -- likely can be ignored in practice.
            v.prstValIdx := toSlv(0, 32);
            -- Preset the counter with next preset value (here always idx=0)
            v.cnt        := r.prstVals(0);
        elsif r.cnt = 0 then
            -- Check the integral value, register it in the previous value
            -- register for reference and set the trigger flag if threshold
            -- is exceeded.
            -- Force trigger works independent of state.
            -- Variable reused below in to give real trigger precedence and return
            -- to idle state if required.
            trigConditionMet := (r.datInt >= r.datIntThr) and (r.state = ARMD_S);
            if (trigConditionMet) or (r.forceRevSyncTrig = '1') then
                -- Want to issue a trigger always at the same timing in
                -- relation to the revSig to make delay adjustment possible.
                -- There is not gain in outputting the trigger earlier as
                -- the abort kicker would wait anyways.
                v.revSyncTrig      := '1';
                -- Make sure the force flag is reset in case it was set but do
                -- so here to make sure it stays set until the next deadline is
                -- reached.
                v.forceRevSyncTrig := '0';
            end if;
            v.datIntPrev := r.datInt;

            -- Determine next preset value index
            if (r.prstValIdx < r.prstValIdxMax) then
                v.prstValIdx := r.prstValIdx + 1;
            else
                -- Wrap around to 1, not 0. The preset val at index
                -- 0 determines the initial delay form revSig to the
                -- first deadline.
                v.prstValIdx := toSlv(1, 32);
            end if;

            -- Preset the counter with next preset value
            v.cnt    := r.prstVals(conv_integer(v.prstValIdx));
            -- Reset the integral value to 0
            v.datInt := toSlv(0, DATA_WIDTH_G*2);
        else  -- TODO: Could add a count only when 'running' flag set here...
            -- Decrement counter
            v.cnt := r.cnt - 1;
        end if;

        -- Keep around also an immediate (not revSig synchronized) threshold crossed
        -- strobe and record the count at which the threshold was crossed as we might
        -- care about that in post-mortem analysis.
        -- Only in armed state to allow for freezing of the recorded count by disabling
        -- keepArm (which requires software re-arm after each trigger).
        -- Force threshold crossed strobe works independent of state.
        if ((r.datInt >= r.datIntThr) and (r.state = ARMD_S)) or (r.forceThrCross = '1') then
            v.thrCross      := '1';
            v.cntAtThrCross := r.cnt;
        end if;

        -- Trigger FSM
        case r.state is

            when IDLE_S =>
                -- Check for arming the trigger
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
                else
                    -- Return to idle state if keep arm is disabled and logic
                    -- above issued the revSig synchronous trigger (trigger
                    -- condition met). Check the trigger condition variable
                    -- specifically (and not the trigger output signal) in order
                    -- to not change the state if the trigger was forced.
                    if (trigConditionMet) and (r.keepArm = '0') then
                        v.state := IDLE_S;
                        -- Reset arm flag
                        v.arm   := '0';
                    end if;
                end if;

        end case;

        -- Update state register
        v.stateReg := conv_std_logic_vector(StateType'pos(v.state), v.stateReg'length);

        ----------------------------------------------------------------------

        -- Force trigger when commanded from software, independent of
        -- state of the FSM, which also will remain in current state.
        if r.forceThrCross = '1' then
            v.thrCross := '1';
        end if;

        ----------------------------------------------------------------------

        -- Outputs
        axilAdcWriteSlave <= r.axilWriteSlave;
        axilAdcReadSlave  <= r.axilReadSlave;
        revSyncTrigOut    <= r.revSyncTrig;
        thrCrossOut       <= r.thrCross;

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
