"""Shared test rig: a real Bridge on a fake song, with a transport that records instead of sending."""

import json

import fake_live
from MeterBridge.bridge import Bridge
from MeterBridge.log import RateLimitedLog


class RecordingTransport(object):
    """Same interface as UdpTransport; keeps sent messages and feeds queued ones to receive()."""

    def __init__(self, port=47801):
        self.port = port
        self.bound_port = None
        self.last_error = None
        self.is_open = False
        self.closed = False
        self.fail_open = False
        #: [(message dict, destination port, size in bytes)]
        self.sent = []
        self.inbox = []

    def open(self):
        if self.fail_open:
            self.last_error = "[Errno 48] Address already in use"
            return False
        self.is_open = True
        self.bound_port = self.port
        return True

    def receive(self, limit=64):
        batch = self.inbox[:limit]
        del self.inbox[:limit]
        return batch

    def send(self, data, port, host="127.0.0.1"):
        self.sent.append((json.loads(data.decode("utf-8")), port, len(data)))
        return True

    def close(self):
        self.is_open = False
        self.closed = True

    def push(self, message):
        self.inbox.append((json.dumps(message).encode("utf-8"), ("127.0.0.1", 50123)))

    def push_raw(self, data):
        self.inbox.append((data, ("127.0.0.1", 50123)))


class Rig(object):
    """A Bridge driven tick by tick with an explicit clock."""

    def __init__(
        self,
        track_count=12,
        left_xts=0,
        right_xts=0,
        group=False,
        exclusive_solo=True,
        slots=None,
        session=4242,
        song=None,
        perf_clock=None,
    ):
        self.song = song or fake_live.FakeSong(track_count, 2, group, 7, exclusive_solo)
        self.controller, self.slots = fake_live.build_mackie_stack(self.song, left_xts, right_xts)
        if slots is not None:
            self.slots = slots
        self.transport = RecordingTransport()
        self.lines = []
        self.now = 1000.0
        self.log = RateLimitedLog(self.lines.append, clock=lambda: self.now)
        self.bridge = Bridge(
            song=lambda: self.song,
            control_surfaces=lambda: self.slots,
            transport=self.transport,
            log=self.log,
            live_version="12.4.6",
            session=session,
            clock=lambda: self.now,
            perf_clock=perf_clock or (lambda: 0.0),
        )

    def tick(self, dt=0.016):
        self.now += dt
        self.song.now = self.now
        self.bridge.tick(self.now)

    def run(self, seconds, dt=0.016):
        steps = int(round(seconds / dt))
        for _ in range(steps):
            self.tick(dt)

    def push(self, message):
        self.transport.push(message)

    @staticmethod
    def sub_message(port=47800, hz=30, app=None):
        message = {"v": 1, "t": "sub", "port": port, "hz": hz}
        if app is not None:
            message["app"] = app
        return message

    def subscribe(self, port=47800, hz=30, app=None):
        self.push(self.sub_message(port, hz, app))
        self.tick()

    def keep_alive(self, seconds, port=47800, hz=30, dt=0.016, app=None):
        """Runs for `seconds`, sending `sub` every second like the app."""
        elapsed = 0.0
        next_sub = 1.0
        while elapsed < seconds:
            if elapsed >= next_sub:
                next_sub += 1.0
                self.push(self.sub_message(port, hz, app))
            self.tick(dt)
            elapsed += dt

    def messages(self, message_type=None):
        return [m for m, _port, _size in self.transport.sent if message_type is None or m["t"] == message_type]

    def types(self):
        return [m["t"] for m, _port, _size in self.transport.sent]

    def clear(self):
        del self.transport.sent[:]

    def track_named(self, name):
        return self.song.find(name)

    def tid(self, name):
        return self.song.find(name)._live_ptr
