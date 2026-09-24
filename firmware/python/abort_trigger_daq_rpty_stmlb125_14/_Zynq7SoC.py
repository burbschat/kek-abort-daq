import pyrogue as pr

import axi_soc_7000_core  as socCore
import abort_trigger_daq_rpty_stmlb125_14 as target


class Zynq7SoC(pr.Device):
    def __init__(self, n_adc_channels, clkFreq=125.0e6, **kwargs):
        super().__init__(**kwargs)

        self.add(socCore.AxiSocCore(
            offset      = 0x0000_0000,
            hidden      = False,
        ))

        self.add(target.Application(
            offset         = 0x2000_0000,
            n_adc_channels = n_adc_channels,
            clkFreq        = clkFreq,
            expand         = True,
            enabled        = True,
        ))
