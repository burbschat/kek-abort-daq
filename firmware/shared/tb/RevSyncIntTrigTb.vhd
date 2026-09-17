library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.SsiPkg.all;

entity RevSyncIntTrigTb is end RevSyncIntTrigTb;

architecture testbed of RevSyncIntTrigTb is

    constant CLK_PERIOD_C : time := 8 ns;
    constant TPD_C        : time := CLK_PERIOD_C/4;

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

    signal dataClk : sl := '0';
    signal dataRst : sl := '1';
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
            CLK_PERIOD_G      => CLK_PERIOD_C,
            RST_START_DELAY_G => 0 ns,  -- Wait this long into simulation before asserting reset
            RST_HOLD_TIME_G   => 1000 ns)  -- Hold reset for this long
        port map (
            clkP => dataClk,
            clkN => open,
            rst  => dataRst,
            rstL => open);

    U_AxiClkRst : entity surf.ClkRst
        generic map (
            CLK_PERIOD_G      => CLK_PERIOD_C/3.1415,  -- Make clocks more or less async
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

    U_RevSyncIntTrig : entity work.RevSyncIntTrig
        generic map(
            TPD_G           => TPD_C,
            NUM_WNDS_G      => 2,
            NUM_ADDR_BITS_G => 16)
        port map(
            adcClk          => dataClk,
            adcRst          => dataRst,
            adcDat          => r.dat,
            -- Revolution signal input
            revSig          => r.revSig,
            -- Trigger outputs
            trigOut         => open,
            thrCrsOut       => open,
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
        -- axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_0030", debugData, true);

        -- Set revSigDly to 16 cycles
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0030", x"0000_0010", true);
        -- Set revSigDly to 16 cycles
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0030", x"0000_0010", true);

        -- Set wndIdxMax to 1 (e.g. 2 windows)
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0034", x"0000_0001", true);
        -- Readback for confirmation
        axiLiteBusSimRead (axilClk, axilReadMaster, axilReadSlave, x"0000_0034", debugData, true);

        -- Set wndLngts(0) to 512
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0038", x"0000_0200", true);
        -- Set wndLngts(1) to 512
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_003C", x"0000_0200", true);

        -- Set datIntThrs(0) to 4096
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0058", x"0000_1000", true);
        -- Set datIntThrs(1) to 4096
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_005C", x"0000_1000", true);

        -- Set arm to 1, keepArm to 1
        axiLiteBusSimWrite (axilClk, axilWriteMaster, axilWriteSlave, x"0000_0004", x"0000_0003", true);

        axilSetupDone <= '1';
    end process axil;


    comb : process (r, dataRst, axilSetupDone) is
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

        -- Generate a revolution signal pulse every 1024 counts
        if r.cnt(9 downto 0) = 0 then
            v.revSig := '1';
        end if;

        -- Synchronous Reset
        -- Keep reset until configuration over axil done
        if (dataRst = '1') or (axilSetupDone = '0') then
            v := REG_INIT_C;
        end if;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (dataClk) is
    begin
        if (rising_edge(dataClk)) then
            r <= rin after TPD_C;
        end if;
    end process seq;

end testbed;
