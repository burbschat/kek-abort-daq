import pyrogue as pr

import abort_trigger_daq_rpty_stmlb125_14 as rpty


class Application(pr.Device):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        self.add(rpty.TestRegister(name="TestRegister", offset=0x0, hidden=False))
