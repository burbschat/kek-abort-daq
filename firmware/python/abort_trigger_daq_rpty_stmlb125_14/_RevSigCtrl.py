import pyrogue as pr

class RevSigCtrl(pr.Device):
    def __init__(self, clkFreq, **kwargs):
        super().__init__(**kwargs)

        # 5120 RF buckets at 508.89 MHz RF clock frequency
        revPeriodDefault = 1 / 508.89e6 * 5120

        self.add(pr.RemoteVariable(
            name         = 'revCounterPresetVal',
            description  = 'Revolutions per generated trigger pulse',
            offset       = 0x0,
            bitSize      = 32,
            bitOffset    = 0,
            mode         = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name         = 'clockCounterPresetVal',
            description  = 'Clock cycles per beam revolution used for dummy revolution signal generation',
            offset       = 0x4,
            bitSize      = 32,
            bitOffset    = 0,
            mode         = 'RW',
        ))

        # 'xxx per yyy' variables are the counter preset values + 1
        self.add(pr.LinkVariable(
            name         = 'revPerTrig',
            description  = 'Revolutions per generated trigger pulse',
            dependencies = [self.revCounterPresetVal],
            mode         = 'RW',
            linkedGet    = lambda: self.revCounterPresetVal.value() + 1,
            linkedSet    = lambda val, wr: self.revCounterPresetVal.set(val-1),
            # 5120 buckets / 508.89 MHz RF clock gives ~ 10 us per turn.
            # Trigger every 100000 turns gives around 1.00611134 Hz trigger.
            default      = 100000,
        ))

        self.add(pr.LinkVariable(
            name         = 'cyclesPerRev',
            description  = 'Clock cycles per beam revolution used for dummy revolution signal generation',
            dependencies = [self.clockCounterPresetVal],
            mode         = 'RW',
            linkedGet    = lambda: self.clockCounterPresetVal.value() + 1,
            linkedSet    = lambda val, wr: self.clockCounterPresetVal.set(val-1),
        ))

        self.add(pr.LinkVariable(
            name         = 'revPeriod',
            description  = 'Clock cycles per beam revolution used for dummy revolution signal generation',
            dependencies = [self.clockCounterPresetVal],
            mode         = 'RW',
            units        = 'us',
            disp         = '{:0.5g}',
            linkedGet    = lambda: self.cyclesPerRev.value() / clkFreq,
            linkedSet    = lambda val, wr: self.cyclesPerRev.set(round(val * clkFreq)),
            default      = revPeriodDefault,
        ))

        self.add(pr.RemoteVariable(
            name         = 'revCounter',
            description  = 'Current value of revolution counter',
            offset       = 0x8,
            bitSize      = 32,
            bitOffset    = 0,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'clockCounter',
            description  = 'Current value of clock counter used for dummy revolution signal generation',
            offset       = 0xC,
            bitSize      = 32,
            bitOffset    = 0,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'revSelect',
            description  = 'Select real or dummy revolution signal',
            offset       = 0x10,
            bitSize      = 1,
            bitOffset    = 0,
            mode         = 'RW',
            enum        = {
                0: "realRev",
                1: "dummyRev",
            },
        ))

        self.add(pr.RemoteVariable(
            name         = 'realRevVal',
            description  = 'Real revolution signal input value',
            offset       = 0x14,
            bitSize      = 1,
            bitOffset    = 0,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'dummyRevVal',
            description  = 'Dummy revolution signal value',
            offset       = 0x14,
            bitSize      = 1,
            bitOffset    = 1,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'dummyRevVal',
            description  = 'Dummy revolution signal value',
            offset       = 0x14,
            bitSize      = 1,
            bitOffset    = 1,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'revOutVal',
            description  = 'Revolution signal output value',
            offset       = 0x14,
            bitSize      = 1,
            bitOffset    = 2,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'revSyncTrigVal',
            description  = 'Revolution synchronous trigger output value',
            offset       = 0x14,
            bitSize      = 1,
            bitOffset    = 3,
            mode         = 'RO',
        ))
