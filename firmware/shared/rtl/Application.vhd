library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiPkg.all;
use surf.SsiPkg.all;

library work;
use work.AppPkg.all;

library axi_soc_7000_core;
use axi_soc_7000_core.AxiSoc7000Pkg.all;


entity Application is
    generic (
        TPD_G            : time := 1 ns;
        AXIL_BASE_ADDR_G : slv(31 downto 0));
    port (
        leds            : out slv(7 downto 0);
        -- AXI-Lite Interface (top module appClk domain, this module axilClk domain)
        axilClk         : in  sl;
        axilRst         : in  sl;
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType;
        -- Stream interface to DMA (top module dmaClk domain, this module axisClk domain)
        axisClk         : in  sl;
        axisRst         : in  sl;
        dmaIbMaster     : out AxiStreamMasterType;
        dmaIbSlave      : in  AxiStreamSlaveType;
        -- ADC data lines
        adcClk          : in  sl;
        adcDatA         : in  slv(15 downto 0);
        adcDatB         : in  slv(15 downto 0)
        );
end Application;

architecture mapping of Application is

    constant NUM_AXIL_MASTERS_C : natural := 2;
    constant AXIL_TEST_INDEX    : natural := 0;
    constant AXIL_RING_INDEX    : natural := 1;

    -- TODO: What should the base bits be for genAxiLiteConfig? Set using global constants?
    -- constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 28, 24);
    -- For now, be explicit:
    -- TODO: See if I can get around specifying all 32 address bits as we don't care about the upper ones (I think)
    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := (
        AXIL_TEST_INDEX  => (
            baseAddr     => AXIL_BASE_ADDR_G + x"0000_0000",  -- Relative to app offset applied by crossbar in reg module in core? But still have to give correct address as all bits are compared???
            addrBits     => 24,
            connectivity => x"FFFF"),
        AXIL_RING_INDEX  => (
            baseAddr     => AXIL_BASE_ADDR_G + x"0100_0000",
            addrBits     => 24,
            connectivity => x"FFFF")
        );

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    signal count : slv(31 downto 0) := (others => '0');

    signal ringBuffTrig : sl := '0';

begin

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

    -- Some static registers for testing
    U_REG_STATIC : entity axi_soc_7000_core.AxiTestRegister
        port map(
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(AXIL_TEST_INDEX),
            axilReadSlave   => axilReadSlaves(AXIL_TEST_INDEX),
            axilWriteMaster => axilWriteMasters(AXIL_TEST_INDEX),
            axilWriteSlave  => axilWriteSlaves(AXIL_TEST_INDEX)
            );

    ringBuffTrig <= count(29-7+2);

    -- LED blinking
    process(axilClk)
    begin
        if rising_edge(axilClk) then
            count <= count + 1;

            -- At 125MHz the 26th bit should give visible LED blinking
            leds <= count(29 downto 29 - 7);

            -- Display ADC A Data bits on LEDs
            -- leds(7 downto 1) <= adcDatA(7 downto 1);
            leds(0) <= ringBuffTrig;
            leds(1) <= ringBuffTrig;

        end if;
    end process;

    U_AxiStreamRingBuffer : entity surf.AxiStreamRingBuffer
        generic map (
            TPD_G               => TPD_G,
            SYNTH_MODE_G        => "xpm",
            MEMORY_TYPE_G       => "block",
            COMMON_CLK_G        => false,  -- In this design in general axisClk is not same as axilClk (see top module)
            DATA_BYTES_G        => 2,   -- 16 bit (2 byte) per clock from ADC
            RAM_ADDR_WIDTH_G    => 13,  -- Decides size of the buffer (2**13=8192 words)
            -- AXI Stream Configurations
            FIFO_MEMORY_TYPE_G  => "block",
            FIFO_ADDR_WIDTH_G   => 9,
            GEN_SYNC_FIFO_G     => false,  -- In this design in general axisClk is not same as axilClk (see top module)
            AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C)
        port map (
            -- Data to store in ring buffer (dataClk domain)
            dataClk         => adcClk,
            dataValid       => '1',     -- Always valid 
            dataValue       => adcDatA,    -- ADC channel A
            extTrig         => '0',
            -- AXI-Lite interface (axilClk domain)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(AXIL_RING_INDEX),
            axilReadSlave   => axilReadSlaves(AXIL_RING_INDEX),
            axilWriteMaster => axilWriteMasters(AXIL_RING_INDEX),
            axilWriteSlave  => axilWriteSlaves(AXIL_RING_INDEX),
            -- AXI-Stream Interface (axisClk domain)
            axisClk         => axisClk,
            axisRst         => axisRst,
            axisMaster      => dmaIbMaster,
            axisSlave       => dmaIbSlave
            );

end mapping;
