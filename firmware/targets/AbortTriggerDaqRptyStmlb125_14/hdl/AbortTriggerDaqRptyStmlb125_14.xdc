create_clock -name adcClkP -period  8.0 [get_ports {adcClkP}]

# set_clock_groups -asynchronous \
#     -group [get_clocks -of_objects [get_pins U_Core/adcClk]] \
#     -group [get_clocks -of_objects [get_pins U_core/REAL_CPU.U_CPU/U_CPU/FCLK_CLK0_0]] \
#     -group [get_clocks -of_objects [get_pins U_core/REAL_CPU.U_CPU/U_CPU/FCLK_CLK1_0]] \
#     -group [get_clocks -of_objects [get_pins U_core/REAL_CPU.U_CPU/U_CPU/FCLK_CLK2_0]] \

set_clock_groups -asynchronous \
    -group [get_clocks adcClkP] \
    -group [get_clocks clk_fpga_0] \
    -group [get_clocks clk_fpga_1] \
    -group [get_clocks clk_fpga_2]
