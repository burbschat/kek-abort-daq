import pyrogue as pr

import abort_trigger_daq_rpty_stmlb125_14 as rpty


class AbortTrigs(pr.Device):
    def __init__(self, clkFreq=125.0e6, **kwargs):
        super().__init__(**kwargs)

        n_adc_channels = 2
        self._trigger_type_names = ["Thr", "Tot", "RevSyncInt"]
        n_trig_types = len(self._trigger_type_names)

        # self.add(
        #     pr.RemoteVariable(
        #         name="EnMask",
        #         description="Trigger type enable mask",
        #         offset=0x0,
        #         bitOffset=0,
        #         bitSize=2,
        #         mode="RW",
        #         hidden=False,
        #     )
        # )

        # self.add(
        #     pr.RemoteVariable(
        #         name="ChMask",
        #         description="ADC channel enable mask",
        #         offset=0x4,
        #         bitOffset=0,
        #         bitSize=3,
        #         mode="RW",
        #         hidden=False,
        #     )
        # )

        # Add each bit as a single variable with more intuitive name
        for i in range(n_trig_types):
            self.add(
                pr.RemoteVariable(
                    name=f"{self._trigger_type_names[i]}En",
                    description=f"Enable the {self._trigger_type_names[i]} type trigger in the trigger output or chain",
                    offset=0x0,
                    bitOffset=i,
                    bitSize=1,
                    mode="RW",
                    hidden=False,
                )
            )

        for i in range(n_adc_channels):
            self.add(
                pr.RemoteVariable(
                    name=f"Ch{i}En",
                    description=f"Enable channel {i} in the trigger output or chain",
                    offset=0x4,
                    bitOffset=i,
                    bitSize=1,
                    mode="RW",
                    hidden=False,
                )
            )

        offset_increment = 0x0001_0000
        offset = offset_increment
        for i in range(n_adc_channels):
            self.add(rpty.ThrTrig(name=f"ThrTrig[{i}]", offset=offset))
            offset += offset_increment

        for i in range(n_adc_channels):
            self.add(rpty.TotTrig(name=f"TotTrig[{i}]", offset=offset, clkFreq=clkFreq))
            offset += offset_increment

        for i in range(n_adc_channels):
            self.add(rpty.RevSyncIntTrig(name=f"RevSyncIntTrig[{i}]", offset=offset, clkFreq=clkFreq, numWnds=2))
            offset += offset_increment
