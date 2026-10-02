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

# Application specific ports (bank 35, 3.3V logic), routed to headers on the
# side of the board (can be used with a daughter board/hat).
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports { abortReq }] # DIO0_P
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 } [get_ports { revSig }] # DIO0_N
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { injSig }] # DIO1_P
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { extTrig }] # DIO1_N
