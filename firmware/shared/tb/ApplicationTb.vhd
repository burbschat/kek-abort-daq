library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

entity ApplicationTb is end ApplicationTb;

architecture testbed of ApplicationTb is

    constant ADC_CLK_PERIOD_C : time := 8 ns;
    constant APP_CLK_PERIOD_C : time := 10 ns;
    constant TPD_C            : time := ADC_CLK_PERIOD_C/4;

    constant AXIL_REG_BASE_ADDR_C : slv(31 downto 0) := x"4000_0000";
    constant APP_ADDR_OFFSET_C    : slv(31 downto 0) := x"2000_0000";  -- Relative to AXIL_GLOB_BASE_ADDR_C

    type RegType is record
        dat    : slv(15 downto 0);
        revSig : sl;
        cnt    : slv(15 downto 0);
    end record;

    constant REG_INIT_C : RegType := (
        dat    => (others => '0'),
        revSig => '0',
        cnt    => (others => '0'));

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

    signal adcClk : sl := '0';
    signal adcRst : sl := '1';
    signal appClk : sl := '0';
    signal appRst : sl := '1';

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
            CLK_PERIOD_G      => APP_CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => appClk,
            clkN => open,
            rst  => appRst,
            rstL => open);

    --------------------------
    -- Design Under Test (DUT)
    --------------------------

    U_App : entity work.Application
        generic map (
            TPD_G            => TPD_C,
            -- If there was another crossbar at the top module we may reference
            -- the baseAddr from there but for now there is non, so must set the
            -- (full 32 bits) of base addres here manually.
            AXIL_BASE_ADDR_G => AXIL_REG_BASE_ADDR_C + APP_ADDR_OFFSET_C  -- AXIL_CONFIG_C(APP_INDEX_C).baseAddr  -- Global base + offset should be 0x6000_0000
            )
        port map (
            leds            => open,
            -- AXI-Lite Interface (appClk domain)
            axilClk         => appClk,
            axilRst         => appRst,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            -- DMA Interface (dmaClk domain)
            axisClk         => appClk,
            axisRst         => appRst,
            dmaIbMaster     => open,
            dmaIbSlave      => AXI_STREAM_SLAVE_INIT_C,
            -- ADC data lines (there no control input to the ADCs, so there
            -- only is the data stream, thus directly pipe it into the
            -- Application)
            adcClk          => adcClk,
            adcDat(0)       => r.dat,
            adcDat(1)       => r.dat,
            -- Application specific ports
            abortReq        => open,
            revSigIn        => '0',
            injSig          => '0',
            extTrig         => '0');


    axil : process is
        variable debugData : slv(31 downto 0) := (others => '0');
    begin
        ------------------------------------------
        -- Wait for the AXI-Lite reset to complete
        ------------------------------------------
        wait until appRst = '1';
        wait until appRst = '0';

        --------------------------------------
        -- Axi reads/writes (block until done)
        --------------------------------------

        wait for 50 ns;  -- First write does not register immediately after reset...

        -- Test register (first register in the application)
        axiLiteBusSimRead (appClk, axilReadMaster, axilReadSlave, x"6000_0000", debugData, true);

        -- Attempt write to chMask register
        axiLiteBusSimWrite (appClk, axilWriteMaster, axilWriteSlave, x"6400_0000", x"0000_0003", true);
        -- Readback for confirmation
        axiLiteBusSimRead (appClk, axilReadMaster, axilReadSlave, x"6400_0000", debugData, true);

        axilSetupDone <= '1';
    end process axil;


    comb : process (r, adcRst, axilSetupDone) is
        variable v : RegType;
    begin

        -- Latch the current value
        v := r;

        -- Reset the strobes
        v.revSig := '0';

        -- Increment the counter
        v.cnt := r.cnt + 1;

        -- For now, let the data be the counter
        v.dat := r.cnt;

        -- Generate a revolution signal pulse every 64 counts
        if r.cnt(5 downto 0) = 0 then
            v.revSig := '1';
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
