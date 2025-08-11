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
