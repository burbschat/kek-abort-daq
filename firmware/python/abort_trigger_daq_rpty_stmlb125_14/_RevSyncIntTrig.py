import pyrogue as pr


class RevSyncIntTrig(pr.Device):
    def __init__(self, num_wnds=8, **kwargs):
        super().__init__(**kwargs)

        self._trigStatesEnum = {
            0x0: "IDLE",
            0x1: "ARMED",
        }

        # ------------------------------------------------------------------
        # Read-only single-bit registers
        # ------------------------------------------------------------------

        self.add(
            pr.RemoteVariable(
                name="RevSig",
                description="Revolution signal readback",
                offset=0x00,
                bitOffset=0,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="RevSigDlyCntRun",
                description="Revolution signal delay counter running",
                offset=0x00,
                bitOffset=1,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="WndAlgn",
                description="Window alignment status",
                offset=0x00,
                bitOffset=2,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="ThrCrs",
                description="Threshold crossed strobe output readback",
                offset=0x00,
                bitOffset=3,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="Trig",
                description="Trigger output signal readback",
                offset=0x00,
                bitOffset=4,
                bitSize=1,
                mode="RO",
                hidden=False,
            )
        )

        # ------------------------------------------------------------------
        # Writable single-bit registers
        # ------------------------------------------------------------------

        self.add(
            pr.RemoteVariable(
                name="Arm",
                description=(
                    "Set to arm trigger. Reset to 0 to disarm. Automatically reset when trigger FSM returns to idle."
                ),
                offset=0x04,
                bitOffset=0,
                bitSize=1,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="KeepArm",
                description="Set to automatically re-arm after triggered.",
                offset=0x04,
                bitOffset=1,
                bitSize=1,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="ForceThrCrs",
                description="Force threshold crossed strobe output.",
                offset=0x04,
                bitOffset=2,
                bitSize=1,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="ForceTrig",
                description="Force trigger. Does not affect the state of the FSM.",
                offset=0x04,
                bitOffset=3,
                bitSize=1,
                mode="RW",
                hidden=False,
            )
        )

        # ------------------------------------------------------------------
        # Read-only vector registers
        # ------------------------------------------------------------------

        self.add(
            pr.RemoteVariable(
                name="RevSigDlyCnt",
                description="Revolution signal delay counter",
                offset=0x08,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="RevSigPrdCnt",
                description="Revolution signal period counter to measure revolution signal period (in clock cycles)",
                offset=0x0C,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="RevSigPrd",
                description="Revolution signal period count (in clock cycles)",
                offset=0x10,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="WndCnt",
                description="Window length counter",
                offset=0x14,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="WndIdx",
                description="Current window index",
                offset=0x18,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="Dat",
                description="Current ADC data value",
                offset=0x1C,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="DatInt",
                description="Current integral value (integral starts at start of current window)",
                offset=0x20,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="DatIntLch",
                description="Integral value as latched at last deadline",
                offset=0x24,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="WndCntAtThrCrs",
                description="WndCnt counter value at last threshold crossing",
                offset=0x28,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="stateReg",
                description="Register indicating the state of the trigger FSM",
                offset=0x2C,
                bitSize=32,
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

        # ------------------------------------------------------------------
        # Writable vector registers
        # ------------------------------------------------------------------

        self.add(
            pr.RemoteVariable(
                name="RevSigDly",
                description="Revolution signal delay until start of first window",
                offset=0x30,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="WndIdxMax",
                description="Maximum window index (must be <= NUM_WNDS_G hard limit)",
                offset=0x34,
                bitSize=32,
                mode="RW",
                hidden=False,
            )
        )

        # ------------------------------------------------------------------
        # Per-window registers
        #
        # Each window reserves 8 registers. The firmware expression uses:
        #   x"38" + (i * 4)
        #   x"38" + (8 * 4 + i * 4)
        #
        # ------------------------------------------------------------------

        if num_wnds > 8:
            raise IndexError("num_wnds must be smaller or equal to maximal value of 8.")

        # If num_wnds larger than what is mapped in firmware, the non-mapped
        # registers will always return 0 as the addresses are reserved.
        for i in range(num_wnds):
            self.add(
                pr.RemoteVariable(
                    name=f"WndLngts[{i}]",
                    description=f"Window {i} length (in clock cycles)",
                    offset=0x38 + i * 4,
                    bitSize=32,
                    mode="RW",
                    hidden=False,
                )
            )

            self.add(
                pr.RemoteVariable(
                    name=f"DatIntThrs[{i}]",
                    description=f"Window {i} integral threshold",
                    offset=0x38 + 8 * 4 + i * 4,
                    bitSize=32,
                    mode="RW",
                    hidden=False,
                )
            )

    def getStateString(self, stateIdx):
        if stateIdx in self._trigStatesEnum:
            return self._trigStatesEnum[stateIdx]
        else:
            return "UNDEFINED"
