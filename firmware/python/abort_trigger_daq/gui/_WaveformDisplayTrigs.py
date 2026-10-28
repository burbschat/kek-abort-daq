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


class PyDMWaveformPlotTrig(PyDMWaveformPlot):
    def __init__(self, trig_delay_channel_addr, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self._trig_line_width = 2
        self.trig_delay = 0

        self._trig_line_pen_connected = pg.mkPen(
            "yellow",
            width=self._trig_line_width,
            style=pg.QtCore.Qt.PenStyle.DashLine,
        )
        self._trig_line_pen_disconnected = pg.mkPen(
            "magenta",
            width=self._trig_line_width,
            style=pg.QtCore.Qt.PenStyle.DotLine,
        )

        self.trig_line = pg.InfiniteLine(
            pos=0,
            angle=90,
            pen=self._trig_line_pen_disconnected,
            movable=False,
        )
        self.trig_line.hide()

        self.trig_delay_channel = PyDMChannel(
            address=trig_delay_channel_addr,
            value_slot=self.receive_value_trig_delay,
            connection_slot=self.trig_connection_state_changed,
        )
        self.trig_delay_channel.connect()

    def addChannel(self, *args, **kwargs):
        if self.channel_pairs:
            raise RuntimeError("PyDMWaveformPlotTrig supports only one waveform per plot.")

        super().addChannel(*args, **kwargs)

        curve = next(iter(self.channel_pairs.values()))
        # Recalculate whenever new waveform data arrives.
        curve.sigPlotChanged.connect(self.update_trig_line)

        curve.getViewBox().addItem(self.trig_line)

        # Try immediately in case data is already available.
        self.update_trig_line()

    def foo(self):
        self.update_trig_line()

    def trig_connection_state_changed(self, connected):
        pen = self._trig_line_pen_connected if connected else self._trig_line_pen_disconnected
        self.trig_line.setPen(pen)

    def receive_value_trig_delay(self, new_value):
        if new_value is None:
            return

        self.trig_delay = int(new_value)
        self.update_trig_line()

    def update_trig_line(self, *args):
        if not self.channel_pairs:
            return

        curve = next(iter(self.channel_pairs.values()))
        x_data, y_data = curve.getData()

        if x_data is None or len(x_data) == 0:
            return

        trigger_index = len(x_data) - 1 - self.trig_delay

        if 0 <= trigger_index < len(x_data):
            self.trig_line.setValue(x_data[trigger_index])
            self.trig_line.show()
        else:
            self.trig_line.hide()


class PyDMWaveformPlotThrTrig(PyDMWaveformPlotTrig):
    def __init__(
        self,
        thr_channel_addr,
        hyst_channel_addr,
        trig_delay_channel_addr,
        *args,
        **kwargs,
    ):
        super().__init__(trig_delay_channel_addr, *args, **kwargs)

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

        self.thr_line = pg.InfiniteLine(
            pos=self.thr,
            angle=0,
            pen=self._thr_line_pen_disconnected,
            movable=False,
        )
        self.hyst_upper_line = pg.InfiniteLine(
            pos=self.thr + self.hyst,
            angle=0,
            pen=self._hyst_line_pen_disconnected,
            movable=False,
        )
        self.hyst_lower_line = pg.InfiniteLine(
            pos=self.thr - self.hyst,
            angle=0,
            pen=self._hyst_line_pen_disconnected,
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
        # Base class creates the waveform and adds the trigger timing line.
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
        self.hyst_upper_line.setPen(hyst_pen)
        self.hyst_lower_line.setPen(hyst_pen)

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


class PyDMWaveformPlotTotTrig(PyDMWaveformPlotThrTrig):
    def __init__(
        self,
        thr_channel_addr,
        hyst_channel_addr,
        tot_window_channel_addr,
        trig_delay_channel_addr,
        *args,
        **kwargs,
    ):
        super().__init__(
            thr_channel_addr,
            hyst_channel_addr,
            trig_delay_channel_addr,
            *args,
            **kwargs,
        )

        self.tot_window = 0

        self.tot_region = pg.LinearRegionItem(
            values=(0, 1),
            orientation=pg.LinearRegionItem.Vertical,
            brush=pg.mkBrush(255, 215, 0, 45),
            movable=False,
        )
        self.tot_region.setZValue(-10)
        self.tot_region.hide()

        self.tot_window_channel = PyDMChannel(
            address=tot_window_channel_addr,
            value_slot=self.receive_value_tot_window,
        )
        self.tot_window_channel.connect()

    def addChannel(self, *args, **kwargs):
        super().addChannel(*args, **kwargs)

        curve = next(iter(self.channel_pairs.values()))
        curve.getViewBox().addItem(self.tot_region)

        self.update_tot_region()

    def receive_value_tot_window(self, new_value):
        print("VALUE", new_value)
        if new_value is None:
            return

        self.tot_window = max(0, int(new_value))
        self.update_tot_region()

    def update_trig_line(self, *args):
        super().update_trig_line(*args)
        self.update_tot_region()

    def update_tot_region(self):
        if not self.channel_pairs:
            return

        curve = next(iter(self.channel_pairs.values()))
        x_data, _ = curve.getData()

        if x_data is None or len(x_data) == 0:
            return

        trigger_index = len(x_data) - 1 - self.trig_delay

        if not 0 <= trigger_index < len(x_data):
            self.tot_region.hide()
            return

        start_index = max(0, trigger_index - self.tot_window)

        self.tot_region.setRegion((x_data[start_index], x_data[trigger_index]))
        self.tot_region.show()


class WaveformDisplayTrigs(PyDMFrame):
    def __init__(self, channel_idx=0, trig_type="thr", *args, **kwargs):
        super().__init__(*args, **kwargs)

        i = channel_idx

        self.color = "white"
        self.wav_path = f"{self.channel}.AdcProcessor[{i}]"

        vb = QVBoxLayout()
        self.setLayout(vb)

        if trig_type == "thr":
            self.trig_path = f"{self.channel}.Zynq7SoC.Application.AbortTrigs.ThrTrig[{i}]"
            self.timePlot = PyDMWaveformPlotThrTrig(
                thr_channel_addr=f"{self.trig_path}.Threshold",
                hyst_channel_addr=f"{self.trig_path}.Hysteresis",
                trig_delay_channel_addr=f"{self.channel}.Zynq7SoC.Application.AbortTrigs.TrigDly",
            )
        elif trig_type == "tot":
            self.trig_path = f"{self.channel}.Zynq7SoC.Application.AbortTrigs.TotTrig[{i}]"
            self.timePlot = PyDMWaveformPlotTotTrig(
                thr_channel_addr=f"{self.trig_path}.Threshold",
                hyst_channel_addr=f"{self.trig_path}.Hysteresis",
                tot_window_channel_addr=f"{self.trig_path}.TotCountTrig",
                trig_delay_channel_addr=f"{self.channel}.Zynq7SoC.Application.AbortTrigs.TrigDly",
            )
        else:
            raise ValueError(f"Unsupported trigger type: {trig_type}")

        self.timePlot.setLabel("bottom", text="Time (ns)")

        self.timePlot.addChannel(
            name="Counts",
            x_channel=f"{self.wav_path}.Time",
            y_channel=f"{self.wav_path}.WaveformData",
            color=self.color,
            symbol="o",
            symbolSize=3,
        )
        vb.addWidget(self.timePlot)

        self.timePlot.update_trig_line()
