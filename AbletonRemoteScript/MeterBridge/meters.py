"""Meter frames (`m` messages). Pure module: no Live import.

Each frame covers the union of the tracks on surface strips, the selected track,
the main track and the app's watch list, at most MAX_ENTRIES. Values are Live's
own normalized meter scale, rounded to 4 decimals. A track that leaves that set
is sent once more with zeros so the app can drop it.
"""

from .lom import safe_get
from .protocol import finite_or

MAX_ENTRIES = 64
DECIMALS = 4


def round_level(value):
    """A meter value clamped to 0..1 and rounded to 4 decimals (0.0 when unreadable)."""
    level = finite_or(value, 0.0)
    return round(min(max(level, 0.0), 1.0), DECIMALS)


def read_levels(track, has_audio_output):
    """(left, right) for one track.

    Tracks with audio output use output_meter_left/right. Tracks without it (a
    MIDI track with no instrument) raise on those, so they report
    output_meter_level on both sides.
    """
    if has_audio_output:
        try:
            return round_level(track.output_meter_left), round_level(track.output_meter_right)
        except Exception:
            pass
    level = round_level(safe_get(track, "output_meter_level", 0.0))
    return level, level


def select_ids(strip_ids, selected_id, main_id, watched_ids, known, limit=MAX_ENTRIES):
    """Ids to meter, in priority order (strips, selected, main, watched), unique, known, at most `limit`."""
    chosen = []
    seen = set()
    candidates = list(strip_ids) + [selected_id, main_id] + list(watched_ids)
    for tid in candidates:
        if tid is None or tid in seen or tid not in known:
            continue
        seen.add(tid)
        chosen.append(tid)
        if len(chosen) >= limit:
            break
    return chosen


class MeterFrameBuilder(object):
    """Builds `m` entries and remembers the previous frame's ids for the drop-out zeros."""

    def __init__(self, limit=MAX_ENTRIES):
        self._limit = limit
        self._previous = []

    def reset(self):
        """Forgets the previous frame (new subscription or pause)."""
        self._previous = []

    def build(self, ids, lookup):
        """[[id, left, right], ...] for `ids`, plus one zero entry per id that just dropped out.

        `lookup(id)` returns (track object or None, has_audio_output).
        """
        entries = []
        for tid in ids[: self._limit]:
            track, has_audio_output = lookup(tid)
            if track is None:
                left, right = 0.0, 0.0
            else:
                left, right = read_levels(track, has_audio_output)
            entries.append([tid, left, right])
        current = [entry[0] for entry in entries]
        current_set = set(current)
        for tid in self._previous:
            if len(entries) >= self._limit:
                break
            if tid not in current_set:
                entries.append([tid, 0.0, 0.0])
        self._previous = current
        return entries
