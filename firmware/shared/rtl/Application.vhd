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
        adcDat          : in  Slv16Array(1 downto 0));
end Application;

architecture mapping of Application is

    constant NUM_ADC_CH_C       : natural                            := 2;
    constant ADC_TDEST_ROUTES_C : Slv8Array(NUM_ADC_CH_C-1 downto 0) := (0 => x"00", 1 => x"01");

    constant NUM_AXIL_MASTERS_C   : natural := 4;
    constant AXIL_TEST_INDEX      : natural := 0;
    constant AXIL_RING_INDEX_BASE : natural := 1;  -- Must accomodate NUM_ADC_CH_C channels
    constant AXIL_THR_TRIG_INDEX  : natural := AXIL_RING_INDEX_BASE + NUM_ADC_CH_C;  -- 3

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 28, 24);

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

    -- Axi stream for ring buffers
    signal axisMasters : AxiStreamMasterArray(NUM_ADC_CH_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
    signal axisSlaves  : AxiStreamSlaveArray(NUM_ADC_CH_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

    signal count : slv(31 downto 0) := (others => '0');

    signal buffTrig : sl := '0';

begin

    --------------------
    -- AXI-Lite Crossbar
    --------------------

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

    -----------------
    -- Test Registers
    -----------------

    U_REG_STATIC : entity axi_soc_7000_core.AxiTestRegister
        port map(
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(AXIL_TEST_INDEX),
            axilReadSlave   => axilReadSlaves(AXIL_TEST_INDEX),
            axilWriteMaster => axilWriteMasters(AXIL_TEST_INDEX),
            axilWriteSlave  => axilWriteSlaves(AXIL_TEST_INDEX)
            );

    ---------------
    -- LED blinking
    ---------------

    process(axilClk)
    begin
        if rising_edge(axilClk) then
            count <= count + 1;

            -- At 125MHz the 26th bit should give visible LED blinking
            leds <= count(29 downto 29 - 7);
        end if;
    end process;

    ------------------------
    -- ADC Data Ring Buffers
    ------------------------

    genAxiStreamRingBuffers : for i in 0 to 1 generate
        U_AxiStreamRingBuffer : entity surf.AxiStreamRingBuffer
            generic map (
                TPD_G               => TPD_G,
                SYNTH_MODE_G        => "xpm",
                MEMORY_TYPE_G       => "block",
                COMMON_CLK_G        => false,  -- In this design in general axisClk is not same as axilClk (see top module)
                DATA_BYTES_G        => 2,  -- 16 bit (2 byte) per clock from ADC
                RAM_ADDR_WIDTH_G    => 13,  -- Decides size of the buffer (2**13=8192 words)
                -- AXI Stream Configurations
                FIFO_MEMORY_TYPE_G  => "block",
                FIFO_ADDR_WIDTH_G   => 9,
                GEN_SYNC_FIFO_G     => false,  -- In this design in general axisClk is not same as axilClk (see top module)
                AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C)
            port map (
                -- Data to store in ring buffer (dataClk domain)
                dataClk         => adcClk,
                dataValid       => '1',    -- Always valid 
                dataValue       => adcDat(i),  -- ADC channel A
                extTrig         => buffTrig,
                -- AXI-Lite interface (axilClk domain)
                axilClk         => axilClk,
                axilRst         => axilRst,
                axilReadMaster  => axilReadMasters(AXIL_RING_INDEX_BASE + i),
                axilReadSlave   => axilReadSlaves(AXIL_RING_INDEX_BASE + i),
                axilWriteMaster => axilWriteMasters(AXIL_RING_INDEX_BASE + i),
                axilWriteSlave  => axilWriteSlaves(AXIL_RING_INDEX_BASE + i),
                -- AXI-Stream Interface (axisClk domain)
                axisClk         => axisClk,
                axisRst         => axisRst,
                axisMaster      => axisMasters(i),
                axisSlave       => axisSlaves(i)
                );
    end generate genAxiStreamRingBuffers;

    -- Mux AXI streams and stick on the correct destinations (ROUTED mode)
    U_Mux : entity surf.AxiStreamMux
        generic map (
            TPD_G          => TPD_G,
            NUM_SLAVES_G   => NUM_ADC_CH_C,
            MODE_G         => "ROUTED",
            TDEST_ROUTES_G => ADC_TDEST_ROUTES_C,
            PIPE_STAGES_G  => 1)
        port map (
            -- Clock and reset
            axisClk      => axisClk,
            axisRst      => axisRst,
            -- Slaves
            sAxisMasters => axisMasters,
            sAxisSlaves  => axisSlaves,
            -- Master
            mAxisMaster  => dmaIbMaster,
            mAxisSlave   => dmaIbSlave);

    ------------------------
    -- ADC Threshold Trigger
    ------------------------

    ThrTrig_inst : entity work.ThrTrig
        generic map(
            TPD_G           => TPD_G,
            DATA_WIDTH_G    => 16,
            SAFE_HYST_EN_G  => true,
            NUM_ADDR_BITS_G => 32)
        port map(
            adcClk          => adcClk,
            adcRst          => '0',
            adcDat          => adcDat(0),  -- For now just on channel 0
            trigOut         => buffTrig,
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilWriteMaster => axilWriteMasters(AXIL_THR_TRIG_INDEX),
            axilWriteSlave  => axilWriteSlaves(AXIL_THR_TRIG_INDEX),
            axilReadMaster  => axilReadMasters(AXIL_THR_TRIG_INDEX),
            axilReadSlave   => axilReadSlaves(AXIL_THR_TRIG_INDEX)
            );

end mapping;
