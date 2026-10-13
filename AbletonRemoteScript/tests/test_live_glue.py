"""The Live glue (MeterBridgeSurface) under fake Live modules, and real UDP on loopback."""

import json
import os
import socket
import sys
import time
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_live
from meterbridge_rig import RecordingTransport
from MeterBridge.bridge import Bridge
from MeterBridge.log import RateLimitedLog
from MeterBridge.transport import UdpTransport


class GlueTests(unittest.TestCase):
    def make_live(self, **options):
        self.transports = []

        def factory():
            transport = RecordingTransport()
            self.transports.append(transport)
            return transport

        self.logged = []
        live = fake_live.FakeLive(track_count=8, transport_factory=factory, log=self.logged.append, **options)
        self.addCleanup(live.disconnect)
        return live

    def test_create_instance_starts_a_repeating_timer(self):
        live = self.make_live()
        timers = [t for t in fake_live.FakeTimer.instances if t.running]
        self.assertEqual(len(timers), 1)
        self.assertEqual(timers[0].interval, 16)
        self.assertTrue(timers[0].repeat)
        self.assertTrue(self.transports[0].is_open)
        self.assertEqual(live.slot, 2)
        self.assertTrue(any("started in Live 12.4.6" in line for line in self.logged))
        self.assertTrue(all(line.startswith("(MeterBridgeSurface) ") for line in self.logged))

    def test_timer_drives_the_bridge(self):
        live = self.make_live()
        transport = self.transports[0]
        transport.push({"v": 1, "t": "sub", "port": 47800, "hz": 30})
        start = live.now
        for k in range(1, 41):
            live.step(start + k * 0.016)
        types = [m["t"] for m, _port, _size in transport.sent]
        self.assertEqual(types[:4], ["hello", "tracks", "sel", "surfaces"])
        self.assertGreater(types.count("m"), 10)
        surfaces = [m for m, _p, _s in transport.sent if m["t"] == "surfaces"][0]
        # The script itself sits in slot 2 and is not reported as a surface.
        self.assertEqual([u["slot"] for u in surfaces["units"]], [1])

    def test_disconnect_stops_the_timer_and_closes_the_socket(self):
        live = self.make_live()
        timer = [t for t in fake_live.FakeTimer.instances if t.running][0]
        live.disconnect()
        self.assertFalse(timer.running)
        self.assertTrue(self.transports[0].closed)
        self.assertIsNone(live.bridge)
        live.disconnect()  # twice is harmless

    def test_tick_errors_never_escape(self):
        live = self.make_live()

        def explode(now=None):
            raise RuntimeError("kaboom")

        live.bridge.tick = explode
        for k in range(5):
            live.step(live.now + 0.02)
        self.assertTrue(any("kaboom" in line for line in self.logged))

    def test_falls_back_to_update_display_without_timer(self):
        base = sys.modules["Live"].Base
        saved = base.Timer
        del base.Timer
        try:
            live = self.make_live()
        finally:
            base.Timer = saved
        self.assertEqual([t for t in fake_live.FakeTimer.instances if t.running], [])
        transport = self.transports[0]
        transport.push({"v": 1, "t": "sub", "port": 47800, "hz": 30})
        for k in range(12):
            live.step(live.now + 0.1)
        hello = [m for m, _p, _s in transport.sent if m["t"] == "hello"][0]
        self.assertEqual(hello["hz"], 10)
        self.assertTrue(any("update_display" in line for line in self.logged))


class UdpTests(unittest.TestCase):
    def test_transport_binds_loopback_only(self):
        transport = UdpTransport(port=0)
        self.addCleanup(transport.close)
        self.assertTrue(transport.open())
        self.assertEqual(transport._sock.getsockname()[0], "127.0.0.1")
        self.assertEqual(transport.receive(), [])

    def test_second_bind_on_the_same_port_fails_cleanly(self):
        first = UdpTransport(port=0)
        self.addCleanup(first.close)
        self.assertTrue(first.open())
        second = UdpTransport(port=first.bound_port)
        self.addCleanup(second.close)
        self.assertFalse(second.open())
        self.assertTrue(second.last_error)
        self.assertFalse(second.is_open)
        self.assertFalse(second.send(b"x", 47800))

    def test_full_round_trip_over_real_udp(self):
        app = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.addCleanup(app.close)
        app.bind(("127.0.0.1", 0))
        app.settimeout(0.5)
        app_port = app.getsockname()[1]

        song = fake_live.FakeSong(track_count=10)
        _controller, slots = fake_live.build_mackie_stack(song)
        transport = UdpTransport(port=0)
        lines = []
        bridge = Bridge(lambda: song, lambda: slots, transport, RateLimitedLog(lines.append), live_version="11.3.42")
        self.addCleanup(bridge.close)
        now = time.monotonic()
        bridge.tick(now)
        self.assertTrue(transport.is_open, lines)

        def send(message):
            app.sendto(json.dumps(message).encode("utf-8"), ("127.0.0.1", transport.bound_port))

        def pump(seconds):
            end = time.monotonic() + seconds
            while time.monotonic() < end:
                song.now = time.monotonic()
                bridge.tick(song.now)
                time.sleep(0.005)

        def drain():
            received = []
            app.settimeout(0.05)
            while True:
                try:
                    data, _address = app.recvfrom(65535)
                except socket.timeout:
                    return received
                self.assertLessEqual(len(data), 8192)
                self.assertNotIn(b": ", data[:40])
                received.append(json.loads(data.decode("utf-8")))

        send({"v": 1, "t": "sub", "port": app_port, "hz": 30})
        pump(0.3)
        received = drain()
        types = [m["t"] for m in received]
        self.assertEqual(types[:4], ["hello", "tracks", "sel", "surfaces"])
        self.assertIn("m", types)
        self.assertEqual(received[0]["live"], "11.3.42")
        bass = [i for i in received[1]["items"] if i["n"] == "Bass"][0]

        send({"v": 1, "t": "cmd", "op": "mute", "id": bass["id"], "on": True})
        pump(0.15)
        deltas = [m for m in drain() if m["t"] == "track"]
        self.assertEqual([d["item"]["n"] for d in deltas], ["Bass"])
        self.assertIs(deltas[0]["item"]["m"], True)
        self.assertTrue(song.find("Bass")._mute)


if __name__ == "__main__":
    unittest.main()
