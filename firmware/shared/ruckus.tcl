# Load RUCKUS environment and library
source $::env(RUCKUS_PROC_TCL)

# Load submodule code
loadRuckusTcl $::env(TOP_DIR)/submodules/surf
loadRuckusTcl $::env(TOP_DIR)/submodules/axi-soc-7000-core/hardware/RedPitayaStemlab125-14

# Load RTL code
loadSource -dir  "$::DIR_PATH/rtl"

# TODO Load IP cores
# loadIpCore -dir "$::DIR_PATH/ip"

# Updating the impl_1 strategy
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# Load simulation only code
# loadSource -sim_only -dir "$::DIR_PATH/tb" -fileType "VHDL 2008"
# Load VIVADO unisim components
loadSource -sim_only -lib unisim -path "$::env(XILINX_VIVADO)/data/vhdl/src/unisims/unisim_VPKG.vhd"
loadSource -sim_only -lib unisim -path "$::env(XILINX_VIVADO)/data/vhdl/src/unisims/unisim_VCOMP.vhd"
loadSource -sim_only -lib unisim -dir  "$::env(XILINX_VIVADO)/data/vhdl/src/unisims/primitive"
