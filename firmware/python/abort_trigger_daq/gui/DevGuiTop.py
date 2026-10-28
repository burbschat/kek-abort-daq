import os
from pydm import Display
from qtpy.QtWidgets import QVBoxLayout, QTabWidget

from pyrogue.pydm.widgets import DebugTree
from pyrogue.pydm.widgets import SystemWindow

import axi_soc_7000_core.hardware.red_pitaya_stemlab_125_14.gui as gui_core
import abort_trigger_daq.gui as gui

Channel = "rogue://0/root"


class GuiTop(Display):
    def __init__(self, parent=None, args=[], macros=None):
        super(GuiTop, self).__init__(parent=parent, args=args, macros=None)

        self.setStyleSheet("*[dirty='true']\
                           {background-color: orange;}")

        self.sizeX = None
        self.sizeY = None
        self.title = None
        self.numAdcCh = None
        self.numDacCh = None

        for a in args:
            if "sizeX=" in a:
                self.sizeX = int(a.split("=")[1])
            if "sizeY=" in a:
                self.sizeY = int(a.split("=")[1])
            if "title=" in a:
                self.title = a.split("=")[1]
            if "numAdcCh=" in a:
                self.numAdcCh = int(a.split("=")[1])
            if "numDacCh=" in a:
                self.numDacCh = int(a.split("=")[1])

        if self.title is None:
            self.title = "Rogue Server: {}".format(os.getenv("ROGUE_SERVERS"))

        if self.sizeX is None:
            self.sizeX = 800
        if self.sizeY is None:
            self.sizeY = 1000
        if self.numAdcCh is None:
            self.numAdcCh = 1
        if self.numDacCh is None:
            self.numDacCh = 1

        self.setWindowTitle(self.title)

        vb = QVBoxLayout()
        self.setLayout(vb)

        self.tab = QTabWidget()
        vb.addWidget(self.tab)

        # Live Display (Tab Index=0)
        sys = SystemWindow(parent=None, init_channel=Channel)
        self.tab.addTab(sys, "System")

        # Live Display (Tab Index=1)
        var = DebugTree(parent=None, init_channel=Channel)
        self.tab.addTab(var, "Debug Tree")

        # ADC Live Display (Tab Index=2)
        adcDisplay = gui_core.LiveDisplay(parent=None, init_channel=Channel, dispType="Adc", numCh=self.numAdcCh)
        self.tab.addTab(adcDisplay, "ADC Waveforms")

        # DAC Live Display (Tab Index=3)
        # TODO: Add DAC functionality in firmware
        # dacDisplay = gui_core.LiveDisplay(parent=None, init_channel=Channel, dispType="Dac", numCh=self.numDacCh)
        # self.tab.addTab(dacDisplay, "DAC Waveforms")

        adcDisplayTrigs = gui.WaveformDisplayTrigs(parent=None, init_channel=Channel, channel_idx=0, trig_type="thr")
        self.tab.addTab(adcDisplayTrigs, "ThrTrig")

        adcDisplayTrigs = gui.WaveformDisplayTrigs(parent=None, init_channel=Channel, channel_idx=0, trig_type="tot")
        self.tab.addTab(adcDisplayTrigs, "TotTrig")

        # Set the default Tab view
        self.tab.setCurrentIndex(2)

        # Resize the window
        self.resize(self.sizeX, self.sizeY)

    def ui_filepath(self):
        # No UI file is being used
        return None
