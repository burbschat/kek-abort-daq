import pyrogue as pr

import abort_trigger_daq_rpty_stmlb125_14 as rpty


class AbortTrigs(pr.Device):
    def __init__(self, clkFreq=125.0e6, **kwargs):
        super().__init__(**kwargs)

        clkFreqMhz = clkFreq * 1e-6

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

        self.add(
            pr.RemoteVariable(
                name="InjSig",
                description="Injection signal readback",
                offset=0x8,
                bitOffset=0,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjSigDlyCntRun",
                description="Injection signal delay counter running flag",
                offset=0x8,
                bitOffset=1,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjVetActive",
                description="Injection veto currently active (veto signal high)",
                offset=0x8,
                bitOffset=2,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjSigDly",
                description="Injection signal delay (in clock cycles)",
                minimum=2,
                offset=0xC,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.LinkVariable(
                name="InjSigDlyUs",
                description="Injection signal delay (in us)",
                mode="RW",
                units="us",
                disp="{:0.5g}",
                dependencies=[self.InjSigDly],
                linkedGet=lambda: (float(self.InjSigDly.value()) * (1.0 / clkFreqMhz)),
                linkedSet=lambda value, write: self.InjSigDly.set(int(value / (1.0 / clkFreqMhz))),
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjSigDlyCnt",
                description="Injection signal delay counter current value",
                offset=0x10,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjVetWndLen",
                description="Injection veto window length (in clock cycles)",
                minimum=1,
                offset=0x14,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.LinkVariable(
                name="InjVetWndLenUs",
                description="Injection veto window length (in us)",
                mode="RW",
                units="us",
                disp="{:0.5g}",
                dependencies=[self.InjVetWndLen],
                linkedGet=lambda: (float(self.InjVetWndLen.value()) * (1.0 / clkFreqMhz)),
                linkedSet=lambda value, write: self.InjVetWndLen.set(int(value / (1.0 / clkFreqMhz))),
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjVetWndCnt",
                description="Injection veto window counter current count",
                offset=0x18,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="InjVetEn",
                description="Injection veto enable (to block trigger outputs)",
                offset=0x1C,
                bitOffset=0,
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
