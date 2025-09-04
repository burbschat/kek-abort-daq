import pyrogue as pr

import axi_soc_7000_core  as socCore
import abort_trigger_daq_rpty_stmlb125_14 as target


class Zynq7SoC(pr.Device):
    def __init__(self,**kwargs):
        super().__init__(**kwargs)

        self.add(socCore.AxiSocCore(
            offset      = 0x0000_0000,
        ))

        # self.add(target.Application(
        #     offset  = 0xA000_0000,
        #     expand  = True,
        #     enabled = False, # Do not configure until after DSP clock stable
        # ))
