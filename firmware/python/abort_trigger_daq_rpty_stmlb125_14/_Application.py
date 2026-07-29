import pyrogue as pr

import abort_trigger_daq_rpty_stmlb125_14 as rpty
import surf.axi as axi


class Application(pr.Device):
    def __init__(self, n_adc_channels, **kwargs):
        super().__init__(**kwargs)

        self.add(rpty.TestRegister(name="TestRegister", offset=0x0, hidden=False))

        for i in range(n_adc_channels):
            self.add(axi.AxiStreamRingBuffer(name=f"AxiStreamRingBuffer[{i}]", offset=0x0100_0000 + 0x0100_0000 * i, hidden=False))
