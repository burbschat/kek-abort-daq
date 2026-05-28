import rogue
import rogue.interfaces.stream as stream
import rogue.utilities.fileio
import rogue.hardware.axi
import rogue.interfaces.memory

import pyrogue as pr
import pyrogue.protocols
import pyrogue.interfaces.stream
import pyrogue.utilities.fileio
import pyrogue.utilities.prbs

import abort_trigger_daq_rpty_stmlb125_14 as target
# import axi_soc_7000_core.hardware.HW_HERE as zynq_hw
import axi_soc_7000_core as soc_core

rogue.Version.minVersion("6.5.0")


class Root(pr.Root):
    def __init__(
        self,
        ip="10.0.0.10",  # ETH Host Name (or IP address)
        top_level="",
        defaultFile="",
        zmqSrvPort=9099,  # Set to zero if dynamic (instead of static)
        **kwargs,
    ):
        super().__init__(timeout=5.0, **kwargs)

        #################################################################

        self.zmqServer = pr.interfaces.ZmqServer(root=self, addr="127.0.0.1", port=zmqSrvPort)
        self.addInterface(self.zmqServer)

        #################################################################

        # Local Variables
        self.top_level = top_level
        if self.top_level != "":
            self.defaultFile = f"{top_level}/{defaultFile}"
        else:
            self.defaultFile = defaultFile

        # File writer
        self.dataWriter = pr.utilities.fileio.StreamWriter(name="DataWriter")
        self.add(self.dataWriter)

        ##################################################################################
        ##                              Register Access
        ##################################################################################

        if ip != None:
            # Check if we can ping the device and TCP socket not open
            soc_core.connectionTest(ip)
            # Start a TCP Bridge Client, Connect remote server at 'ethReg' ports 9000 & 9001.
            self.memMap = rogue.interfaces.memory.TcpClient(ip, 9000)
        else:
            # Assume this is run ton the SoC so directly connect to kernel driver.
            self.memMap = rogue.hardware.axi.AxiMemMap("/dev/axi_memory_map")

        # Add PS hardware control
        # self.add(
        #     soc_hw.Hardware(
        #         memBase=self.memMap,
        #     )
        # )

        # Added the RFSoC device
        self.add(
            target.Zynq7SoC(
                memBase=self.memMap,
                offset=0x4000_0000,  # 32-bit address space
                expand=True,
            )
        )

        ##################################################################################
        ##                              Data Path
        ##################################################################################

        # Create rogue stream arrays
        if ip != None:
            self.testStream = stream.TcpClient(ip,10000)
        else:
            self.testStream = rogue.hardware.axi.AxiStreamDma('/dev/axi_stream_dma_0', 0,  True)

        self.testStreamDropFifo = pr.interfaces.stream.Fifo(name=f'TestStreamDropFifo', maxDepth=1, hidden=False) # Drop if more than 1 frame in FIFO

        self.add(self.testStreamDropFifo)

        # Connect test stream
        self.testStream >> self.dataWriter.getChannel(0)
        self.testStream >> self.testStreamDropFifo

        # Debug Slave
        self.dbg = rogue.interfaces.stream.Slave()
        # Set debug mode for first 100 bytes, with name myDebug
        self.dbg.setDebug(2048*8,"myDebug")
        # Add the debug slave as a second slave
        self.testStream >> self.dbg

    def start(self,**kwargs):
        super(Root, self).start(**kwargs)

        # Read all registers once on init
        self.ReadAll()
