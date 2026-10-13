"""Commands from the app: parsing, queueing, and applying them to Live. Pure module: no Live import.

Commands are queued when they arrive and applied only from the timer tick, on
Live's main thread and never from inside a listener callback (Live raises
"Changes cannot be triggered by notifications"). Live also refuses changes
during undo/redo; such a command stays at the head of the queue and is retried
on the next tick, at most MAX_RETRIES times.

A volume drag arrives as a stream of `vol` commands. VolumeGestures wraps it in
parameter.begin_gesture()/end_gesture() and one Song undo step, as Live does for
a mouse drag on its own fader (docs/PROTOCOL.md, `vol`).
"""

from collections import OrderedDict

from .lom import ARMABLE_KINDS, KIND_MAIN, safe_get, safe_list, track_id, volume_parameter
from .protocol import finite_or, is_int, is_number

OP_SELECT = "select"
OP_MUTE = "mute"
OP_SOLO = "solo"
OP_ARM = "arm"
OP_VOLUME = "vol"
OPS = (OP_SELECT, OP_MUTE, OP_SOLO, OP_ARM, OP_VOLUME)

#: Retries after the first refused attempt.
MAX_RETRIES = 3
#: Commands applied per tick at most, so a flood cannot stall Live.
MAX_PER_TICK = 32
#: Commands kept waiting at most; the oldest are dropped beyond this.
MAX_QUEUED = 256

#: Text of Live's refusals that go away on a later tick (undo/redo, notifications).
REFUSAL_MARKER = "Changes cannot be triggered"

#: Seconds without a `vol` for a track before its drag gesture is closed.
GESTURE_IDLE_SECONDS = 0.5
#: Live stores parameter values as 32-bit floats; closer values than this count as unchanged.
VALUE_EPSILON = 1e-7

APPLIED = "applied"
IGNORED = "ignored"
RETRY = "retry"
ERROR = "error"


class Command(object):
    """One parsed `cmd` message."""

    def __init__(self, op, track_id, on=None, exclusive=None, value=None, end=False):
        self.op = op
        self.track_id = track_id
        self.on = on
        #: For solo and arm: True, False, or None to follow song.exclusive_solo / exclusive_arm.
        self.exclusive = exclusive
        #: For vol: the requested normalized value.
        self.value = value
        #: For vol: True on the last value of a drag, which closes the drag gesture.
        self.end = end
        #: Refused attempts so far.
        self.refusals = 0

    def describe(self):
        """Short text for logs and `err` messages."""
        return "%s on track %s" % (self.op, self.track_id)


class Result(object):
    """What happened to one command during a tick."""

    def __init__(self, status, command, message=None):
        self.status = status
        self.command = command
        self.message = message


def parse_command(message):
    """(Command, None) for a valid `cmd` message, else (None, error text)."""
    op = message.get("op")
    if op not in OPS:
        return None, "unknown cmd op %r" % (op,)
    tid = message.get("id")
    if not is_int(tid):
        return None, "cmd %s needs an integer id" % op
    if op == OP_SELECT:
        return Command(op, tid), None
    if op == OP_VOLUME:
        value = message.get("val")
        if not is_number(value):
            return None, "cmd vol needs a numeric val"
        end = message.get("end")
        if end is not None and not isinstance(end, bool):
            return None, "cmd vol needs end to be true or false"
        return Command(op, tid, value=float(value), end=end is True), None
    on = message.get("on")
    if not isinstance(on, bool):
        return None, "cmd %s needs a boolean on" % op
    if op in (OP_SOLO, OP_ARM):
        exclusive = message.get("excl")
        if exclusive is not None and not isinstance(exclusive, bool):
            return None, "cmd %s needs excl to be true, false or null" % op
        return Command(op, tid, on=on, exclusive=exclusive), None
    return Command(op, tid, on=on), None


def is_refusal(exc):
    """True when Live refused a change that may succeed on a later tick."""
    try:
        return REFUSAL_MARKER in str(exc)
    except Exception:
        return False


def _set_if_different(obj, name, value):
    if getattr(obj, name) != value:
        setattr(obj, name, value)


def apply_command(command, song, resolve, gestures=None, now=0.0):
    """Applies one command to Live. Returns a Result; raises when Live refuses the change.

    `resolve(track_id)` returns (track, kind) or (None, None). `gestures` (a
    VolumeGestures, optional) groups a volume drag into one gesture and undo
    step; any other command closes the open gestures first.
    """
    op = command.op
    if gestures is not None and op != OP_VOLUME:
        gestures.end_all()
    track, kind = resolve(command.track_id)
    if track is None:
        return Result(ERROR, command, "unknown track id %s in cmd" % command.track_id)
    if op == OP_SELECT:
        view = song.view
        if view.selected_track != track:
            view.selected_track = track
        return Result(APPLIED, command)
    if op == OP_VOLUME:
        parameter = volume_parameter(track)
        if parameter is None:
            return Result(ERROR, command, "track %s has no volume" % command.track_id)
        low = finite_or(safe_get(parameter, "min"), 0.0)
        high = finite_or(safe_get(parameter, "max"), 1.0)
        value = min(max(command.value, low), high)
        if abs(parameter.value - value) > VALUE_EPSILON:
            if gestures is not None:
                gestures.touch(command.track_id, parameter, song, now)
            parameter.value = value
        if gestures is not None:
            if command.end:
                gestures.end(command.track_id)
            else:
                gestures.keep_alive(command.track_id, now)
        return Result(APPLIED, command)
    if op in (OP_MUTE, OP_SOLO) and kind == KIND_MAIN:
        return Result(ERROR, command, "the main track has no %s; ignored" % op)
    if op == OP_MUTE:
        _set_if_different(track, "mute", command.on)
        return Result(APPLIED, command)
    if op == OP_SOLO:
        exclusive = command.exclusive
        if exclusive is None:
            exclusive = bool(safe_get(song, "exclusive_solo", False))
        if command.on and exclusive:
            unsolo_others(song, command.track_id)
        _set_if_different(track, "solo", command.on)
        return Result(APPLIED, command)
    if op == OP_ARM:
        if kind not in ARMABLE_KINDS or not safe_get(track, "can_be_armed", False):
            return Result(IGNORED, command)
        exclusive = command.exclusive
        if exclusive is None:
            exclusive = bool(safe_get(song, "exclusive_arm", False))
        if command.on and exclusive:
            disarm_others(song, command.track_id)
        _set_if_different(track, "arm", command.on)
        return Result(APPLIED, command)
    return Result(ERROR, command, "unknown cmd op %r" % (op,))


def unsolo_others(song, keep_id):
    """Clears solo on every track and return track except `keep_id`.

    Setting `track.solo` bypasses Live's Exclusive Solo preference, so exclusive
    solo is done by hand, like Ableton's MackieControl does. `song.tracks`
    includes tracks inside folded groups.
    """
    for other in safe_list(song, "tracks") + safe_list(song, "return_tracks"):
        if track_id(other) != keep_id and safe_get(other, "solo", False):
            other.solo = False


def disarm_others(song, keep_id):
    """Clears arm on every armable track except `keep_id`.

    Setting `track.arm` bypasses Live's Exclusive Arm preference, so exclusive
    arm is done by hand, like Ableton's MackieControl does. `song.tracks`
    includes tracks inside folded groups.
    """
    for other in safe_list(song, "tracks"):
        if (
            track_id(other) != keep_id
            and safe_get(other, "can_be_armed", False)
            and safe_get(other, "arm", False)
        ):
            other.arm = False


def _same_object(a, b):
    """True when `a` and `b` are the same Live object. Live may hand out a new Python
    wrapper on every property access, so wrappers are compared by `_live_ptr` too."""
    if a is b:
        return True
    pointer = safe_get(a, "_live_ptr")
    return pointer is not None and pointer == safe_get(b, "_live_ptr")


def _call(obj, name):
    """Calls obj.name() and returns True, or False when it is missing or raises."""
    try:
        getattr(obj, name)()
        return True
    except Exception:
        return False


class VolumeGestures(object):
    """Open drag gestures on volume parameters, one per track.

    The first write of a drag calls parameter.begin_gesture() and, when no other
    gesture is open, song.begin_undo_step(); closing a gesture calls
    end_gesture(), and closing the last one end_undo_step(). An end call is made
    only when its begin call succeeded, so the pairs stay balanced. Only call it
    from the timer tick.
    """

    def __init__(self, idle=GESTURE_IDLE_SECONDS):
        self.idle = idle
        #: track id -> [parameter, gesture began, last vol time]
        self._open = OrderedDict()
        self._undo_song = None

    def __len__(self):
        return len(self._open)

    def touch(self, tid, parameter, song, now):
        """Opens the gesture of `tid` on `parameter` (before a write) unless it is open."""
        entry = self._open.get(tid)
        if entry is not None and not _same_object(entry[0], parameter):
            self.end(tid)
            entry = None
        if entry is None:
            if not self._open and self._undo_song is None and _call(song, "begin_undo_step"):
                self._undo_song = song
            self._open[tid] = [parameter, _call(parameter, "begin_gesture"), now]
        else:
            entry[2] = now

    def keep_alive(self, tid, now):
        """Records a `vol` for `tid` that did not change the value."""
        entry = self._open.get(tid)
        if entry is not None:
            entry[2] = now

    def end(self, tid):
        """Closes the gesture of `tid`, if open."""
        entry = self._open.pop(tid, None)
        if entry is not None and entry[1]:
            _call(entry[0], "end_gesture")
        if not self._open and self._undo_song is not None:
            song = self._undo_song
            self._undo_song = None
            _call(song, "end_undo_step")

    def end_idle(self, now):
        """Closes gestures with no `vol` for `idle` seconds."""
        for tid in [tid for tid, entry in self._open.items() if now - entry[2] >= self.idle]:
            self.end(tid)

    def end_all(self):
        """Closes every open gesture."""
        for tid in list(self._open.keys()):
            self.end(tid)
        if self._undo_song is not None:
            song = self._undo_song
            self._undo_song = None
            _call(song, "end_undo_step")


class CommandQueue(object):
    """FIFO of commands waiting for the next tick."""

    def __init__(self, max_per_tick=MAX_PER_TICK, max_retries=MAX_RETRIES, max_queued=MAX_QUEUED):
        self._pending = []
        self._max_per_tick = max_per_tick
        self._max_retries = max_retries
        self._max_queued = max_queued
        #: Commands dropped because the queue overflowed.
        self.dropped = 0

    def __len__(self):
        return len(self._pending)

    def enqueue(self, command):
        """Adds a command. A volume change replaces a volume change for the same track still waiting at the tail."""
        if self._pending and command.op == OP_VOLUME:
            last = self._pending[-1]
            if last.op == OP_VOLUME and last.track_id == command.track_id and last.refusals == 0:
                last.value = command.value
                last.end = last.end or command.end
                return
        self._pending.append(command)
        if len(self._pending) > self._max_queued:
            del self._pending[0]
            self.dropped += 1

    def apply(self, song, resolve, gestures=None, now=0.0):
        """Applies waiting commands in order and returns their Results.

        A refused command stays at the head and stops this tick's processing, so
        later commands keep their order. It gives up after `max_retries` retries.
        """
        results = []
        processed = 0
        while self._pending and processed < self._max_per_tick:
            command = self._pending[0]
            processed += 1
            try:
                result = apply_command(command, song, resolve, gestures, now)
            except Exception as exc:
                if is_refusal(exc):
                    command.refusals += 1
                    if command.refusals <= self._max_retries:
                        results.append(Result(RETRY, command, str(exc)))
                        break
                    message = "Live refused %s %d times: %s" % (command.describe(), command.refusals, exc)
                else:
                    message = "%s failed: %s" % (command.describe(), exc)
                result = Result(ERROR, command, message)
            del self._pending[0]
            results.append(result)
        return results
