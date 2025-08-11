library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

package AppPkg is

   constant NUM_ADC_CH_C     : positive := 2;
   constant NUM_DAC_CH_C     : positive := 2;

   -------------------------------------------------
   -- DMA[lane=0].inbound  = ADC/DAC ring buffers
   -------------------------------------------------
   -- constant DMA_SIZE_C : positive := 1;

   -- constant AXIL_CLK_FREQ_C   : real := 100.0E+6;               -- Units of Hz
   -- constant AXIL_CLK_PERIOD_C : real := (1.0/AXIL_CLK_FREQ_C);  -- Units of seconds

end package AppPkg;
