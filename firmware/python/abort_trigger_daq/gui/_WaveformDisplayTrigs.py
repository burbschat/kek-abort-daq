from pydm.widgets.frame import PyDMFrame
from pydm.widgets import PyDMWaveformPlot, PyDMPushButton

from qtpy import QtCore
from qtpy.QtGui import QColor
from qtpy.QtWidgets import QHBoxLayout, QLabel, QVBoxLayout

from pyrogue.pydm.data_plugins.rogue_plugin import nodeFromAddress

from pyqtgraph import TextItem
from pyqtgraph import LinearRegionItem
from pydm import PyDMChannel
import numpy as np
import pyqtgraph as pg


# Waveform plot but with indication for trigger settings
class PyDMWaveformPlotThrTrig(PyDMWaveformPlot):
    def __init__(self, thr_channel_addr, hyst_channel_addr, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self._thr_line_width = 2
        self.thr = 2**16 / 2
        self.hyst = 0

        self._thr_line_pen_connected = pg.mkPen(
            "royalblue",
            width=self._thr_line_width,
            style=pg.QtCore.Qt.PenStyle.SolidLine,
        )
        self._thr_line_pen_disconnected = pg.mkPen(
            "magenta",
            width=self._thr_line_width,
            style=pg.QtCore.Qt.PenStyle.DotLine,
        )
        self._hyst_line_pen_connected = pg.mkPen(
            "royalblue",
            width=self._thr_line_width,
            style=pg.QtCore.Qt.PenStyle.DashLine,
        )
        self._hyst_line_pen_disconnected = pg.mkPen(
            "magenta",
            width=self._thr_line_width,
            style=pg.QtCore.Qt.PenStyle.DotLine,
        )

        # Threshold line
        self.thr_line = pg.InfiniteLine(
            pos=self.thr,
            angle=0,
            pen=self._thr_line_pen_disconnected,
            movable=False,
        )

        # Hysteresis boundary lines
        self.hyst_upper_line = pg.InfiniteLine(
            pos=self.thr + self.hyst,
            angle=0,
            pen=self._hyst_line_pen_connected,
            movable=False,
        )
        self.hyst_lower_line = pg.InfiniteLine(
            pos=self.thr - self.hyst,
            angle=0,
            pen=self._hyst_line_pen_connected,
            movable=False,
        )

        self.thr_channel = PyDMChannel(
            address=thr_channel_addr,
            value_slot=self.receive_value_thr,
            connection_slot=self.connection_state_changed,
        )
        self.thr_channel.connect()

        self.hyst_channel = PyDMChannel(
            address=hyst_channel_addr,
            value_slot=self.receive_value_hyst,
        )
        self.hyst_channel.connect()

    def addChannel(self, *args, **kwargs):
        if self.channel_pairs:
            raise RuntimeError("PyDMWaveformPlotThrTrig supports only one waveform per plot.")

        super().addChannel(*args, **kwargs)

        curve = next(iter(self.channel_pairs.values()))
        view_box = curve.getViewBox()

        view_box.addItem(self.thr_line)
        view_box.addItem(self.hyst_upper_line)
        view_box.addItem(self.hyst_lower_line)

    def connection_state_changed(self, connected):
        thr_pen = self._thr_line_pen_connected if connected else self._thr_line_pen_disconnected
        hyst_pen = self._hyst_line_pen_connected if connected else self._hyst_line_pen_disconnected
        self.thr_line.setPen(thr_pen)
        self.hyst_lower_line.setPen(hyst_pen)
        self.hyst_upper_line.setPen(hyst_pen)

    def receive_value_thr(self, new_value):
        if new_value is None:
            return

        self.thr = new_value
        self.update_thr_lines()

    def receive_value_hyst(self, new_value):
        if new_value is None:
            return

        self.hyst = abs(new_value)
        self.update_thr_lines()

    def update_thr_lines(self):
        self.thr_line.setValue(self.thr)
        self.hyst_upper_line.setValue(self.thr + self.hyst)
        self.hyst_lower_line.setValue(self.thr - self.hyst)


class WaveformDisplayTrigs(PyDMFrame):
    def __init__(self, numCh=2, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self.numCh = numCh
        self.color = ["white", "red", "dodgerblue", "forestgreen"]
        self.wav_path = [f"{self.channel}.AdcProcessor[{i}]" for i in range(self.numCh)]
        self.trig_path = [f"{self.channel}.Zynq7SoC.Application.AbortTrigs.ThrTrig[{i}]" for i in range(self.numCh)]

        vb = QVBoxLayout()
        self.setLayout(vb)

        self.timePlot = PyDMWaveformPlotThrTrig(
            thr_channel_addr=f"{self.trig_path[0]}.Threshold", hyst_channel_addr=f"{self.trig_path[0]}.Hysteresis"
        )
        self.timePlot.setLabel("bottom", text="Time (ns)")
        # for i in range(self.numCh):
        i = 0
        self.timePlot.addChannel(
            name="Counts",
            x_channel=f"{self.wav_path[i]}.Time",
            y_channel=f"{self.wav_path[i]}.WaveformData",
            color=self.color[i],
            symbol="o",
            symbolSize=3,
        )
        vb.addWidget(self.timePlot)
