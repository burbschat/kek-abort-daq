import pyrogue as pr


class RevSyncIntTrig(pr.Device):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        self._trigStatesEnum = {
            0x0: "IDLE",
            0x1: "ARMED",
        }

        # Signals in firmware scale with DATA_WIDTH_G but for registers
        # we don't care as they are layed out to always be 32 bit and the
        # unused bits return 0.
        self.add(
            pr.RemoteVariable(
                name="DatIntThrLower",
                description="Trigger threshold applied to integral value (lower bytes)",
                offset=0x0,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="DatIntThrUpper",
                description="Trigger threshold applied to integral value (upper bytes)",
                offset=0x4,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="RevSig",
                description="Revolution signal readback",
                offset=0x8,
                bitOffset=0,
                bitSize=1,
                mode="RO",
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
                name="ForceRevSyncTrig",
                description="Force trigger. Does not affect the state of the FSM.",
                offset=0x08,
                bitOffset=4,
                bitSize=1,
                mode="WO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="RevSyncTrig",
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
                name="ForceThrCross",
                description="Force threshold crossed strobe output",
                offset=0x08,
                bitOffset=6,
                bitSize=1,
                mode="WO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="ThrCross",
                description="Threshold strobe output readback",
                offset=0x08,
                bitOffset=7,
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

        self.add(
            pr.RemoteVariable(
                name="DatIntLower",
                description="Current integral value (lower bytes)",
                offset=0x38,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="DatIntUpper",
                description="Current integral value (upper bytes)",
                offset=0x3C,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="DatIntPrevLower",
                description="Integral value at last deadline (lower bytes)",
                offset=0x40,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="DatIntPrevUpper",
                description="Integral value at last deadline (upper bytes)",
                offset=0x44,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

    def getStateString(self, stateIdx):
        if stateIdx in self._trigStatesEnum:
            return self._trigStatesEnum[stateIdx]
        else:
            return "UNDEFINED"
