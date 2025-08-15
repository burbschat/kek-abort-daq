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
        adc_clk_p_i       : in    sl;
        adc_clk_n_i       : in    sl
        );
end entity AbortTriggerDaqRptyStmlb125_14;

architecture top_level of AbortTriggerDaqRptyStmlb125_14 is

    signal adc_clk : sl;

begin

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
            -- Ports forwarded from CPU
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
            -- Global clock synchronous to ADC clock
            pl_clk => adc_clk
            );

end architecture top_level;
