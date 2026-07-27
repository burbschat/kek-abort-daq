library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiPkg.all;

library work;
use work.AppPkg.all;

library axi_soc_7000_core;
use axi_soc_7000_core.AxiSoc7000Pkg.all;

library unisim;
use unisim.vcomponents.all;

entity AbortTriggerDaqRptyStmlb125_14 is
    generic(
        TPD_G        : time := 1 ns;
        BUILD_INFO_G : BuildInfoType
        );
    port (
        -- Ports forwared from CPU
        DDR_cas_n         : inout std_logic;
        DDR_cke           : inout std_logic;
        DDR_ck_n          : inout std_logic;
        DDR_ck_p          : inout std_logic;
        DDR_cs_n          : inout std_logic;
        DDR_reset_n       : inout std_logic;
        DDR_odt           : inout std_logic;
        DDR_ras_n         : inout std_logic;
        DDR_we_n          : inout std_logic;
        DDR_ba            : inout std_logic_vector (2 downto 0);
        DDR_addr          : inout std_logic_vector (14 downto 0);
        DDR_dm            : inout std_logic_vector (3 downto 0);
        DDR_dq            : inout std_logic_vector (31 downto 0);
        DDR_dqs_n         : inout std_logic_vector (3 downto 0);
        DDR_dqs_p         : inout std_logic_vector (3 downto 0);
        FIXED_IO_mio      : inout std_logic_vector (53 downto 0);
        FIXED_IO_ddr_vrn  : inout std_logic;
        FIXED_IO_ddr_vrp  : inout std_logic;
        FIXED_IO_ps_srstb : inout std_logic;
        FIXED_IO_ps_clk   : inout std_logic;
        FIXED_IO_ps_porb  : inout std_logic;
        -- ADC clock inputs
        adcClkP           : in    sl;
        adcClkN           : in    sl;
        -- LEDs
        led_o             : out   slv(7 downto 0);
        -- ADC data lines
        adc_dat_a_i       : in    slv(15 downto 0);
        adc_dat_b_i       : in    slv(15 downto 0)
        );
end entity AbortTriggerDaqRptyStmlb125_14;

architecture top_level of AbortTriggerDaqRptyStmlb125_14 is

    signal adcClk : sl;

    -- For now there is no crossbar in this module...
    -- constant NUM_AXIL_MASTERS_C : positive := 3;
    -- constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, APP_ADDR_OFFSET_C, 31, 28);

    signal axilWriteMaster : AxiLiteWriteMasterType;
    signal axilWriteSlave  : AxiLiteWriteSlaveType;
    signal axilReadMaster  : AxiLiteReadMasterType;
    signal axilReadSlave   : AxiLiteReadSlaveType;

    signal dmaBuffGrpPause : slv(7 downto 0);  -- Not used/required?
    -- Outbound (from CPU to PL)
    signal dmaObMasters    : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
    signal dmaObSlaves     : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
    -- Inbound (from PL to CPU)
    signal dmaIbMasters    : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
    signal dmaIbSlaves     : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

    -- Clocks
    signal auxClk     : sl;             -- Aux clock, output from core module
    signal auxRst     : sl;
    signal appClk     : sl;  -- Used by application, also input into core module
    signal appRst     : sl;
    signal appUserRst : sl;
    signal dmaClk     : sl;  -- Used by DMA, also in application, output from core module
    signal dmaRst     : sl;

begin
    -------------------
    -- Clock Assignment
    -------------------
    -- appClk is auxClk from the core (100 MHz).
    -- Could use the adc clock as the app clock (125 MHz) to make processing
    -- of ADC data easier? Would have to synchronize the resets in that case.
    appClk <= auxClk;
    appRst <= auxRst or appUserRst;

    -------------------
    -- ADC Clock Buffer
    -------------------
    -- Obtain single ended clock signal from the differential one
    U_IBUFDS : IBUFDS
        port map(
            I  => adcClkP,
            IB => adcClkN,
            O  => adcClk);

    -----------------------
    -- Common Platform Core
    -----------------------
    U_core : entity axi_soc_7000_core.AxiSoc7000Core
        generic map (
            TPD_G                => TPD_G,
            BUILD_INFO_G         => BUILD_INFO_G,
            COMMON_AUX_APP_CLK_G => false  -- appClk = auxClk?
            )
        port map(
            -- DDR ports connected to CPU
            DDR_addr(14 downto 0)     => DDR_addr(14 downto 0),
            DDR_ba(2 downto 0)        => DDR_ba(2 downto 0),
            DDR_cas_n                 => DDR_cas_n,
            DDR_ck_n                  => DDR_ck_n,
            DDR_ck_p                  => DDR_ck_p,
            DDR_cke                   => DDR_cke,
            DDR_cs_n                  => DDR_cs_n,
            DDR_dm(3 downto 0)        => DDR_dm(3 downto 0),
            DDR_dq(31 downto 0)       => DDR_dq(31 downto 0),
            DDR_dqs_n(3 downto 0)     => DDR_dqs_n(3 downto 0),
            DDR_dqs_p(3 downto 0)     => DDR_dqs_p(3 downto 0),
            DDR_odt                   => DDR_odt,
            DDR_ras_n                 => DDR_ras_n,
            DDR_reset_n               => DDR_reset_n,
            DDR_we_n                  => DDR_we_n,
            FIXED_IO_ddr_vrn          => FIXED_IO_ddr_vrn,
            FIXED_IO_ddr_vrp          => FIXED_IO_ddr_vrp,
            FIXED_IO_mio(53 downto 0) => FIXED_IO_mio(53 downto 0),
            FIXED_IO_ps_clk           => FIXED_IO_ps_clk,
            FIXED_IO_ps_porb          => FIXED_IO_ps_porb,
            FIXED_IO_ps_srstb         => FIXED_IO_ps_srstb,

            -- ADC Clock and Reset Monitoring
            adcClk => adcClk,
            -- LTC2145CUP-14 does not seem to have some sort of reset output, so 
            -- can't really assign a sensible reset here.
            adcRst => '0',

            -- AUX Clock and Reset
            auxClk => auxClk,           -- 100 MHz
            auxRst => auxRst,

            -- Application AXI-Lite Interfaces [0x6000_0000:0x7FFF_FFFF] (appClk domain)
            appClk         => appClk,  -- Input, the user decides the frequency
            appRst         => appRst,
            appUserRst     => appUserRst,
            appReadMaster  => axilReadMaster,
            appReadSlave   => axilReadSlave,
            appWriteMaster => axilWriteMaster,
            appWriteSlave  => axilWriteSlave,

            -- DMA Interfaces  (dmaClk domain)
            dmaClk          => dmaClk,  -- 125 MHz
            dmaRst          => dmaRst,
            dmaBuffGrpPause => dmaBuffGrpPause,
            dmaObMasters    => dmaObMasters,
            dmaObSlaves     => dmaObSlaves,
            dmaIbMasters    => dmaIbMasters,
            dmaIbSlaves     => dmaIbSlaves);

    --------------
    -- Application
    --------------
    U_App : entity work.Application
        generic map (
            TPD_G            => TPD_G,
            -- If there was another crossbar at the top module we may reference
            -- the baseAddr from there but for now there is non, so must set the
            -- (full 32 bits) of base addres here manually.
            AXIL_BASE_ADDR_G => AXIL_REG_BASE_ADDR_C + APP_ADDR_OFFSET_C  -- AXIL_CONFIG_C(APP_INDEX_C).baseAddr  -- Global base + offset should be 0x6000_0000
            )
        port map (
            leds            => led_o,
            -- AXI-Lite Interface (appClk domain)
            axilClk         => appClk,
            axilRst         => appRst,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            -- DMA Interface (dmaClk domain)
            axisClk         => dmaClk,
            axisRst         => dmaRst,
            dmaIbMaster     => dmaIbMasters(0),
            dmaIbSlave      => dmaIbSlaves(0),
            -- ADC data lines (there no control input to the ADCs, so there
            -- only is the data stream, thus directly pipe it into the
            -- Application)
            adcClk          => adcClk,
            adcDatA         => adc_dat_a_i,
            adcDatB         => adc_dat_b_i);

end architecture top_level;
