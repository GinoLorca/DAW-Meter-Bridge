"""Defensive access to Live Object Model objects. Pure module: no Live import.

Live raises RuntimeError for properties an object does not have (for example
`mute` on the main track, `arm` on a return, `output_meter_left` on a MIDI track
without an instrument). These helpers turn such failures into defaults so a
poll never stops halfway.
"""

KIND_AUDIO = "audio"
KIND_MIDI = "midi"
KIND_GROUP = "group"
KIND_RETURN = "return"
KIND_MAIN = "main"

#: Kinds whose tracks can have an arm button.
ARMABLE_KINDS = (KIND_AUDIO, KIND_MIDI)


def safe_get(obj, name, default=None):
    """getattr that never raises."""
    if obj is None:
        return default
    try:
        return getattr(obj, name)
    except Exception:
        return default


def safe_list(obj, name):
    """A list-valued property as a Python list; empty when missing or unreadable."""
    value = safe_get(obj, name)
    if value is None:
        return []
    try:
        return list(value)
    except Exception:
        return []


def track_id(track):
    """Stable id of a track: Live's `_live_ptr`, falling back to `id(track)`."""
    pointer = safe_get(track, "_live_ptr")
    if isinstance(pointer, int) and not isinstance(pointer, bool):
        return pointer
    return id(track)


def visible_kind(track):
    """Kind of a track from `song.visible_tracks`: group, midi or audio."""
    if safe_get(track, "is_foldable", False):
        return KIND_GROUP
    if safe_get(track, "has_midi_input", False):
        return KIND_MIDI
    return KIND_AUDIO


def ordered_tracks(song):
    """[(track, kind)] in protocol order: visible tracks, return tracks, then the main track."""
    result = [(track, visible_kind(track)) for track in safe_list(song, "visible_tracks")]
    result.extend((track, KIND_RETURN) for track in safe_list(song, "return_tracks"))
    main = safe_get(song, "master_track")
    if main is not None:
        result.append((main, KIND_MAIN))
    return result


def volume_parameter(track):
    """The track's mixer volume DeviceParameter, or None."""
    return safe_get(safe_get(track, "mixer_device"), "volume")


def selected_track(song):
    """`song.view.selected_track`, or None."""
    return safe_get(safe_get(song, "view"), "selected_track")
