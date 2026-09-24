import pyrogue as pr

import abort_trigger_daq_rpty_stmlb125_14 as rpty
import surf.axi as axi


class Application(pr.Device):
    def __init__(self, n_adc_channels, clkFreq=125.0e6, **kwargs):
        super().__init__(**kwargs)

        self.add(rpty.TestRegister(name="TestRegister", offset=0x0, hidden=False))

        offset_increment = 0x0100_0000
        offset = offset_increment
        for i in range(n_adc_channels):
            self.add(axi.AxiStreamRingBuffer(name=f"AxiStreamRingBuffer[{i}]", offset=offset, hidden=False))
            offset += offset_increment

        self.add(rpty.RevSigCtrl(name="RevSigCtrl", offset=offset, clkFreq=clkFreq))
        offset += offset_increment

        self.add(rpty.AbortTrigs(name="AbortTrigs", offset=offset, clkFreq=clkFreq))
