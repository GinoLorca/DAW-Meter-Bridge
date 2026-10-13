#!/usr/bin/env python3
"""Fake Ableton Live for running the MeterBridge Remote Script without Live.

Injects fake `Live` and `_Framework` modules, builds a fake song (tracks, two
returns, the main track) and a fake MackieControl stack, then instantiates the
REAL script through MeterBridge.create_instance() and drives its timer in real
time with real UDP on 127.0.0.1:47801. The macOS app's LiveSource connects to it
exactly as it would to Live. Commands from the app change the fake song, and the
meters move like music.

    python3 AbletonRemoteScript/tools/fake_live.py --tracks 24 --xts 0 --bank-step-seconds 0 --duration 0

`--bank-step-seconds 0` never banks; `--duration 0` runs until Ctrl-C.

The tests import the fakes from this module.
"""

import argparse
import math
import os
import random
import signal
import struct
import sys
import time
import types

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT_ROOT = os.path.dirname(HERE)
if SCRIPT_ROOT not in sys.path:
    sys.path.insert(0, SCRIPT_ROOT)

#: Live's own refusal texts (from the user's Live 11 log and the 12.4.6 binary).
UNDO_REFUSAL = "Changes cannot be triggered during undo or redo. You will need to defer your response."
NOTIFICATION_REFUSAL = "Changes cannot be triggered by notifications. You will need to defer your response."

NUM_SLOTS = 7
STRIPS_PER_UNIT = 8

#: (name, kind, meter style). Kind "midi-out" is a MIDI track without an instrument (no audio output).
TRACK_TEMPLATE = [
    ("Kick", "audio", "kick"),
    ("Snare", "audio", "snare"),
    ("Hats", "audio", "hats"),
    ("Bass", "audio", "bass"),
    ("Keys", "midi", "pad"),
    ("Pad", "midi", "pad"),
    ("Lead Vox", "audio", "lead"),
    ("BV High", "audio", "lead"),
    ("BV Low", "audio", "lead"),
    ("Gtr L", "audio", "pad"),
    ("Gtr R", "audio", "pad"),
    ("Synth Lead", "midi", "lead"),
    ("Clip Triggers", "midi-out", "midi"),
    ("Perc", "audio", "hats"),
    ("FX Riser", "audio", "fx"),
    ("Room Mics", "audio", "silent"),
]

#: Colours in the spirit of Live's clip/track palette.
PALETTE = [
    0xFF94A6, 0xFFA529, 0xCC9927, 0xF7F47C, 0xBFFB00, 0x1AFF2F, 0x25FFA8, 0x5CFFE8,
    0x8BC5FF, 0x5480E4, 0x92A7FF, 0xD86CE4, 0xE553A0, 0xFFFFFF, 0xFF3636, 0xF66C03,
]

_pointer = [0x7F8A10004000]


def next_pointer():
    """A fresh fake `_live_ptr` value."""
    _pointer[0] += 0x2F0
    return _pointer[0]


def float32(value):
    """Rounds like Live's 32-bit parameter storage."""
    return struct.unpack("f", struct.pack("f", float(value)))[0]


def fader_db(value):
    """Approximate dB of Live's mixer fader (0.85 = 0 dB, 1.0 = +6 dB). None for -inf."""
    if value <= 0:
        return None
    if value >= 0.4:
        return (value - 0.85) / 0.15 * 6.0
    return -18.0 + 52.0 * math.log10(value / 0.4) / 1.6


def volume_text(value):
    """Volume text the way Live prints it."""
    db = fader_db(value)
    if db is None:
        return "-inf dB"
    return "%.1f dB" % db


# Fake Live Object Model


class FakeParameter(object):
    """A DeviceParameter: value in min..max, str_for_value(), str(), begin_gesture()/end_gesture()."""

    def __init__(self, song, owner, name, value=0.85, minimum=0.0, maximum=1.0):
        self._song = song
        self._owner = owner
        self.name = name
        self.min = minimum
        self.max = maximum
        self._value = float32(value)

    @property
    def value(self):
        return self._value

    @value.setter
    def value(self, value):
        self._song.check_write()
        if not (self.min <= value <= self.max):
            raise RuntimeError("Invalid value")
        self._value = float32(value)
        self._song.record_write("%r %s -> %s" % (self._owner.name, self.name, volume_text(self._value)))

    def str_for_value(self, value):
        return volume_text(value)

    def __str__(self):
        return volume_text(self._value)

    def begin_gesture(self):
        self._song.record_gesture("begin", self)

    def end_gesture(self):
        self._song.record_gesture("end", self)


class FakeMixerDevice(object):
    def __init__(self, song, owner, volume):
        self.volume = FakeParameter(song, owner, "Volume", volume)
        self.panning = FakeParameter(song, owner, "Pan", 0.0, -1.0, 1.0)


class MeterProfile(object):
    """Deterministic, music-like motion for one track's pre-fader level (Live's 0..1 meter scale)."""

    def __init__(self, rng, style):
        self.style = style
        self.level = rng.uniform(0.6, 0.88)
        self.phase = rng.random()
        self.width = rng.uniform(0.02, 0.12)
        self._rng = rng

    def level_at(self, t, tempo):
        beat = t * tempo / 60.0 + self.phase
        style = self.style
        if style == "silent":
            return 0.0
        if style == "kick":
            env = math.exp(-7.0 * (beat % 1.0))
        elif style == "snare":
            env = math.exp(-9.0 * ((beat + 1.0) % 2.0))
        elif style == "hats":
            env = 0.55 + 0.45 * math.exp(-12.0 * ((beat * 2.0) % 1.0))
        elif style == "bass":
            env = 0.65 + 0.35 * math.exp(-3.0 * (beat % 1.0))
        elif style == "pad":
            env = 0.72 + 0.2 * math.sin(2 * math.pi * (t * 0.11 + self.phase))
        elif style == "lead":
            phrase = math.sin(2 * math.pi * (t / 9.0 + self.phase))
            env = 0.0 if phrase < -0.3 else 0.55 + 0.4 * abs(math.sin(math.pi * beat / 2.0))
        elif style == "fx":
            env = ((t / 8.0 + self.phase) % 1.0) ** 2
        elif style == "midi":
            env = 0.9 if (beat % 1.0) < 0.25 else 0.0
        else:
            env = 0.5
        jitter = 1.0 + self._rng.uniform(-0.04, 0.04)
        return max(0.0, min(1.0, self.level * env * jitter))


class FakeTrack(object):
    """A Live Track. Kinds: audio, midi, group, return, main."""

    def __init__(self, song, name, kind, color=None, has_audio_output=True, style="pad", volume=0.85):
        self._song = song
        self._live_ptr = next_pointer()
        self._name = name
        self._color = color if color is not None else 0x9B9B9B
        self.kind = kind
        self._mute = False
        self._solo = False
        self._arm = False
        self._has_audio_output = has_audio_output
        self.group_track = None
        self._fold_state = False
        self.mixer_device = FakeMixerDevice(song, self, volume)
        self.profile = MeterProfile(song.rng, style)

    def __repr__(self):
        return "<FakeTrack %r %s>" % (self._name, self.kind)

    # Identity and look

    @property
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        self._song.check_write()
        self._name = value

    @property
    def color(self):
        return self._color

    @color.setter
    def color(self, value):
        self._song.check_write()
        self._color = value

    @property
    def is_foldable(self):
        return self.kind == "group"

    @property
    def is_grouped(self):
        return self.group_track is not None

    @property
    def fold_state(self):
        if not self.is_foldable:
            raise RuntimeError("Track is not foldable")
        return self._fold_state

    @fold_state.setter
    def fold_state(self, value):
        if not self.is_foldable:
            raise RuntimeError("Track is not foldable")
        self._fold_state = bool(value)

    @property
    def has_midi_input(self):
        return self.kind == "midi"

    @property
    def has_audio_input(self):
        return self.kind == "audio"

    @property
    def has_audio_output(self):
        return self._has_audio_output

    @property
    def can_be_armed(self):
        return self.kind in ("audio", "midi")

    # Mixer state

    @property
    def mute(self):
        if self.kind == "main":
            raise RuntimeError("Main track has no 'Mute' state")
        return self._mute

    @mute.setter
    def mute(self, value):
        if self.kind == "main":
            raise RuntimeError("Main track has no 'Mute' state")
        self._song.check_write()
        self._mute = bool(value)
        self._song.record_write("%r mute -> %s" % (self._name, self._mute))

    @property
    def solo(self):
        if self.kind == "main":
            raise RuntimeError("Main track has no 'Solo' state")
        return self._solo

    @solo.setter
    def solo(self, value):
        if self.kind == "main":
            raise RuntimeError("Main track has no 'Solo' state")
        self._song.check_write()
        self._solo = bool(value)
        self._song.record_write("%r solo -> %s" % (self._name, self._solo))

    @property
    def arm(self):
        if not self.can_be_armed:
            raise RuntimeError("Main and Return Tracks have no 'Arm' state!")
        return self._arm

    @arm.setter
    def arm(self, value):
        if not self.can_be_armed:
            raise RuntimeError("Main and Return Tracks have no 'Arm' state!")
        self._song.check_write()
        self._arm = bool(value)
        self._song.record_write("%r arm -> %s" % (self._name, self._arm))

    @property
    def muted_via_solo(self):
        return self._song.is_muted_via_solo(self)

    # Meters

    @property
    def output_meter_left(self):
        if not self._has_audio_output:
            raise RuntimeError("Tracks with MIDI output have no 'output_meter_left' property")
        return self._song.meter(self)[0]

    @property
    def output_meter_right(self):
        if not self._has_audio_output:
            raise RuntimeError("Tracks with MIDI output have no 'output_meter_right' property")
        return self._song.meter(self)[1]

    @property
    def output_meter_level(self):
        left, right = self._song.meter(self)
        return max(left, right)


class FakeSongView(object):
    def __init__(self, song):
        self._song = song
        self._selected_track = None

    @property
    def selected_track(self):
        return self._selected_track

    @selected_track.setter
    def selected_track(self, track):
        self._song.check_write()
        self._selected_track = track
        self._song.record_write("selected %r" % (track.name if track is not None else None))


class FakeSong(object):
    """A Live Song with `track_count` tracks, returns and a main track, and fake meter motion."""

    def __init__(self, track_count=24, return_count=2, group=False, seed=7, exclusive_solo=True):
        self.rng = random.Random(seed)
        self.tempo = 120.0
        #: Seconds; the harness advances it, meters are computed from it.
        self.now = 0.0
        self.exclusive_solo = exclusive_solo
        self.exclusive_arm = True
        #: Upcoming writes to refuse as if Live were in undo/redo.
        self.refuse_writes = 0
        #: Text of every write applied, in order.
        self.writes = []
        #: (event, parameter owner name) for begin/end_gesture and begin/end_undo_step calls, in order.
        self.gestures = []
        #: Undo steps begun and not yet ended.
        self.undo_depth = 0
        #: Make begin_gesture() / begin_undo_step() raise, to test balancing.
        self.fail_gestures = False
        self.fail_undo_steps = False
        #: Optional callback(text) for each write.
        self.on_write = None
        self._meter_cache = {}
        self._meter_time = None
        self.tracks = []
        for index in range(track_count):
            name, kind, style = TRACK_TEMPLATE[index % len(TRACK_TEMPLATE)]
            if index >= len(TRACK_TEMPLATE):
                name = "%s %d" % (name, index // len(TRACK_TEMPLATE) + 1)
            has_audio_output = kind != "midi-out"
            kind = "midi" if kind == "midi-out" else kind
            volume = 0.85 - 0.05 * self.rng.random()
            self.tracks.append(
                FakeTrack(self, name, kind, PALETTE[index % len(PALETTE)], has_audio_output, style, volume)
            )
        self.group = None
        if group and track_count >= 3:
            self.group = FakeTrack(self, "Drums", "group", 0xFFA529, True, "kick")
            for child in self.tracks[:3]:
                child.group_track = self.group
            self.tracks.insert(0, self.group)
        self.return_tracks = [
            FakeTrack(self, "%s-%s" % (chr(65 + k % 26), ("Reverb", "Delay")[k % 2]), "return", 0x5CFFE8, True, "pad", 0.7)
            for k in range(return_count)
        ]
        self.master_track = FakeTrack(self, "Main", "main", 0xD0D0D0, True, "pad")
        self.view = FakeSongView(self)
        self.view._selected_track = self.tracks[0] if self.tracks else self.master_track

    @property
    def visible_tracks(self):
        """Tracks not hidden inside a folded group."""
        result = []
        for track in self.tracks:
            parent = track.group_track
            hidden = False
            while parent is not None:
                if parent._fold_state:
                    hidden = True
                    break
                parent = parent.group_track
            if not hidden:
                result.append(track)
        return result

    def all_tracks(self):
        return self.tracks + self.return_tracks + [self.master_track]

    def find(self, name):
        """The track called `name`."""
        for track in self.all_tracks():
            if track.name == name:
                return track
        raise KeyError(name)

    # Writes

    def check_write(self):
        """Raises like Live does during undo/redo while `refuse_writes` is positive."""
        if self.refuse_writes > 0:
            self.refuse_writes -= 1
            raise RuntimeError(UNDO_REFUSAL)

    def record_write(self, text):
        self._meter_cache = {}
        self.writes.append(text)
        if self.on_write is not None:
            self.on_write(text)

    def record_gesture(self, event, parameter):
        if event == "begin" and self.fail_gestures:
            raise RuntimeError("begin_gesture failed")
        self.gestures.append((event + "_gesture", parameter._owner.name))
        if self.on_write is not None:
            self.on_write("%r %s %s_gesture" % (parameter._owner.name, parameter.name, event))

    def begin_undo_step(self):
        if self.fail_undo_steps:
            raise RuntimeError("begin_undo_step failed")
        self.undo_depth += 1
        self.gestures.append(("begin_undo_step", None))

    def end_undo_step(self):
        self.undo_depth -= 1
        self.gestures.append(("end_undo_step", None))

    def set_folded(self, folded):
        """Folds or unfolds the fake group (if any)."""
        if self.group is not None:
            self.group._fold_state = bool(folded)
            self._meter_cache = {}

    # Solo and meters

    def _ancestors(self, track):
        parent = track.group_track
        while parent is not None:
            yield parent
            parent = parent.group_track

    def is_muted_via_solo(self, track):
        """Approximates Live: soloing silences every other track except related groups; returns stay up."""
        if track.kind == "main" or track._solo:
            return False
        soloed = [t for t in self.tracks + self.return_tracks if t._solo]
        if not soloed:
            return False
        if any(ancestor._solo for ancestor in self._ancestors(track)):
            return False
        if any(track is ancestor for t in soloed for ancestor in self._ancestors(t)):
            return False
        if track.kind == "return" and not any(t.kind == "return" for t in soloed):
            return False
        return True

    def _audible(self, track):
        if track.kind != "main" and (track._mute or self.is_muted_via_solo(track)):
            return False
        return not any(ancestor._mute for ancestor in self._ancestors(track))

    def _post_fader(self, track, level):
        db = fader_db(track.mixer_device.volume.value)
        if db is None:
            return 0.0
        return max(0.0, min(1.0, level * 10 ** (db / 40.0)))

    def meter(self, track):
        """(left, right) on Live's 0..1 meter scale at `self.now` (cached per instant)."""
        if self._meter_time != self.now:
            self._meter_time = self.now
            self._meter_cache = {}
        cached = self._meter_cache.get(track._live_ptr)
        if cached is None:
            cached = self._compute_meter(track)
            self._meter_cache[track._live_ptr] = cached
        return cached

    def _compute_meter(self, track):
        t = self.now
        if track.kind == "main":
            levels = [max(self.meter(other)) for other in self.tracks + self.return_tracks if other.kind != "group"]
            mix = 0.0
            if levels:
                mix = min(1.0, 0.7 * max(levels) + 0.25 * sum(levels) / len(levels))
            level = self._post_fader(track, mix)
        elif not self._audible(track):
            return 0.0, 0.0
        elif track.kind == "group":
            children = [child for child in self.tracks if child.group_track is track]
            level = max([max(self.meter(child)) for child in children] or [0.0])
            level = self._post_fader(track, level)
        elif track.kind == "return":
            sources = [max(self.meter(other)) for other in self.tracks if other.kind != "group"]
            level = self._post_fader(track, 0.6 * sum(sources) / len(sources) if sources else 0.0)
        else:
            level = self._post_fader(track, track.profile.level_at(t, self.tempo))
        wobble = track.profile.width * math.sin(2 * math.pi * (t * 0.7 + track.profile.phase))
        return max(0.0, min(1.0, level * (1 - wobble))), max(0.0, min(1.0, level * (1 + wobble)))


# Fake MackieControl stack


class FakeStripController(object):
    """Bank state shared by a MackieControl and its XTs, like Ableton's ChannelStripController."""

    def __init__(self, song):
        self.song = song
        self.bank_offset = 0
        self.view_returns = False
        #: All strips across the main unit and its extensions; the bank step.
        self.strip_count = STRIPS_PER_UNIT

    def _tracks(self):
        return list(self.song.return_tracks if self.view_returns else self.song.visible_tracks)

    def track_at(self, stack_index):
        tracks = self._tracks()
        index = self.bank_offset + stack_index
        if 0 <= index < len(tracks):
            return tracks[index]
        return None

    def bank(self, direction=1):
        """Banks by the total strip count, wrapping around at the ends."""
        count = len(self._tracks())
        offset = self.bank_offset + direction * self.strip_count
        if offset >= count:
            offset = 0
        elif offset < 0:
            offset = max(0, ((count - 1) // self.strip_count) * self.strip_count)
        self.bank_offset = offset
        return offset


class FakeChannelStrip(object):
    def __init__(self, controller, stack_index):
        self._controller = controller
        self._stack_index = stack_index

    def assigned_track(self):
        return self._controller.track_at(self._stack_index)


class MackieControl(object):
    """Stand-in for Ableton's MackieControl: keeps its own 8 strips in the same private attribute."""

    def __init__(self, controller, stack_offset):
        self.controller = controller
        self.__channel_strips = [FakeChannelStrip(controller, stack_offset + k) for k in range(STRIPS_PER_UNIT)]


class MackieControlXT(object):
    """Stand-in for Ableton's MackieControlXT, with its public channel_strips()."""

    def __init__(self, controller, stack_offset):
        self.controller = controller
        self.__channel_strips = [FakeChannelStrip(controller, stack_offset + k) for k in range(STRIPS_PER_UNIT)]

    def channel_strips(self):
        return self.__channel_strips


class OtherScript(object):
    """Some other control surface in a slot (a keyboard script, AbletonMCP, ...)."""


def build_mackie_stack(song, left_xts=0, right_xts=0, first_slot=1):
    """(controller, slots) with left XTs, the main unit and right XTs in consecutive slots.

    `slots` has NUM_SLOTS entries (None for empty). Stack offsets follow
    MackieControl: left extensions first, then the main unit, then the right ones.
    """
    if left_xts + 1 + right_xts + first_slot - 1 > NUM_SLOTS:
        raise ValueError("too many units for %d slots" % NUM_SLOTS)
    controller = FakeStripController(song)
    controller.strip_count = STRIPS_PER_UNIT * (left_xts + 1 + right_xts)
    slots = [None] * NUM_SLOTS
    slot = first_slot - 1
    stack = 0
    for _ in range(left_xts):
        slots[slot] = MackieControlXT(controller, stack)
        slot += 1
        stack += STRIPS_PER_UNIT
    slots[slot] = MackieControl(controller, stack)
    slot += 1
    stack += STRIPS_PER_UNIT
    for _ in range(right_xts):
        slots[slot] = MackieControlXT(controller, stack)
        slot += 1
        stack += STRIPS_PER_UNIT
    return controller, slots


# Fake Live and _Framework modules


class FakeTimer(object):
    """Stand-in for Live.Base.Timer(callback=..., interval=<ms>, repeat=True)."""

    #: Every timer created since the fakes were installed.
    instances = []

    def __init__(self, callback=None, interval=1, repeat=False, start=False):
        self.callback = callback
        self.interval = interval
        self.repeat = repeat
        self.running = False
        self.due = None
        FakeTimer.instances.append(self)
        if start:
            self.start()

    def start(self):
        self.running = True
        self.due = None

    def stop(self):
        self.running = False

    def fire_if_due(self, now):
        """Calls the callback when the interval has passed. Returns True if it fired."""
        if not self.running:
            return False
        period = self.interval / 1000.0
        if self.due is None:
            self.due = now + period
            return False
        if now < self.due:
            return False
        self.due += period
        if self.due < now:
            self.due = now + period
        if not self.repeat:
            self.running = False
        self.callback()
        return True


class FakeApplication(object):
    """Live.Application.Application: control_surfaces and the version getters."""

    def __init__(self, control_surfaces, version=(12, 4, 6)):
        self.control_surfaces = control_surfaces
        self._version = version

    def get_major_version(self):
        return self._version[0]

    def get_minor_version(self):
        return self._version[1]

    def get_bugfix_version(self):
        return self._version[2]


class FakeCInstance(object):
    """The c_instance Live passes to create_instance()."""

    def __init__(self, song, log=None):
        self._song = song
        self._log = log
        self.logged = []

    def song(self):
        return self._song

    def log_message(self, message):
        self.logged.append(message)
        if self._log is not None:
            self._log(message)

    def show_message(self, message):
        pass


class FakeControlSurface(object):
    """Minimal _Framework.ControlSurface.ControlSurface."""

    def __init__(self, c_instance):
        self._c_instance = c_instance

    def song(self):
        return self._c_instance.song()

    def application(self):
        return _state["application"]

    def log_message(self, *message):
        if self._c_instance is not None:
            text = "(%s) %s" % (self.__class__.__name__, " ".join(str(part) for part in message))
            self._c_instance.log_message(text)

    def update_display(self):
        pass

    def disconnect(self):
        self._c_instance = None


_state = {"application": None, "installed": False}


def install_fake_live(application):
    """Puts fake `Live` and `_Framework` modules in sys.modules; get_application() returns `application`."""
    _state["application"] = application
    FakeTimer.instances = []
    if _state["installed"]:
        return
    live = types.ModuleType("Live")
    base = types.ModuleType("Live.Base")
    base.Timer = FakeTimer
    app_module = types.ModuleType("Live.Application")
    app_module.get_application = lambda: _state["application"]
    live.Base = base
    live.Application = app_module
    framework = types.ModuleType("_Framework")
    framework.__path__ = []
    control_surface = types.ModuleType("_Framework.ControlSurface")
    control_surface.ControlSurface = FakeControlSurface
    framework.ControlSurface = control_surface
    sys.modules["Live"] = live
    sys.modules["Live.Base"] = base
    sys.modules["Live.Application"] = app_module
    sys.modules["_Framework"] = framework
    sys.modules["_Framework.ControlSurface"] = control_surface
    _state["installed"] = True


class FakeLive(object):
    """A fake Live session running the real MeterBridge script in a free control-surface slot."""

    def __init__(
        self,
        track_count=24,
        left_xts=0,
        right_xts=0,
        return_count=2,
        group=False,
        seed=7,
        exclusive_solo=True,
        version=(12, 4, 6),
        log=None,
        transport_factory=None,
    ):
        self.song = FakeSong(track_count, return_count, group, seed, exclusive_solo)
        self.controller, self.slots = build_mackie_stack(self.song, left_xts, right_xts)
        self.application = FakeApplication(self.slots, version)
        install_fake_live(self.application)
        self.c_instance = FakeCInstance(self.song, log)
        #: The clock the script sees; step() moves it.
        self.now = time.monotonic()
        import MeterBridge
        from MeterBridge import live_surface

        saved = (live_surface.make_transport, live_surface.clock)
        if transport_factory is not None:
            live_surface.make_transport = transport_factory
        live_surface.clock = lambda: self.now
        try:
            self.surface = MeterBridge.create_instance(self.c_instance)
        finally:
            live_surface.make_transport, live_surface.clock = saved
        self.slot = self.slots.index(None) + 1 if None in self.slots else None
        if self.slot is not None:
            self.slots[self.slot - 1] = self.surface
        self._last_display = None

    @property
    def bridge(self):
        """The script's Bridge (None after disconnect)."""
        return self.surface.meter_bridge

    def step(self, now):
        """Advances the clock to `now` and fires due timers and update_display, like Live's main loop."""
        self.now = now
        self.song.now = now
        for timer in list(FakeTimer.instances):
            timer.fire_if_due(now)
        if self._last_display is None or now - self._last_display >= 0.1:
            self._last_display = now
            self.surface.update_display()

    def next_due(self, now):
        """Seconds until the next timer is due (for sleeping)."""
        dues = [timer.due for timer in FakeTimer.instances if timer.running and timer.due is not None]
        if not dues:
            return 0.005
        return max(0.0, min(dues) - now)

    def disconnect(self):
        self.surface.disconnect()


# Command line


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Run the MeterBridge Remote Script against a fake Live with real UDP.")
    parser.add_argument("--tracks", type=int, default=24, help="number of tracks (default 24)")
    parser.add_argument("--xts", type=int, default=0, help="MackieControlXT units right of the main unit (default 0)")
    parser.add_argument("--left-xts", type=int, default=0, help="MackieControlXT units left of the main unit")
    parser.add_argument("--returns", type=int, default=2, help="number of return tracks (default 2)")
    parser.add_argument(
        "--bank-step-seconds", type=float, default=0.0, help="bank the surface every N seconds (0 = never)"
    )
    parser.add_argument("--duration", type=float, default=0.0, help="stop after N seconds (0 = run until Ctrl-C)")
    parser.add_argument("--group", action="store_true", help="put the first three tracks in a 'Drums' group")
    parser.add_argument(
        "--fold-seconds", type=float, default=0.0, help="fold/unfold the group every N seconds (implies --group)"
    )
    parser.add_argument("--no-exclusive-solo", action="store_true", help="turn Live's Exclusive Solo preference off")
    parser.add_argument("--live-version", default="12.4.6", help="version the fake Live reports")
    parser.add_argument("--seed", type=int, default=7, help="random seed for colours and meter motion")
    parser.add_argument("--quiet", action="store_true", help="only print the script's log and errors")
    args = parser.parse_args(argv)
    if args.tracks < 0 or args.xts < 0 or args.left_xts < 0 or args.returns < 0:
        parser.error("counts must not be negative")
    if args.left_xts + 1 + args.xts + 1 > NUM_SLOTS:
        parser.error("main unit + XTs + MeterBridge must fit in %d slots" % NUM_SLOTS)
    try:
        version = tuple(int(part) for part in args.live_version.split("."))
        if len(version) != 3:
            raise ValueError
    except ValueError:
        parser.error("--live-version must look like 12.4.6")
    args.version = version
    if args.fold_seconds > 0:
        args.group = True
    return args


def _stamp():
    return time.strftime("%H:%M:%S")


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)

    def say(text):
        print("%s %s" % (_stamp(), text))
        sys.stdout.flush()

    live = FakeLive(
        track_count=args.tracks,
        left_xts=args.left_xts,
        right_xts=args.xts,
        return_count=args.returns,
        group=args.group,
        seed=args.seed,
        exclusive_solo=not args.no_exclusive_solo,
        version=args.version,
        log=lambda message: say("[script] " + message),
    )
    if not args.quiet:
        live.song.on_write = lambda text: say("[live] " + text)
    units = args.left_xts + 1 + args.xts
    say(
        "[fake] Live %s: %d tracks%s + %d returns + main; MackieControl in slot %d with %d XT(s) left, %d right "
        "(bank step %d); MeterBridge in slot %s; exclusive solo %s"
        % (
            args.live_version,
            args.tracks,
            " (Drums group)" if args.group else "",
            args.returns,
            args.left_xts + 1,
            args.left_xts,
            args.xts,
            units * STRIPS_PER_UNIT,
            live.slot,
            "off" if args.no_exclusive_solo else "on",
        )
    )
    say("[fake] the app subscribes by sending to 127.0.0.1:47801; Ctrl-C to stop")
    stop = []

    def request_stop(signum, frame):
        stop.append(signum)

    # Explicit handlers, so Ctrl-C and `kill` stop cleanly even when started in the
    # background (where SIGINT is inherited as ignored).
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, request_stop)
    start = time.monotonic()
    next_bank = start + args.bank_step_seconds if args.bank_step_seconds > 0 else None
    next_fold = start + args.fold_seconds if args.fold_seconds > 0 else None
    next_status = start + 5.0
    subscribed = False
    try:
        while not stop:
            now = time.monotonic()
            if args.duration > 0 and now - start >= args.duration:
                break
            live.step(now)
            bridge = live.bridge
            if bridge is not None and bridge.is_subscribed != subscribed:
                subscribed = bridge.is_subscribed
                say("[fake] app %s" % ("subscribed" if subscribed else "gone (no sub for 5 s)"))
            if next_bank is not None and now >= next_bank:
                next_bank += args.bank_step_seconds
                offset = live.controller.bank(1)
                if not args.quiet:
                    say("[fake] surface banked to offset %d" % offset)
            if next_fold is not None and now >= next_fold:
                next_fold += args.fold_seconds
                folded = not live.song.group._fold_state
                live.song.set_folded(folded)
                if not args.quiet:
                    say("[fake] Drums group %s" % ("folded" if folded else "unfolded"))
            if now >= next_status:
                next_status += 5.0
                if not args.quiet and bridge is not None:
                    say(
                        "[fake] subscribed=%s hz=%d sent=%d received=%d commands=%d errors=%d"
                        % (
                            "yes" if bridge.is_subscribed else "no",
                            bridge.hz,
                            bridge.stats["sent"],
                            bridge.stats["received"],
                            bridge.stats["commands"],
                            bridge.stats["errors"],
                        )
                    )
            time.sleep(min(0.01, max(0.001, live.next_due(time.monotonic()))))
    except KeyboardInterrupt:
        pass
    finally:
        live.disconnect()
        say("[fake] stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
