"""The bridge core: one `tick` per Live timer callback. Pure module: no Live import.

Each tick, in order:
1. (Re)binds the UDP socket if needed and drains incoming datagrams.
2. Ends the subscription after 5 s without `sub`.
3. Closes idle volume-drag gestures, then applies queued commands (only here,
   never from a listener or on receipt).
4. While subscribed: sends the full state after a new subscription, otherwise
   polls track state and surfaces about every 100 ms, half a period apart so
   they never share a tick, and sends what changed; sends meters at the
   subscribed rate and a heartbeat every second.

Every step is guarded, so one failure is logged (rate-limited) and the rest of
the tick, and every later tick, still runs.
"""

import random
import time
from collections import OrderedDict

from . import protocol
from .commands import APPLIED, ERROR, OP_VOLUME, RETRY, CommandQueue, VolumeGestures, parse_command
from .meters import MeterFrameBuilder, select_ids
from .protocol import MAX_DATAGRAM_BYTES, PROTOCOL_VERSION, SCRIPT_PORT, is_int
from .subscription import Subscription
from .surfaces import read_surfaces, strip_track_ids
from .tracks import TrackStateTracker
from .volume_curve import approximate_curve, sample_song_curve

STATE_POLL_SECONDS = 0.1
SURFACE_POLL_SECONDS = 0.1
#: The surface poll runs this long after the state poll, so the two never read Live in the same tick.
SURFACE_POLL_OFFSET = STATE_POLL_SECONDS / 2.0
#: A track-state read slower than this is logged (rate-limited) with the track count.
SLOW_READ_SECONDS = 0.002
HEARTBEAT_SECONDS = 1.0
REBIND_SECONDS = 5.0
MAX_DATAGRAMS_PER_TICK = 64


def new_session_id():
    """Random id for `hello.session`, chosen once per script instance."""
    try:
        return random.SystemRandom().randint(1, 2 ** 31 - 1)
    except Exception:
        return random.randint(1, 2 ** 31 - 1)


class Bridge(object):
    """Protocol state machine between Live and the app.

    `song` and `control_surfaces` are callables returning Live's Song and the
    slot-indexed control-surface list; `transport` is a UdpTransport (or a test
    double with the same methods); `log` is a RateLimitedLog. `perf_clock`
    times the track-state reads.
    """

    def __init__(
        self,
        song,
        control_surfaces,
        transport,
        log,
        live_version="",
        session=None,
        clock=time.monotonic,
        tick_interval=0.016,
        max_hz=protocol.MAX_HZ,
        perf_clock=time.perf_counter,
    ):
        self._song = song
        self._control_surfaces = control_surfaces
        self._transport = transport
        self._log = log
        self._clock = clock
        self._perf_clock = perf_clock
        self.live_version = live_version
        self.session = session if session is not None else new_session_id()
        self.tick_interval = tick_interval
        self.subscription = Subscription(max_hz=max_hz)
        self.tracker = TrackStateTracker()
        self.commands = CommandQueue()
        #: Open volume-drag gestures (begin_gesture and one undo step per drag).
        self.gestures = VolumeGestures()
        self.meter_frames = MeterFrameBuilder()
        self.gen = 0
        self.meter_seq = 0
        self.heartbeat_seq = 0
        #: Latest surface units (protocol dicts) and warning.
        self.units = []
        self.warn = None
        #: Counters for diagnostics (the fake-Live harness prints them).
        self.stats = {"sent": 0, "send_failures": 0, "received": 0, "commands": 0, "errors": 0, "slow_reads": 0}
        #: Slowest track-state poll read so far, in seconds.
        self.slowest_read = 0.0
        self._sent_surfaces = None
        self._pending_tracks = OrderedDict()
        self._selection_dirty = False
        self._needs_full_state = False
        self._next_state_poll = 0.0
        self._next_surface_poll = 0.0
        self._surface_poll_deferred = False
        self._next_meter = 0.0
        self._next_heartbeat = 0.0
        self._next_bind_attempt = 0.0
        self._volume_curve = None
        self._version_warned = False
        self._closed = False

    # Lifecycle

    def tick(self, now=None):
        """Runs one timer tick. Never raises."""
        if self._closed:
            return
        try:
            if now is None:
                now = self._clock()
        except Exception:
            return
        self._guard("socket", self._ensure_transport, now)
        self._guard("receive", self._receive, now)
        if self.subscription.expire(now):
            self._on_unsubscribed()
        self._guard("commands", self._apply_commands, now)
        if not self.subscription.active:
            return
        if self._needs_full_state:
            self._guard("full state", self._send_full_state, now)
        else:
            polled_state = False
            if now >= self._next_state_poll:
                self._guard("track state", self._poll_state, now)
                polled_state = True
            if now >= self._next_surface_poll:
                if polled_state and not self._surface_poll_deferred:
                    # Not in the same tick as the state poll: wait one tick (never longer).
                    self._surface_poll_deferred = True
                else:
                    self._surface_poll_deferred = False
                    self._guard("surfaces", self._poll_surfaces, now)
        self._guard("deltas", self._flush_deltas, now)
        if not self._needs_full_state and self._meter_due(now):
            self._guard("meters", self._send_meters, now)
        if now >= self._next_heartbeat:
            self._guard("heartbeat", self._send_heartbeat, now)

    def close(self):
        """Stops for good: closes any open drag gesture, then the socket."""
        self._closed = True
        try:
            self.gestures.end_all()
        except Exception:
            pass
        try:
            self._transport.close()
        except Exception:
            pass

    @property
    def hz(self):
        """Meter rate in use."""
        return self.subscription.hz

    @property
    def is_subscribed(self):
        """True while the app's `sub` keep-alive is current."""
        return self.subscription.active

    def _guard(self, name, step, now):
        try:
            step(now)
        except Exception:
            self.stats["errors"] += 1
            self._log.exception("step:" + name, "error in %s" % name)

    # Incoming

    def _ensure_transport(self, now):
        if self._transport.is_open or now < self._next_bind_attempt:
            return
        self._next_bind_attempt = now + REBIND_SECONDS
        if self._transport.open():
            self._log.info("listening on 127.0.0.1:%s" % self._transport.bound_port)
        else:
            self._log.limited(
                "bind",
                "could not listen on 127.0.0.1:%s (%s). Is another MeterBridge running, "
                "for example in Live 11 and Live 12 at once? Retrying every %d s"
                % (getattr(self._transport, "port", SCRIPT_PORT), self._transport.last_error, REBIND_SECONDS),
            )

    def _receive(self, now):
        if not self._transport.is_open:
            return
        for data, _address in self._transport.receive(MAX_DATAGRAMS_PER_TICK):
            self.stats["received"] += 1
            # One bad datagram must not lose the rest of the batch (already read from the socket).
            try:
                self.handle_datagram(data, now)
            except Exception:
                self.stats["errors"] += 1
                self._log.exception("datagram", "error handling a datagram")

    def handle_datagram(self, data, now):
        """Decodes one datagram and handles it."""
        message, problem = protocol.decode(data)
        if problem is not None:
            self._log.limited("bad datagram", "ignored a datagram: %s" % problem)
            return
        self.handle_message(message, now)

    def handle_message(self, message, now):
        """Handles one decoded message. Commands are only queued here; `tick` applies them."""
        version = message.get("v")
        if not (is_int(version) and version == PROTOCOL_VERSION):
            if not self._version_warned:
                self._version_warned = True
                self._log.info(
                    "ignoring messages with protocol version %r; this script speaks v%d. "
                    "Update the app or the script so they match." % (version, PROTOCOL_VERSION)
                )
            return
        message_type = message.get("t")
        if message_type == "sub":
            if self.subscription.on_sub(message, now):
                self._start_subscription(now)
        elif message_type == "watch":
            self.subscription.on_watch(message)
        elif message_type == "cmd":
            command, problem = parse_command(message)
            if problem is not None:
                self._send_error(problem)
            else:
                self.commands.enqueue(command)

    def _start_subscription(self, now):
        self._needs_full_state = True
        self.tracker.reset()
        self.meter_frames.reset()
        self._sent_surfaces = None
        self._pending_tracks.clear()
        self._selection_dirty = False
        self._log.info("app subscribed on port %d, meters at %d Hz" % (self.subscription.reply_port, self.hz))

    def _on_unsubscribed(self):
        try:
            self.gestures.end_all()
        except Exception:
            self._log.exception("gestures", "could not close a volume gesture")
        self._needs_full_state = False
        self.meter_frames.reset()
        self._pending_tracks.clear()
        self._selection_dirty = False
        self._log.info("no sub from the app for %d s; meters and updates paused" % self.subscription.timeout)

    # Commands

    def _apply_commands(self, now):
        if len(self.gestures):
            self.gestures.end_idle(now)
        if not len(self.commands):
            return
        song = self._song()
        refreshed = [False]

        def resolve(tid):
            track, kind = self.tracker.resolve(tid)
            if track is None and not refreshed[0]:
                refreshed[0] = True
                self.tracker.read(song)
                track, kind = self.tracker.resolve(tid)
            return track, kind

        for result in self.commands.apply(song, resolve, self.gestures, now):
            command = result.command
            if result.status == ERROR:
                self._log.limited("cmd error", result.message)
                self._send_error(result.message)
            elif result.status == RETRY:
                self._log.limited("cmd retry", "Live refused %s; retrying next tick" % command.describe())
            elif result.status == APPLIED:
                self.stats["commands"] += 1
                self._after_command(command, now)

    def _after_command(self, command, now):
        """Echoes the result quickly: one track for volume, a full poll this tick for the rest."""
        if not self.subscription.active or self._needs_full_state:
            return
        if command.op == OP_VOLUME:
            record = self.tracker.refresh(command.track_id)
            if record is not None:
                self._pending_tracks[record["id"]] = record
        else:
            self._next_state_poll = now

    # Outgoing state

    def _send_full_state(self, now):
        song = self._song()
        self.tracker.read(song)
        units, warn = self._read_surfaces()
        self._send(protocol.hello(self.session, self.live_version, self.hz, self._curve(song)))
        self._send_track_list()
        self.tracker.diff()
        self._send(protocol.selection(self.tracker.selected_id))
        self._send_surfaces(units, warn)
        self._pending_tracks.clear()
        self._selection_dirty = False
        self._needs_full_state = False
        self._next_state_poll = now + STATE_POLL_SECONDS
        self._next_surface_poll = now + SURFACE_POLL_OFFSET
        self._surface_poll_deferred = False
        self._next_meter = now
        self._next_heartbeat = now + HEARTBEAT_SECONDS

    def _send_track_list(self):
        self.gen += 1
        self._pending_tracks.clear()
        for part in protocol.tracks_parts(self.gen, self.tracker.full_list()):
            self._send(part)

    def _poll_state(self, now):
        self._next_state_poll = now + STATE_POLL_SECONDS
        song = self._song()
        started = self._perf_clock()
        self.tracker.read(song)
        self._note_read_time(self._perf_clock() - started)
        full, changed, selection_changed = self.tracker.diff()
        if full:
            self._send_track_list()
        else:
            for record in changed:
                self._pending_tracks[record["id"]] = record
        if selection_changed:
            self._selection_dirty = True

    def _note_read_time(self, seconds):
        """Logs (rate-limited) a slow track-state read, so a real Live set shows whether polling needs work."""
        if seconds > self.slowest_read:
            self.slowest_read = seconds
        if seconds > SLOW_READ_SECONDS:
            self.stats["slow_reads"] += 1
            self._log.limited(
                "slow read",
                "reading %d tracks from Live took %.1f ms (more than %.0f ms; slowest so far %.1f ms)"
                % (len(self.tracker.order), seconds * 1000.0, SLOW_READ_SECONDS * 1000.0, self.slowest_read * 1000.0),
            )

    def _flush_deltas(self, now):
        """Sends coalesced `track` deltas (at most one per track per tick), then `sel`."""
        pending = list(self._pending_tracks.values())
        self._pending_tracks.clear()
        for record in pending:
            self._send(protocol.track(self.gen, record))
        if self._selection_dirty:
            self._selection_dirty = False
            self._send(protocol.selection(self.tracker.selected_id))

    def _read_surfaces(self):
        try:
            scripts = self._control_surfaces()
        except Exception as exc:
            return [], "could not read Live's control surfaces: %s" % exc
        return read_surfaces(scripts, self.tracker.id_of)

    def _poll_surfaces(self, now):
        self._next_surface_poll = now + SURFACE_POLL_SECONDS
        units, warn = self._read_surfaces()
        if (units, warn) != self._sent_surfaces:
            self._send_surfaces(units, warn)

    def _send_surfaces(self, units, warn):
        if warn and warn != self.warn:
            self._log.limited("surfaces warn", "bank follow: " + warn)
        self.units = units
        self.warn = warn
        self._sent_surfaces = (units, warn)
        self._send(protocol.surfaces(units, warn))

    def _curve(self, song):
        if self._volume_curve is None:
            try:
                curve, problem = sample_song_curve(song)
            except Exception as exc:
                curve, problem = approximate_curve(), "volume curve failed: %s" % exc
            if problem:
                self._log.info(problem)
            self._volume_curve = curve
        return self._volume_curve

    # Meters and heartbeat

    def _meter_due(self, now):
        period = 1.0 / max(self.hz, 1)
        slack = min(self.tick_interval, period) / 2.0
        if now + slack < self._next_meter:
            return False
        self._next_meter += period
        if self._next_meter <= now:
            self._next_meter = now + period
        return True

    def meter_ids(self):
        """Track ids the next meter frame covers."""
        return select_ids(
            strip_track_ids(self.units),
            self.tracker.selected_id,
            self.tracker.main_id,
            self.subscription.watch,
            self.tracker.objects,
        )

    def _send_meters(self, now):
        entries = self.meter_frames.build(self.meter_ids(), self._meter_lookup)
        self.meter_seq += 1
        self._send(protocol.meters(self.meter_seq, entries))

    def _meter_lookup(self, tid):
        return self.tracker.objects.get(tid), self.tracker.has_audio_output(tid)

    def _send_heartbeat(self, now):
        self._next_heartbeat = now + HEARTBEAT_SECONDS
        self.heartbeat_seq += 1
        self._send(protocol.heartbeat(self.heartbeat_seq))

    # Sending

    def _send_error(self, text):
        self._send(protocol.error(text))

    def _send(self, message):
        data = protocol.encode(message)
        if len(data) > MAX_DATAGRAM_BYTES:
            self._log.limited("oversize", "dropped a %r message of %d bytes" % (message.get("t"), len(data)))
            return False
        if not self._transport.is_open:
            return False
        if self._transport.send(data, self.subscription.reply_port):
            self.stats["sent"] += 1
            return True
        self.stats["send_failures"] += 1
        self._log.limited("send", "send failed: %s" % self._transport.last_error)
        return False
