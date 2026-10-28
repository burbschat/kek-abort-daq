import pyrogue as pr


class ThrTrig(pr.Device):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        self._trigStatesEnum = {
            0x0: "IDLE",
            0x1: "ARMED",
            0x2: "HYSTERESIS",
        }

        self._trigDirectionsEnum = {
            0x0: "ABOVE",
            0x1: "BELOW",
        }

        # Signals in firmware scale with DATA_WIDTH_G but for registers
        # we don't care as they are layed out to always be 32 bit and the
        # unused bits return 0.
        self.add(
            pr.RemoteVariable(
                name="Threshold",
                description="Trigger threshold",
                offset=0x0,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="Hysteresis",
                description="Hysteresis around the threshold. Ignored if hysteresis disabled.",
                offset=0x4,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="Direction",
                description="Trigger direction (0=trigger when above, 1=trigger when below).",
                offset=0x08,
                bitOffset=0,
                bitSize=1,
                mode="RW",
                enum=self._trigDirectionsEnum,
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="HysteresisEn",
                description="Hysteresis enable bit",
                offset=0x08,
                bitOffset=1,
                bitSize=1,
                mode="RW",
                hidden=False,
            )
        )

        # Perhaps move to different 32 bit register to not have the problem of
        # rogue GUI writes the last value in the local copy of the variable on
        # write of another variable...
        self.add(
            pr.RemoteVariable(
                name="Arm",
                description="Set to arm trigger. Reset to 0 to disarm. Automatically reset when trigger FSM returns to idle.",
                offset=0x08,
                bitOffset=2,
                bitSize=1,
                mode="WO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="KeepArm",
                description="Set to automatically re-arm after triggered.",
                offset=0x08,
                bitOffset=3,
                bitSize=1,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="ForceTrig",
                description="Force single trigger pulse output. Does not affect the state of the FSM.",
                offset=0x08,
                bitOffset=4,
                bitSize=1,
                mode="WO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="TriggerOut",
                description="Trigger output signal readback",
                offset=0x08,
                bitOffset=5,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="stateReg",
                description="Register indicating the state of the trigger FSM",
                offset=0x0C,
                bitSize=8,
                mode="RO",
                pollInterval=1,
                enum=self._trigStatesEnum,
            )
        )

        # Publish state name as string for use in PyDM displays
        self.add(
            pr.LinkVariable(
                name="stateStr",
                description="String indicating the current state",
                mode="RO",
                dependencies=[self.stateReg],
                linkedGet=lambda: self.getStateString(self.stateReg.value()),
            )
        )

    def getStateString(self, stateIdx):
        if stateIdx in self._trigStatesEnum:
            return self._trigStatesEnum[stateIdx]
        else:
            return "UNDEFINED"
