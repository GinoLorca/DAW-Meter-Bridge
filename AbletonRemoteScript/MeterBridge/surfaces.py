"""Which track each Mackie hardware strip shows. Pure module: no Live import.

Reads Ableton's own MackieControl / MackieControlXT script instances from Live's
control-surface slots and asks each of their strips for `assigned_track()`.
MackieControl keeps its 8 strips in a private, name-mangled attribute, which a
Live update could rename. When that happens the unit is still reported, with
all-empty strips and a warning, and nothing raises.

This script must never subclass MackieControlXT: MackieControl would then claim
it as an extension and change the bank size.
"""

from .lom import safe_get, track_id

MAIN_CLASS = "MackieControl"
XT_CLASS = "MackieControlXT"
ROLE_MAIN = "main"
ROLE_XT = "xt"
STRIPS_PER_UNIT = 8

#: MackieControl's own 8 strips (Live 11.3 and 12.4).
MAIN_STRIPS_ATTRIBUTE = "_MackieControl__channel_strips"
#: MackieControlXT's strips, used when its public channel_strips() is missing.
XT_STRIPS_ATTRIBUTE = "_MackieControlXT__channel_strips"


def mackie_role(script):
    """"main", "xt" or None, from the class name or a base class name (so forks still count)."""
    try:
        names = [cls.__name__ for cls in type(script).__mro__]
    except Exception:
        return None
    if XT_CLASS in names:
        return ROLE_XT
    if MAIN_CLASS in names:
        return ROLE_MAIN
    return None


def script_name(script):
    """Class name of a script instance."""
    try:
        return type(script).__name__
    except Exception:
        return "?"


def unit_strip_objects(script, role):
    """(list of strip objects, problem text or None)."""
    if role == ROLE_MAIN:
        strips = safe_get(script, MAIN_STRIPS_ATTRIBUTE)
        if strips is None:
            return None, "private attribute %s is missing (renamed in this Live version?)" % MAIN_STRIPS_ATTRIBUTE
    else:
        strips = None
        method = safe_get(script, "channel_strips")
        if callable(method):
            try:
                strips = method()
            except Exception as exc:
                return None, "channel_strips() failed: %s" % exc
        if strips is None:
            strips = safe_get(script, XT_STRIPS_ATTRIBUTE)
        if strips is None:
            return None, "channel_strips() is missing (renamed in this Live version?)"
    try:
        return list(strips), None
    except Exception as exc:
        return None, "its strip list is unreadable: %s" % exc


def assigned_ids(strips, id_of=track_id):
    """([track id or None per strip], problem text or None)."""
    ids = []
    for strip in strips:
        method = safe_get(strip, "assigned_track")
        if not callable(method):
            return None, "its strips have no assigned_track() (renamed in this Live version?)"
        try:
            track = method()
        except Exception as exc:
            return None, "assigned_track() failed: %s" % exc
        ids.append(None if track is None else id_of(track))
    return ids, None


def physical_order(entries):
    """Units in physical left-to-right order, following MackieControl's rule.

    XTs in slots before the main unit are left extensions, XTs in later slots are
    right extensions, and each side keeps its slot order. Without a main unit the
    XTs stay in slot order.
    """
    ordered = sorted(entries, key=lambda entry: entry["slot"])
    mains = [entry for entry in ordered if entry["role"] == ROLE_MAIN]
    if not mains:
        return ordered
    main = mains[0]
    left = [entry for entry in ordered if entry is not main and entry["slot"] < main["slot"]]
    right = [entry for entry in ordered if entry is not main and entry["slot"] > main["slot"]]
    return left + [main] + right


def read_surfaces(control_surfaces, id_of=track_id):
    """Reads every Mackie unit in Live's control-surface slots.

    `control_surfaces` is `Live.Application.get_application().control_surfaces`:
    one entry per slot, None for empty slots. Returns (units, warn), where units
    are protocol dicts {"slot", "script", "role", "strips"} in physical order and
    warn is None or a human-readable string.
    """
    problems = []
    try:
        scripts = list(control_surfaces or [])
    except Exception as exc:
        return [], "could not read Live's control surface list: %s" % exc
    entries = []
    for index, script in enumerate(scripts):
        if script is None:
            continue
        role = mackie_role(script)
        if role is None:
            continue
        name = script_name(script)
        slot = index + 1
        strips, problem = unit_strip_objects(script, role)
        ids = None
        if problem is None:
            ids, problem = assigned_ids(strips, id_of)
        if problem is not None:
            problems.append("%s in slot %d: %s; its strips are shown empty" % (name, slot, problem))
            ids = [None] * STRIPS_PER_UNIT
        entries.append({"slot": slot, "script": name, "role": role, "strips": ids})
    mains = [entry["slot"] for entry in entries if entry["role"] == ROLE_MAIN]
    if len(mains) > 1:
        problems.append(
            "%d MackieControl units are configured (slots %s); they compete for the same XT units, "
            "so use one surface's Mackie setup at a time" % (len(mains), ", ".join(str(slot) for slot in mains))
        )
    warn = "; ".join(problems) if problems else None
    return physical_order(entries), warn


def strip_track_ids(units):
    """Every non-empty strip's track id across `units`, left to right."""
    return [tid for unit in units for tid in unit["strips"] if tid is not None]
