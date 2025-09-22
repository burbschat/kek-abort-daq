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
        TPD_G : time := 1 ns
     -- AXIL_BASE_ADDR_G : slv(31 downto 0)
        );
    port (
        pl_clk          : in  sl;
        leds            : out slv(7 downto 0);
        -- AXI-Lite Interface (TODO: axilClk domain?)
        axilWriteMaster : in  AxiLiteWriteMasterType;
        axilWriteSlave  : out AxiLiteWriteSlaveType;
        axilReadMaster  : in  AxiLiteReadMasterType;
        axilReadSlave   : out AxiLiteReadSlaveType;
        -- DMA Interface (TODO: dmaClk domain?)
        -- dmaClk          : in  sl;
        -- dmaRst          : in  sl;
        dmaIbMaster     : out AxiStreamMasterType;
        dmaIbSlave      : in  AxiStreamSlaveType;
        -- ADC data lines
        adcDatA         : in  slv(15 downto 0);
        adcDatB         : in  slv(15 downto 0)
        );
end Application;

architecture mapping of Application is

    signal count : slv(31 downto 0) := (others => '0');

begin

    -- Some static registers for testing
    U_REG_STATIC : entity axi_soc_7000_core.AxiTestRegister
        port map(
            pl_clk          => pl_clk,
            axilReadMaster  => axilReadMaster,
            axilReadSlave   => axilReadSlave,
            axilWriteMaster => axilWriteMaster,
            axilWriteSlave  => axilWriteSlave);

    -- LED blinking
    process(pl_clk)
    begin
        if rising_edge(pl_clk) then
            -- count <= count + 1;
            -- At 125MHz the 26th bit should give visible LED blinking
            -- leds  <= count(29 downto 29 - 7);
            -- Display ADC A Data bits on LEDs
            leds <= adcDatA(7 downto 0);
        end if;
    end process;

end mapping;
