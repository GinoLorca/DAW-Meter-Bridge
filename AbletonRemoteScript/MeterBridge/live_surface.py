"""Live glue: the ControlSurface Live instantiates. It owns the timer and nothing else.

All protocol work happens in Bridge (bridge.py), which has no Live import. This
class creates it, drives it from a Live.Base.Timer on Live's main thread, and
stops the timer and closes the socket on disconnect.
"""

import time

import Live
from _Framework.ControlSurface import ControlSurface

from .bridge import Bridge
from .log import RateLimitedLog
from .protocol import MAX_HZ, SCRIPT_VERSION
from .transport import UdpTransport

#: Timer period in milliseconds. Meters go out every other tick at 30 Hz.
TICK_MS = 16
#: Meter rate cap when Live.Base.Timer is unavailable and update_display (100 ms) drives ticks.
FALLBACK_MAX_HZ = 10

#: Factory for the UDP transport; tests replace it.
make_transport = UdpTransport
#: Clock for the bridge (seconds, monotonic); the fake-Live harness replaces it.
clock = time.monotonic


def live_version():
    """Live's version as "major.minor.bugfix", or "" when unavailable."""
    try:
        application = Live.Application.get_application()
        return "%d.%d.%d" % (
            application.get_major_version(),
            application.get_minor_version(),
            application.get_bugfix_version(),
        )
    except Exception:
        return ""


def control_surfaces():
    """Live's slot-indexed list of control-surface script instances (None for empty slots)."""
    return Live.Application.get_application().control_surfaces


class MeterBridgeSurface(ControlSurface):
    """The MeterBridge control surface. Uses no MIDI ports (Input and Output: None).

    Private members carry an `_mb_` prefix so they can never shadow attributes of
    Live's ControlSurface base classes.
    """

    def __init__(self, c_instance):
        # Set before the base initializer in case it calls update_display() back.
        self._mb_timer = None
        self._mb_bridge = None
        self._mb_use_update_display = False
        # ControlSurface.log_message already prefixes "(MeterBridgeSurface)".
        self._mb_log = RateLimitedLog(self._mb_write_log)
        ControlSurface.__init__(self, c_instance)
        try:
            self._mb_start()
        except Exception:
            self._mb_log.exception("start", "could not start")

    def _mb_start(self):
        timer_class = None
        try:
            timer_class = Live.Base.Timer
        except Exception:
            timer_class = None
        max_hz = MAX_HZ if timer_class is not None else FALLBACK_MAX_HZ
        self._mb_bridge = Bridge(
            song=self.song,
            control_surfaces=control_surfaces,
            transport=make_transport(),
            log=self._mb_log,
            live_version=live_version(),
            clock=clock,
            tick_interval=TICK_MS / 1000.0,
            max_hz=max_hz,
        )
        if timer_class is not None:
            try:
                self._mb_timer = timer_class(callback=self._mb_on_timer, interval=TICK_MS, repeat=True)
                self._mb_timer.start()
            except Exception:
                self._mb_timer = None
                self._mb_log.exception("timer", "Live.Base.Timer failed")
        if self._mb_timer is None:
            self._mb_use_update_display = True
            self._mb_bridge.subscription.max_hz = FALLBACK_MAX_HZ
            self._mb_log.info("no Live.Base.Timer; ticking from update_display at 10 Hz")
        self._mb_log.info("script %s started in Live %s" % (SCRIPT_VERSION, self._mb_bridge.live_version or "?"))
        self._mb_tick()

    def _mb_on_timer(self):
        self._mb_tick()

    def _mb_tick(self):
        try:
            if self._mb_bridge is not None:
                self._mb_bridge.tick()
        except Exception:
            self._mb_log.exception("tick", "tick failed")

    @property
    def meter_bridge(self):
        """The Bridge driving the protocol (None after disconnect)."""
        return self._mb_bridge

    def update_display(self):
        """Called by Live every 100 ms; drives ticks only when the timer is unavailable."""
        ControlSurface.update_display(self)
        if self._mb_use_update_display:
            self._mb_tick()

    def disconnect(self):
        """Stops the timer and closes the socket before Live unloads the script."""
        timer = self._mb_timer
        self._mb_timer = None
        self._mb_use_update_display = False
        if timer is not None:
            try:
                timer.stop()
            except Exception:
                pass
        bridge = self._mb_bridge
        self._mb_bridge = None
        if bridge is not None:
            bridge.close()
        self._mb_log.info("stopped")
        ControlSurface.disconnect(self)

    def _mb_write_log(self, message):
        self.log_message(message)
