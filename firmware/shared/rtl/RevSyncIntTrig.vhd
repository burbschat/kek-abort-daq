-- Description: Revolution signal synchronized integral value trigger.
-- Use to integrate over one full bunch train synchronized with the revolution
-- such that the trigger decision happens just at the 'deadline' timed to abort
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
        TPD_G           : time                  := 1 ns;
        NUM_WNDS_G      : positive range 1 to 8 := 2;  -- Hard limit on number of preset values
        NUM_ADDR_BITS_G : positive);  -- Number of AXI-Lite address bits in the Subordinate
    port (
        -- ADC data lines
        adcClk          : in  sl;
        adcRst          : in  sl := '0';
        adcDat          : in  slv(15 downto 0);
        -- Revolution signal input
        revSig          : in  sl;
        -- Trigger output
        trigOut         : out sl;
        thrCrsOut       : out sl;
        -- AXI-Lite Interface (axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl := '0';
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType);
end entity RevSyncIntTrig;

architecture rtl of RevSyncIntTrig is

    -- Fix to 16 bit wide data interface as that is likely
    -- all that will be needed in practice.
    constant DATA_WIDTH_C : positive := 16;

    type StateType is (
        IDLE_S,
        ARMD_S);

    type RegType is record
        revSig             : sl;        -- Registered revolution signal
        revSigDly          : slv(31 downto 0);  -- Initial delay from revSig until first window
        revSigDlyCnt       : slv(31 downto 0);  -- Counter to measure time for revSig delay
        revSigDlyCntRun    : sl;  -- Counter running flag (for oneshot operation)
        revSigPrdCnt       : slv(31 downto 0);  -- Counter to measure revSig period (T=1/f)
        revSigPrd          : slv(31 downto 0);  -- Counter to latch the measured period to (reference when defining the windows)
        wndAlgn            : sl;  -- Window align pulse (revSig after delay)
        wndCnt             : slv(31 downto 0);  -- Counter to measure time for windows
        wndLngts           : slv32Array(NUM_WNDS_G-1 downto 0);  -- Integration window lengths
        wndIdx             : slv(15 downto 0);  -- Currently active integration window index
        wndIdxMax          : slv(15 downto 0);  -- Index at which to wrap back to 0. Must be < NUM_PRST_VALS_G.
        dat                : slv(DATA_WIDTH_C-1 downto 0);  -- Registered ADC data
        datInt             : slv(DATA_WIDTH_C*2-1 downto 0);  -- Integrated data
        datIntLch          : slv(DATA_WIDTH_C*2-1 downto 0);  -- Integrated data latched at last deadline
        datIntThrs         : slv32Array(NUM_WNDS_G-1 downto 0);  -- Integral value trigger thresholds for each window
        arm                : sl;        -- Arm/disarm flag
        keepArm            : sl;        -- Auto re-arm flag
        thrCrs             : sl;  -- Strobed on integral exceeds threshold (when armed)
        forceThrCrs        : sl;        -- Force thrCrs strobe (for testing)
        wndCntAtThrCrs     : slv(31 downto 0);  -- Counter value latched at time of threshold crossing
        wndCntAtThrCrsLchd : sl;  -- Counter value at time of threshold crossing latched flag
        trig               : sl;  -- Trigger output synchronized to the deadline
        forceTrig          : sl;        -- Force trigger outpt (for testing)
        state              : StateType;         -- FSM state
        stateReg           : slv(7 downto 0);   -- FSM state mapped to slv
        axilReadSlave      : AxiLiteReadSlaveType;
        axilWriteSlave     : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        revSig             => '0',
        revSigDly          => (others => '0'),
        revSigDlyCnt       => (others => '0'),
        revSigDlyCntRun    => '0',
        revSigPrdCnt       => (others => '0'),
        revSigPrd          => (others => '0'),
        wndAlgn            => '0',
        wndCnt             => (others => '0'),
        wndLngts           => (others => (others => '0')),
        wndIdx             => (others => '0'),
        wndIdxMax          => (others => '0'),
        dat                => (others => '0'),
        datInt             => (others => '0'),
        datIntLch          => (others => '0'),
        datIntThrs         => (others => (others => '0')),
        arm                => '0',
        keepArm            => '1',  -- The usual use case would require re-arming so set here just in case
        thrCrs             => '0',
        forceThrCrs        => '0',
        wndCntAtThrCrs     => (others => '0'),
        wndCntAtThrCrsLchd => '0',
        trig               => '0',
        forceTrig          => '0',
        state              => IDLE_S,
        stateReg           => (others => '0'),
        axilReadSlave      => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave     => AXI_LITE_WRITE_SLAVE_INIT_C);

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
        variable trigConditionMet : boolean := false;
    begin

        -- Latch the current value
        v := r;

        -- Register ADC and revSig value to possibly help with timing
        v.dat    := adcDat;
        v.revSig := revSig;

        -- Reset strobes
        v.wndAlgn := '0';

        v.thrCrs      := '0';
        v.forceThrCrs := '0';

        v.trig := '0';
        -- forceRevSyncTrig reset only once deadline reached so not here!

        trigConditionMet := false;

        ---------------------------------------------------------
        -- Apply digital delay to revSig pulse and measure period
        ---------------------------------------------------------
        if r.revSig = '1' then
            v.revSigDlyCnt    := r.revSigDly;  -- Preset counter with delay value
            v.revSigDlyCntRun := '1';   -- start the counter

            v.revSigPrd    := r.revSigPrdCnt;  -- Latch counts since last revSig (measured period)
            v.revSigPrdCnt := (others => '0');     -- Reset period counter
        else
            v.revSigPrdCnt := r.revSigPrdCnt + 1;  -- Increment
        end if;

        -- Update or check delay counter if running
        if r.revSigDlyCntRun = '1' then
            if r.revSigDlyCnt = 0 then
                v.revSigDlyCntRun := '0';              -- Stop counter
                v.wndAlgn         := '1';              -- Strobe window align
            else
                v.revSigDlyCnt := r.revSigDlyCnt - 1;  -- Decrement
            end if;
        end if;

        -----------------------------------
        -- Force wndIdxMax in allowed range
        -----------------------------------
        if (v.wndIdxMax > NUM_WNDS_G-1) then
            v.wndIdxMax := toSlv(NUM_WNDS_G-1, 16);
        end if;

        ---------------------------------------------
        -- Integration logic independent of FSM state
        ---------------------------------------------
        -- Trigger condition used in multiple locations below.
        trigConditionMet := r.datInt >= r.datIntThrs(conv_integer(r.wndIdx));

        if r.wndAlgn = '1' then  -- Align counter reset must come first in if chain to take precedence
            -- Reset the integral value to 0
            v.datInt := (others => '0');
            -- Start back over at first window
            v.wndIdx := toSlv(0, 16);
            v.wndCnt := r.wndLngts(0);  -- Preset counter

        -- A deadline is reached only when the counter runs out!
        -- Making wndAlgn a deadline would mean that the integration window length
        -- is dynamic and as we do not normalize by the length this cannot be
        -- tolerated.
        -- This means that if the wndAlgn happens before the final deadline, it is
        -- never reached and triggering at this last deadline will never happen.
        -- The user must ensure that the windows are sized such that the required
        -- deadlines are all before the next wndAlgn pulse. The revSigPrd register
        -- is provided to count the number of clocks between align signals (which is
        -- the same as number of clocks between revSig pulses). This can be
        -- referenced when sizing the windows to ensure they end before the next
        -- align pulse: T_w1 + T_w2 + ... < T_revSig
        -- The user may also poll wndIdx a few times and see if it ever reaches the
        -- intended maximal value (TODO: Could add sticky max val register).
        -- TODO: Check if there are a few cycle differences due to registered signals...
        elsif r.wndCnt = 0 then         -- Deadline reached
            -- Check the integral value and strobe trigger if threshold exceeded.
            -- Force trigger works independent of state.
            if (trigConditionMet and (r.state = ARMD_S)) or (r.forceTrig = '1') then
                -- Want to issue a trigger always at the same timing in
                -- relation to the revSig to make delay adjustment possible.
                -- There is not gain in outputting the trigger earlier as
                -- the abort kicker would wait anyways.
                v.trig      := '1';
                -- Make sure the force flag is reset in case it was set but do
                -- so here to make sure it stays set until the next deadline is
                -- reached.
                v.forceTrig := '0';
            end if;

            -- Latch integral value at deadline for reference
            v.datIntLch := r.datInt;
            -- Reset the integral value to 0
            v.datInt    := (others => '0');

            -- Reset counter value at threshold crossing latched flag
            v.wndCntAtThrCrsLchd := '0';

            -- Determine next window index
            if (r.wndIdx < r.wndIdxMax) then
                v.wndIdx := r.wndIdx + 1;  -- Increment
            else
                -- Wrap around to 0 if next index would be larger than maximum (i.e.
                -- current one is the maximum).
                v.wndIdx := (others => '0');
            end if;

            -- Preset the counter with next preset value (reference v not r!)
            v.wndCnt := r.wndLngts(conv_integer(v.wndIdx));

        else  -- TODO: Could add a count only when 'running' flag set here...
            v.wndCnt := r.wndCnt - 1;   -- Decrement
            v.datInt := r.datInt + r.dat;  -- Add to integral value

        end if;

        -- Keep around also an immediate (not revSig synchronized) threshold crossed
        -- strobe and record the count at which the threshold was crossed as we might
        -- care about that in post-mortem analysis.
        -- Only in armed state to allow for freezing of the recorded count by disabling
        -- keepArm (which requires software re-arm after each trigger).
        -- Force threshold crossed strobe works independent of state.
        if (trigConditionMet and (r.state = ARMD_S)) or (r.forceThrCrs = '1') then
            v.thrCrs := '1';
            if r.wndCntAtThrCrsLchd = '0' then
                v.wndCntAtThrCrs     := r.wndCnt;
                v.wndCntAtThrCrsLchd := '1';
            end if;
        end if;

        --------------
        -- Trigger FSM
        --------------
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
                    -- above issued the revSig synchronized trigger (trigger
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


        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilAdcWriteMaster, axilAdcReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        -- Read only single bit registers
        axiSlaveRegisterR(axilEp, x"00", 0, r.revSig);
        axiSlaveRegisterR(axilEp, x"00", 1, r.revSigDlyCntRun);
        axiSlaveRegisterR(axilEp, x"00", 2, r.wndAlgn);
        axiSlaveRegisterR(axilEp, x"00", 3, r.thrCrs);
        axiSlaveRegisterR(axilEp, x"00", 4, r.trig);

        -- Writable single bit registers
        axiSlaveRegister (axilEp, x"04", 0, v.arm);
        axiSlaveRegister (axilEp, x"04", 1, v.keepArm);
        axiSlaveRegister (axilEp, x"04", 2, v.forceThrCrs);
        axiSlaveRegister (axilEp, x"04", 3, v.forceTrig);

        -- Read only vector registers
        axiSlaveRegisterR(axilEp, x"08", 0, r.revSigDlyCnt);
        axiSlaveRegisterR(axilEp, x"0C", 0, r.revSigPrdCnt);
        axiSlaveRegisterR(axilEp, x"10", 0, r.revSigPrd);
        axiSlaveRegisterR(axilEp, x"14", 0, r.wndCnt);
        axiSlaveRegisterR(axilEp, x"18", 0, r.wndIdx);
        axiSlaveRegisterR(axilEp, x"1C", 0, r.dat);
        axiSlaveRegisterR(axilEp, x"20", 0, r.datInt);
        axiSlaveRegisterR(axilEp, x"24", 0, r.datIntLch);
        axiSlaveRegisterR(axilEp, x"28", 0, r.wndCntAtThrCrs);
        axiSlaveRegisterR(axilEp, x"2C", 0, r.stateReg);

        -- Writable vector registers
        axiSlaveRegister (axilEp, x"30", 0, v.revSigDly);
        axiSlaveRegister (axilEp, x"34", 0, v.wndIdxMax);

        for i in 0 to NUM_WNDS_G-1 loop
            -- Reserve 8 registers each (which is the max for NUM_WNDS_G)
            axiSlaveRegister (axilEp, x"38" + toSlv(0 + i*4, 8), 0, v.wndLngts(i));
            axiSlaveRegister (axilEp, x"38" + toSlv(8*4 + i*4, 8), 0, v.datIntThrs(i));
        end loop;


        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Update state register
        v.stateReg := conv_std_logic_vector(StateType'pos(v.state), v.stateReg'length);

        -- Outputs
        axilAdcWriteSlave <= r.axilWriteSlave;
        axilAdcReadSlave  <= r.axilReadSlave;
        trigOut           <= r.trig;
        thrCrsOut         <= r.thrCrs;

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
