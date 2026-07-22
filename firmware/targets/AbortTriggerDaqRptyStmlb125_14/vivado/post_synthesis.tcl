##############################
# Get variables and procedures
##############################
source -quiet $::env(RUCKUS_DIR)/vivado_env_var.tcl
source $::env(RUCKUS_PROC_TCL)

######################################################
# Bypass the debug chipscope generation via return cmd
# ELSE ... comment out the return to include chipscope
######################################################
# return

############################
## Open the synthesis design
############################
open_run synth_1

###############################
## Set the name of the ILA core
###############################
set ilaName u_ila_0

##################
## Create the core
##################
CreateDebugCore ${ilaName}

#######################
## Set the record depth
#######################
# set_property C_DATA_DEPTH 8192 [get_debug_cores ${ilaName}]
# set_property C_DATA_DEPTH 1024 [get_debug_cores ${ilaName}]
set_property C_DATA_DEPTH 1024 [get_debug_cores ${ilaName}]

#################################
## Set the clock for the ILA core
#################################
SetDebugCoreClk ${ilaName} {U_App/axilClk}

#######################
## Set the debug Probes
#######################

ConfigProbe ${ilaName} {U_App/axilRst}

# AXI Stream ring buffer output
ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/axisMaster*}
ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/axisSlave*}

# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/TX_FIFO/sAxisMaster*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/TX_FIFO/sAxisSlave*}

# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/dataWriteMaster[*]*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/dataWriteSlave[*]*}
# # ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/dataWriteCtrl*}

# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/descWriteMaster[*]*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/descWriteSlave[*]*}

# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/mAxiWriteMaster[*]*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/mAxiWriteSlave[*]*}
# # ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_ChanGen[0].U_DmaWriteMux/mAxiWriteCtrl*}

# Data written to ring buffer
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/dataR[ramWrData]*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/dataR[nextAddr]*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/dataR[ramWrEn]*}

# Data read from ring buffer
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/axilR[rdEn]*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/axilR[ramRdAddr]*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/axilR[wordCnt]*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/axilR[rdEn]*}
# ConfigProbe ${ilaName} {U_App/U_AxiStreamRingBuffer/ramRdData*}

# Interface to CPU
# ConfigProbe ${ilaName} {U_core/REAL_CPU.U_CPU/U_CPU/axi_dma_*}

# Protocol convert in/out
# ConfigProbe ${ilaName} {U_core/REAL_CPU.U_CPU/U_CPU/axi_protocol_convert_2/m_axi_*}
# ConfigProbe ${ilaName} {U_core/REAL_CPU.U_CPU/U_CPU/axi_protocol_convert_2/s_axi_*}

# # DMA interrupt signal
ConfigProbe ${ilaName} {U_core/U_DMA/dmaIrq}
#
# # DMA Descriptor state (check if stuck in WAIT_S)
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/stateMirror*}
# # Check IRQ assert conditions
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intReqCountMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/holdoffCompare*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/forceIntMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intSwAckReqMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intEnableMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intAckCountMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intCompValid*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/invalidCount*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intDiffValid*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/diffCnt*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intSwAckEn*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intReqEnMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intHoldoffCountMirror*}
# ConfigProbe ${ilaName} {U_core/U_DMA/U_V2Gen/U_DmaDesc/intHoldoffMirror*}

# DMA AXI signals
# With Read/Write path Mux
ConfigProbe ${ilaName} {U_core/U_DMA/U_WritePathMux/sAxiWriteMasters[*]*}
ConfigProbe ${ilaName} {U_core/U_DMA/U_WritePathMux/sAxiWriteSlaves[*]*}
ConfigProbe ${ilaName} {U_core/U_DMA/U_WritePathMux/mAxiWriteMaster[*]*}
ConfigProbe ${ilaName} {U_core/U_DMA/U_WritePathMux/mAxiWriteSlave[*]*}

ConfigProbe ${ilaName} {U_core/U_DMA/U_ReadPathMux/sAxiReadMasters[*]*}
ConfigProbe ${ilaName} {U_core/U_DMA/U_ReadPathMux/sAxiReadSlaves[*]*}
ConfigProbe ${ilaName} {U_core/U_DMA/U_ReadPathMux/mAxiReadMaster[*]*}
ConfigProbe ${ilaName} {U_core/U_DMA/U_ReadPathMux/mAxiReadSlave[*]*}
#
# Without Read/Write path Mux
# ConfigProbe ${ilaName} {U_core/U_DMA/axiWriteMaster[*]*}
# ConfigProbe ${ilaName} {U_core/U_DMA/axiWriteSlave[*]*}
# ConfigProbe ${ilaName} {U_core/U_DMA/axiReadMaster[*]*}
# ConfigProbe ${ilaName} {U_core/U_DMA/axiReadSlave[*]*}
#
# AXI-Lite bus used by descriptor
ConfigProbe ${ilaName} {U_core/REAL_CPU.U_CPU/U_CPU/axi_dmactrl_*}

##########################
## Write the port map file
##########################
WriteDebugProbes ${ilaName}
