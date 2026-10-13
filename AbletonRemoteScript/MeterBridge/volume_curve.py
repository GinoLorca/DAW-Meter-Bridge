"""The volume curve sent in `hello.vc`. Pure module: no Live import.

101 samples of the main track's volume parameter at x = k/100, with the dB value
parsed from `volume.str_for_value(x)` (None for -inf). The app interpolates in
this table to convert between normalized volume and dB during fader drags.
"""

import math
import re

from .lom import safe_get, volume_parameter
from .protocol import CURVE_POINTS

_NUMBER = re.compile(r"[-+]?\d+(?:[.,]\d+)?")
DB_DECIMALS = 2


def curve_xs():
    """[0.0, 0.01, ..., 1.0]."""
    return [k / 100.0 for k in range(CURVE_POINTS)]


def parse_db(text):
    """dB from Live's volume text ("-6.0 dB", "-inf dB", "6.0 dB"). None for -inf or unparseable text."""
    if text is None:
        return None
    try:
        value = str(text).strip().replace("−", "-")
    except Exception:
        return None
    if "inf" in value.lower():
        return None
    match = _NUMBER.search(value)
    if match is None:
        return None
    try:
        return round(float(match.group(0).replace(",", ".")), DB_DECIMALS)
    except ValueError:
        return None


def approximate_db(x):
    """Approximation of Live's fader (0.85 = 0 dB, 1.0 = +6 dB), matching MeterCore's VolumeCurve.liveApproximation."""
    if x <= 0:
        return None
    if x >= 0.4:
        return round((x - 0.85) / 0.15 * 6, DB_DECIMALS)
    return round(-18 + 52 * math.log10(x / 0.4) / 1.6, DB_DECIMALS)


def approximate_curve():
    """The fallback curve used when Live's own cannot be read."""
    xs = curve_xs()
    return {"x": xs, "db": [approximate_db(x) for x in xs]}


def sample_curve(parameter):
    """(curve dict, problem text or None) from a volume DeviceParameter.

    Falls back to the approximation when fewer than two samples parse to a
    finite dB value.
    """
    method = safe_get(parameter, "str_for_value")
    if not callable(method):
        return approximate_curve(), "the main volume has no str_for_value(); using an approximate curve"
    xs = curve_xs()
    dbs = []
    for x in xs:
        try:
            dbs.append(parse_db(method(x)))
        except Exception:
            dbs.append(None)
    if sum(1 for db in dbs if db is not None) < 2:
        return approximate_curve(), "could not parse the main volume's dB text; using an approximate curve"
    return {"x": xs, "db": dbs}, None


def sample_song_curve(song):
    """(curve dict, problem or None) from the main track's volume."""
    return sample_curve(volume_parameter(safe_get(song, "master_track")))
