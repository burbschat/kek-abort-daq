library ieee;
use ieee.std_logic_1164.all;

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
-- generic();
    port (
        -- DDR3 Ports
        DDR_addr          : inout std_logic_vector (14 downto 0);
        DDR_ba            : inout std_logic_vector (2 downto 0);
        DDR_cas_n         : inout std_logic;
        DDR_ck_n          : inout std_logic;
        DDR_ck_p          : inout std_logic;
        DDR_cke           : inout std_logic;
        DDR_cs_n          : inout std_logic;
        DDR_dm            : inout std_logic_vector (3 downto 0);
        DDR_dq            : inout std_logic_vector (31 downto 0);
        DDR_dqs_n         : inout std_logic_vector (3 downto 0);
        DDR_dqs_p         : inout std_logic_vector (3 downto 0);
        DDR_odt           : inout std_logic;
        DDR_ras_n         : inout std_logic;
        DDR_reset_n       : inout std_logic;
        DDR_we_n          : inout std_logic;
        FIXED_IO_ddr_vrn  : inout std_logic;
        FIXED_IO_ddr_vrp  : inout std_logic;
        FIXED_IO_mio      : inout std_logic_vector (53 downto 0);
        FIXED_IO_ps_clk   : inout std_logic;
        FIXED_IO_ps_porb  : inout std_logic;
        FIXED_IO_ps_srstb : inout std_logic;

        -- ADC clock inputs
        adc_clk_p_i : in sl;
        adc_clk_n_i : in sl
        );
end entity AbortTriggerDaqRptyStmlb125_14;

architecture top_level of AbortTriggerDaqRptyStmlb125_14 is

    signal adc_clk : sl;

    signal ddr_ports : DDR3_ports;

begin

    ddr_ports.DDR_addr          <= DDR_addr;
    ddr_ports.DDR_addr          <= DDR_addr;
    ddr_ports.DDR_ba            <= DDR_ba;
    ddr_ports.DDR_cas_n         <= DDR_cas_n;
    ddr_ports.DDR_ck_n          <= DDR_ck_n;
    ddr_ports.DDR_ck_p          <= DDR_ck_p;
    ddr_ports.DDR_cke           <= DDR_cke;
    ddr_ports.DDR_cs_n          <= DDR_cs_n;
    ddr_ports.DDR_dm            <= DDR_dm;
    ddr_ports.DDR_dq            <= DDR_dq;
    ddr_ports.DDR_dqs_n         <= DDR_dqs_n;
    ddr_ports.DDR_dqs_p         <= DDR_dqs_p;
    ddr_ports.DDR_odt           <= DDR_odt;
    ddr_ports.DDR_ras_n         <= DDR_ras_n;
    ddr_ports.DDR_reset_n       <= DDR_reset_n;
    ddr_ports.DDR_we_n          <= DDR_we_n;
    ddr_ports.FIXED_IO_ddr_vrn  <= FIXED_IO_ddr_vrn;
    ddr_ports.FIXED_IO_ddr_vrp  <= FIXED_IO_ddr_vrp;
    ddr_ports.FIXED_IO_mio      <= FIXED_IO_mio;
    ddr_ports.FIXED_IO_ps_clk   <= FIXED_IO_ps_clk;
    ddr_ports.FIXED_IO_ps_porb  <= FIXED_IO_ps_porb;
    ddr_ports.FIXED_IO_ps_srstb <= FIXED_IO_ps_srstb;

    -----------------------
    -- Top level clock generation
    -----------------------
    U_IBUFDS : IBUFDS
        port map(
            I  => adc_clk_p_i,
            IB => adc_clk_n_i,
            O  => adc_clk);

    -----------------------
    -- Common Platform Core
    -----------------------
    U_core : entity axi_soc_7000_core.AxiSoc7000Core
        port map(
            glob_clk => adc_clk,
            ddr_ports => ddr_ports
            );




end architecture top_level;
