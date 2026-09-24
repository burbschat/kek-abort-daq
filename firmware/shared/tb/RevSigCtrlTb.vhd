library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

-- library axi_soc_ultra_plus_core;
-- use axi_soc_ultra_plus_core.AxiSocUltraPlusPkg.all;

library work;
use work.AppPkg.all;

entity RevSigCtrlTb is end entity RevSigCtrlTb;

architecture testbed of RevSigCtrlTb is

    constant CLK_PERIOD_C : time := (1/(ADC_CLK_FREQ_C * 1.0e-9)) * 1 ns;
    constant TPD_C        : time := 1 ns;

    type RegType is record
        cnt : slv(31 downto 0);
    end record;

    constant REG_INIT_C : RegType := (
        cnt => (others => '0'));

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal clk : sl := '0';
    signal rst : sl := '1';

    signal revIn  : sl;
    signal revOut : sl;
    signal revDiv : sl;

    signal axilReadMaster  : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
    signal axilReadSlave   : AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;
    signal axilWriteMaster : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
    signal axilWriteSlave  : AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;

begin

    ----------------------------
    -- Generate clock and reset
    ----------------------------

    U_DataClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => clk,
            clkN => open,
            rst  => rst,
            rstL => open);

    ---------------------------
    -- Design Under Test (DUT)
    ---------------------------

    U_RevSigCtrl : entity work.RevSigCtrl
        generic map(
            CLOCK_FREQ_G => ADC_CLK_FREQ_C,
            TPD_G        => TPD_C)
        port map(
            clk             => clk,
            rst             => rst,
            revIn           => revIn,
            revOut          => revOut,
            revOutDiv       => revDiv,
            -- AXI-Lite Interface
            axilClk         => clk,
            axilRst         => rst,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave);

    ------------------------------------------
    -- Configure over over axi lite interface
    ------------------------------------------

    config : process is
    begin
        wait until rst = '1';
        wait until rst = '0';

        wait for 10*CLK_PERIOD_C;

        -- Set shorter durations
        axiLiteBusSimWrite(clk, axilWriteMaster, axilWriteSlave, x"00000000", x"00000003");
        axiLiteBusSimWrite(clk, axilWriteMaster, axilWriteSlave, x"00000004", x"00000007");
        -- Enable outputs, set use dummy rev, enable module, reset counters
        -- axiLiteBusSimWrite(clk, axilWriteMaster, axilWriteSlave, x"00000010", x"0000003f");
        -- Enable outputs, set use real rev, enable module, reset counters
        axiLiteBusSimWrite(clk, axilWriteMaster, axilWriteSlave, x"00000010", x"0000003d");

    end process config;

    --------------
    -- Test logic
    --------------
    comb : process (r, rst) is
        variable v : RegType;
    begin

        -- Latch the current value
        v := r;

        -- Increment the counter
        v.cnt := r.cnt + 1;

        if r.cnt(3 downto 0) = x"0000" then
            revIn <= '1';
        else
            revIn <= '0';
        end if;

        -- Synchronous Reset
        if (rst = '1') then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (clk) is
    begin
        if (rising_edge(clk)) then
            r <= rin after TPD_C;
        end if;
    end process seq;

end architecture testbed;
