library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.math_real.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

entity RevSigCtrl is
    generic (
        CLOCK_FREQ_G : real := 125.0e6;  -- in Hz
        TPD_G        : time := 1 ns);
    port (
        clk             : in  sl;
        rst             : in  sl;
        -- Input signals
        revIn           : in  sl;       -- Revolution signal input
        -- Output signals
        revOut          : out sl;
        revOutDiv       : out sl;  -- Revolution pulse output only on every nth revolution
        -- AXI-Lite Interface
        axilClk         : in  sl;
        axilRst         : in  sl;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType;
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType);
end entity RevSigCtrl;

architecture rtl of RevSigCtrl is

    -- 5120 RF buckets at 508.89 MHz RF clock frequency
    constant REV_PERIOD_C : real := 1 / 508.89e6 * 5120;

    type RegType is record
        revOut                : sl;
        realRev               : sl;
        dummyRev              : sl;
        revDiv                : sl;
        clockCounter          : slv(31 downto 0);
        clockCounterPresetVal : slv(31 downto 0);
        revCounter            : slv(31 downto 0);
        revCounterPresetVal   : slv(31 downto 0);
        useDummyRev           : sl;
        axilReadSlave         : AxiLiteReadSlaveType;
        axilWriteSlave        : AxiLiteWriteSlaveType;
    end record RegType;

    -- Note: Set reasonable defaults for preset values to avoid the output
    -- signals being triggered at a very high rate on reset.
    constant REG_INIT_C : RegType := (
        revOut                => '0',
        realRev               => '0',
        dummyRev              => '0',
        revDiv                => '0',
        clockCounter          => (others => '0'),
        -- clockCounterPresetVal => toSlv(integer(round(REV_PERIOD_C * CLOCK_FREQ_G)) - 1, 32),
        clockCounterPresetVal => toSlv(8 - 1, 32),
        revCounter            => (others => '0'),
        -- 5120 buckets / 508.89 MHz RF clock gives ~ 10 us per turn.
        -- Trigger every 100000 turns gives around 1.00611134 Hz.
        revCounterPresetVal   => toSlv(100000 - 1, 32),
        useDummyRev           => '0',
        axilReadSlave         => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave        => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal axilDspReadMaster  : AxiLiteReadMasterType;
    signal axilDspReadSlave   : AxiLiteReadSlaveType  := AXI_LITE_READ_SLAVE_EMPTY_DECERR_C;
    signal axilDspWriteMaster : AxiLiteWriteMasterType;
    signal axilDspWriteSlave  : AxiLiteWriteSlaveType := AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C;

begin

    U_AxiLiteAsync : entity surf.AxiLiteAsync
        generic map (
            TPD_G           => TPD_G,
            COMMON_CLK_G    => false,
            NUM_ADDR_BITS_G => 32)
        port map (
            -- Slave Interface (axiClk domain)
            sAxiClk         => axilClk,
            sAxiClkRst      => axilRst,
            sAxiReadMaster  => axilReadMaster,
            sAxiReadSlave   => axilReadSlave,
            sAxiWriteMaster => axilWriteMaster,
            sAxiWriteSlave  => axilWriteSlave,
            -- Master Interface (dspClk domain)
            mAxiClk         => clk,
            mAxiClkRst      => rst,
            mAxiReadMaster  => axilDspReadMaster,
            mAxiReadSlave   => axilDspReadSlave,
            mAxiWriteMaster => axilDspWriteMaster,
            mAxiWriteSlave  => axilDspWriteSlave);

    comb : process (axilDspReadMaster, axilDspWriteMaster, r, revIn) is
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin

        -- Latch the current value
        v := r;

        -- Reset strobes
        v.dummyRev := '0';

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilDspWriteMaster, axilDspReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        axiSlaveRegister (axilEp, x"00", 0, v.revCounterPresetVal);  -- Revolution counter preset value
        axiSlaveRegister (axilEp, x"04", 0, v.clockCounterPresetVal);  -- Clock counter preset value for dummy rev
        axiSlaveRegisterR(axilEp, x"08", 0, r.revCounter);
        axiSlaveRegisterR(axilEp, x"0C", 0, r.clockCounter);
        axiSlaveRegister (axilEp, x"10", 0, v.useDummyRev);
        axiSlaveRegisterR(axilEp, x"14", 0, r.realRev);
        axiSlaveRegisterR(axilEp, x"14", 1, r.dummyRev);
        axiSlaveRegisterR(axilEp, x"14", 2, r.revOut);
        axiSlaveRegisterR(axilEp, x"14", 3, r.revDiv);

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);


        ----------------------------------------------------------------------
        --          Revolution Signal Processing/Generation Logic
        ----------------------------------------------------------------------

        -- Register input revolution signal
        v.realRev := revIn;

        -- Generate dummy revolution signal
        if (r.clockCounter = 0) then
            -- Pulse revolution signal output
            v.dummyRev     := '1';
            -- Preset clock cycle counter
            v.clockCounter := r.clockCounterPresetVal;
        else
            -- Decrement clock cycle counter
            v.clockCounter := r.clockCounter - 1;
        end if;

        -- Select real or dummy revoution signal
        if (r.useDummyRev = '1') then
            v.revOut := r.dummyRev;
        else
            v.revOut := r.realRev;
        end if;

        -- Count revolutions and generate revolution synchronous trigger.
        -- Check v, not r to ensure trigger output in same cycle as revolution signal.
        if (v.revOut = '1') then
            if (r.revCounter = 0) then
                -- Pulse revolution synchronous trigger output
                v.revDiv     := '1';
                -- Preset revolution counter
                v.revCounter := r.revCounterPresetVal;
            else
                -- Decrement revolution counter
                v.revCounter := r.revCounter - 1;
            end if;
        end if;

        ----------------------------------------------------------------------

        -- Outputs
        axilDspWriteSlave <= r.axilWriteSlave;
        axilDspReadSlave  <= r.axilReadSlave;
        revOut            <= r.revOut;
        revOutDiv         <= r.revDiv;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (clk) is
    begin
        if rising_edge(clk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end architecture rtl;
