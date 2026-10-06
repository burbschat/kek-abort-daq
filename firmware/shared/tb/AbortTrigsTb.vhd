library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.SsiPkg.all;

entity AbortTrigsTb is end AbortTrigsTb;

architecture testbed of AbortTrigsTb is

    constant ADC_CLK_PERIOD_C  : time := 8 ns;
    constant AXIL_CLK_PERIOD_C : time := 10 ns;
    constant TPD_C             : time := ADC_CLK_PERIOD_C/4;

    type RegType is record
        dat    : slv(15 downto 0);
        revSig : sl;
        injSig : sl;
        cnt    : slv(15 downto 0);
    end record;

    constant REG_INIT_C : RegType := (
        dat    => (others => '0'),
        revSig => '0',
        injSig => '0',
        cnt    => (others => '0'));

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal adcClk  : sl := '0';
    signal adcRst  : sl := '1';
    signal axilClk : sl := '0';
    signal axilRst : sl := '1';

    signal axilSetupDone : sl := '0';

    signal axilWriteMaster : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
    signal axilWriteSlave  : AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;
    signal axilReadMaster  : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
    signal axilReadSlave   : AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;

begin

    ---------------------------
    -- Generate clock and reset
    ---------------------------
    U_DataClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => ADC_CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => adcClk,
            clkN => open,
            rst  => adcRst,
            rstL => open);

    U_AxiClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => AXIL_CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => axilClk,
            clkN => open,
            rst  => axilRst,
            rstL => open);

    --------------------------
    -- Design Under Test (DUT)
    --------------------------

    U_AbortTrigs : entity work.AbortTrigs
        generic map(
            TPD_G            => TPD_C,
            COMMON_CLK_G     => false,
            AXIL_BASE_ADDR_G => (others => '0'),
            NUM_ADDR_BITS_G  => 24)
        port map(
            -- ADC data lines
            adcClk          => adcClk,
            adcRst          => '0',
            adcDat(0)       => r.dat,
            adcDat(1)       => r.dat,
            -- Revolution signal input
            revSig          => r.revSig,
            -- Injection signal input (use for veto)
            injSig          => r.injSig,
            -- Trigger output
            abortTrig       => open,
            -- AXI-Lite Interface (axilClk domain)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave);



    axil : process is
        variable debugData : slv(31 downto 0) := (others => '0');
    begin
        ------------------------------------------
        -- Wait for the AXI-Lite reset to complete
        ------------------------------------------
        wait until axilRst = '1';
        wait until axilRst = '0';

        --------------------------------------
        -- Axi reads/writes (block until done)
        --------------------------------------

        wait for 50 ns;  -- First write does not register immediately after reset...

        -- Setup registers for injection veto test

        -- Set delay
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_000C", x"0000_0010", true);
        axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_000C", debugData, true);
        -- Set window length
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0014", x"0000_0040", true);
        axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_0014", debugData, true);

        -- Enable veto effect on trigger outputs
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_001C", x"0000_0001", true);
        axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_001C", debugData, true);

        -- Enable both channels
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0004", x"0000_0003", true);
        axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_0004", debugData, true);

        -- Enable threshold trigger in output logic
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0000", x"0000_0007", true);
        axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_0000", debugData, true);

        axilSetupDone <= '1';

        wait for 500 ns;
        -- Force trigger from threshold trigger on first channel to check if vetoed
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0001_0008", x"0000_0010", true);

        wait for 100 ns;
        -- Force trigger from threshold trigger on first channel to check if no longer vetoed
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0001_0008", x"0000_0010", true);

    end process axil;


    comb : process (r, adcRst, axilSetupDone) is
        variable v : RegType;
    begin

        -- Latch the current value
        v := r;

        -- Reset the strobes
        v.revSig := '0';
        v.injSig := '0';

        -- Increment the counter
        v.cnt := r.cnt + 1;

        -- For now, let the data be the counter
        v.dat := r.cnt;

        -- Generate a revolution signal pulse every 64 counts
        if r.cnt(5 downto 0) = 0 then
            v.revSig := '1';
        end if;

        -- Generate a injection signal pulse every 256 counts
        if r.cnt(7 downto 0) = 0 then
            v.injSig := '1';
        end if;

        -- Synchronous Reset
        -- Keep reset until configuration over axil done
        if (adcRst = '1') or (axilSetupDone = '0') then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (adcClk) is
    begin
        if (rising_edge(adcClk)) then
            r <= rin after TPD_C;
        end if;
    end process seq;

end testbed;
