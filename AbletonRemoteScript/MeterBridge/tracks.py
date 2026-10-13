"""Track-state snapshots and diffs. Pure module: no Live import.

The bridge polls the whole ordered track list about 10 times a second and diffs
it against what it last sent. Polling instead of per-track listeners keeps the
lifecycle simple (nothing to add or remove when tracks change) and never runs
inside a Live notification.
"""

from .lom import (
    ARMABLE_KINDS,
    KIND_MAIN,
    ordered_tracks,
    safe_get,
    selected_track,
    track_id,
    volume_parameter,
)
from .protocol import MAX_NAME_CHARS, clip_text, finite_or

#: Normalized volume is rounded to this many decimals on the wire.
VOLUME_DECIMALS = 6

#: Keys of a track record, in wire order (docs/PROTOCOL.md "Track record").
RECORD_KEYS = ("id", "i", "n", "c", "k", "m", "s", "a", "ms", "ao", "vol", "vs")

_UNSET = object()


def color_of(track):
    """0xRRGGBB colour, or None."""
    color = safe_get(track, "color")
    if isinstance(color, int) and not isinstance(color, bool):
        return color & 0xFFFFFF
    return None


def volume_text(parameter, value):
    """The volume as Live displays it, e.g. "-6.0 dB"; "" when there is no parameter."""
    if parameter is None:
        return ""
    try:
        return clip_text(str(parameter), 64)
    except Exception:
        pass
    try:
        return clip_text(parameter.str_for_value(value), 64)
    except Exception:
        return ""


def snapshot_record(track, kind, index, tid, text_cache=None):
    """One protocol track record. `text_cache` maps id -> (volume, text) to skip str() when unchanged."""
    is_main = kind == KIND_MAIN
    arm = None
    if kind in ARMABLE_KINDS and safe_get(track, "can_be_armed", True):
        arm = bool(safe_get(track, "arm", False))
    parameter = volume_parameter(track)
    volume = round(min(max(finite_or(safe_get(parameter, "value"), 0.0), 0.0), 1.0), VOLUME_DECIMALS)
    cached = text_cache.get(tid) if text_cache is not None else None
    if cached is not None and cached[0] == volume:
        text = cached[1]
    else:
        text = volume_text(parameter, volume)
        if text_cache is not None:
            text_cache[tid] = (volume, text)
    return {
        "id": tid,
        "i": index,
        "n": clip_text(safe_get(track, "name", ""), MAX_NAME_CHARS),
        "c": color_of(track),
        "k": kind,
        "m": False if is_main else bool(safe_get(track, "mute", False)),
        "s": False if is_main else bool(safe_get(track, "solo", False)),
        "a": arm,
        "ms": False if is_main else bool(safe_get(track, "muted_via_solo", False)),
        "ao": bool(safe_get(track, "has_audio_output", True)),
        "vol": volume,
        "vs": text,
    }


class TrackStateTracker(object):
    """Latest track list read from Live, and the baseline last sent to the app.

    `read` refreshes the current state from the song. `diff` reports what changed
    since the previous `diff` (or `reset`) and moves the baseline forward, so the
    caller must send what it returns.
    """

    def __init__(self, id_of=track_id):
        self.id_of = id_of
        #: Track ids in protocol order.
        self.order = []
        #: id -> track record (dict).
        self.records = {}
        #: id -> Live track object, for meters and commands.
        self.objects = {}
        #: id -> kind string.
        self.kinds = {}
        self.main_id = None
        #: Selected track id, or None when it is not in the list.
        self.selected_id = None
        self._text_cache = {}
        self._sent_order = None
        self._sent_records = {}
        self._sent_selected = _UNSET

    def read(self, song):
        """Reads the ordered list, every record and the selection from `song`."""
        order = []
        records = {}
        objects = {}
        kinds = {}
        main_id = None
        text_cache = {}
        for track, kind in ordered_tracks(song):
            tid = self.id_of(track)
            if tid in records:
                continue
            if tid in self._text_cache:
                text_cache[tid] = self._text_cache[tid]
            records[tid] = snapshot_record(track, kind, len(order), tid, text_cache)
            order.append(tid)
            objects[tid] = track
            kinds[tid] = kind
            if kind == KIND_MAIN:
                main_id = tid
        selected = selected_track(song)
        selected_id = self.id_of(selected) if selected is not None else None
        if selected_id not in records:
            selected_id = None
        self.order = order
        self.records = records
        self.objects = objects
        self.kinds = kinds
        self.main_id = main_id
        self.selected_id = selected_id
        self._text_cache = text_cache

    def diff(self):
        """(full_list_needed, changed_records, selection_changed) since the last diff or reset."""
        if self._sent_order != self.order:
            full = True
            changed = []
        else:
            full = False
            changed = [self.records[tid] for tid in self.order if self.records[tid] != self._sent_records.get(tid)]
        selection_changed = self._sent_selected is _UNSET or self._sent_selected != self.selected_id
        self._sent_order = list(self.order)
        self._sent_records = dict(self.records)
        self._sent_selected = self.selected_id
        return full, changed, selection_changed

    def reset(self):
        """Forgets the sent baseline, so the next diff reports a full list and the selection."""
        self._sent_order = None
        self._sent_records = {}
        self._sent_selected = _UNSET

    def refresh(self, tid):
        """Re-reads one known track. Returns its record if it differs from the sent baseline, else None.

        The returned record counts as sent; the caller must send it.
        """
        track = self.objects.get(tid)
        if track is None:
            return None
        record = snapshot_record(track, self.kinds[tid], self.records[tid]["i"], tid, self._text_cache)
        self.records[tid] = record
        if self._sent_order is None or record == self._sent_records.get(tid):
            return None
        self._sent_records[tid] = record
        return record

    def full_list(self):
        """Every record in protocol order."""
        return [self.records[tid] for tid in self.order]

    def resolve(self, tid):
        """(track object, kind) for an id, or (None, None)."""
        return self.objects.get(tid), self.kinds.get(tid)

    def has_audio_output(self, tid):
        """`ao` from the latest read (True when unknown)."""
        record = self.records.get(tid)
        return True if record is None else record["ao"]
