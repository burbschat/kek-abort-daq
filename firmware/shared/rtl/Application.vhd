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
        pl_clk : in  sl;
        led    : out sl
        );
end Application;

architecture mapping of Application is

    signal led_state : sl              := '0';
    signal count     : slv(31 downto 0) := (others => '0');

begin

    led <= led_state;

    process(pl_clk)
    begin
        if rising_edge(pl_clk) then
            count <= count + 1;
            -- At 125MHz the 26th bit should give visible LED blinking
            led_state <= count(26);
        end if;
    end process;

end mapping;
