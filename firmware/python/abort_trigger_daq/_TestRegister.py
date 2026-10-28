import pyrogue as pr


class TestRegister(pr.Device):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        self.add(
            pr.RemoteVariable(
                name="TestRegister1",
                description="All ones",
                offset=0x0,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="TestRegister2",
                description="All zeros",
                offset=0x4,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )

        self.add(
            pr.RemoteVariable(
                name="TestRegister3",
                description="Alternating ones and zeros (all 'A')",
                offset=0x08,
                bitSize=32,
                mode="RO",
                hidden=False,
            )
        )
