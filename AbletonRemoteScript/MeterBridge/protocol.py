"""Wire protocol v1 between this script and the app (docs/PROTOCOL.md).

Encoding, decoding and message builders. Pure module: no Live import.
"""

import json
import math

PROTOCOL_VERSION = 1
SCRIPT_VERSION = "0.1.0"

#: Sockets bind and send on loopback only.
HOST = "127.0.0.1"
#: The app listens here unless its `sub` names another port.
APP_PORT = 47800
#: This script listens here.
SCRIPT_PORT = 47801

#: Every datagram must fit in this many bytes (macOS caps UDP at 9216).
MAX_DATAGRAM_BYTES = 8192
#: At most this many items in one `tracks` part.
MAX_TRACKS_PER_PART = 32
#: Track names are cut to this many characters so one record always fits a datagram
#: (6 bytes per character worst case, for JSON-escaped control characters).
MAX_NAME_CHARS = 1000
#: Cap for free text such as `err.msg` and `surfaces.warn`.
MAX_TEXT_CHARS = 500

DEFAULT_HZ = 30
MIN_HZ = 1
MAX_HZ = 60

#: Number of samples in the `hello.vc` volume curve (x = k/100).
CURVE_POINTS = 101


def encode(message):
    """Compact UTF-8 JSON bytes for one message dict."""
    text = json.dumps(message, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    return text.encode("utf-8", "replace")


def decode(data):
    """Parses one datagram. Returns (message dict, None) or (None, reason).

    Datagrams over MAX_DATAGRAM_BYTES are dropped unread (docs/PROTOCOL.md).
    """
    try:
        too_large = len(data) > MAX_DATAGRAM_BYTES
    except TypeError:
        return None, "datagram is not bytes"
    if too_large:
        return None, "datagram is larger than %d bytes" % MAX_DATAGRAM_BYTES
    try:
        text = data.decode("utf-8")
    except (UnicodeDecodeError, AttributeError):
        return None, "datagram is not UTF-8"
    try:
        message = json.loads(text)
    except (ValueError, RecursionError):
        return None, "datagram is not JSON"
    if not isinstance(message, dict):
        return None, "datagram is not a JSON object"
    return message, None


def is_int(value):
    """True for JSON integers (bool is excluded, although it is an int in Python)."""
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    """True for finite JSON numbers (bool excluded)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except (OverflowError, ValueError):
        # A JSON integer too large for a float.
        return False


def finite_or(value, default):
    """`value` as a float when it is a finite number, else `default`."""
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(number):
        return default
    return number


def clip_text(value, limit):
    """`value` as text, at most `limit` characters."""
    if value is None:
        return ""
    try:
        text = value if isinstance(value, str) else str(value)
    except Exception:
        return ""
    if len(text) > limit:
        return text[:limit]
    return text


def clamp_hz(value, max_hz=MAX_HZ):
    """Meter rate from a `sub` message, clamped to MIN_HZ..max_hz; DEFAULT_HZ when absent."""
    if not is_number(value):
        return min(DEFAULT_HZ, max_hz)
    return int(max(MIN_HZ, min(max_hz, int(round(value)))))


def valid_port(value, default=APP_PORT):
    """UDP port from a message, or `default` when it is missing or out of range."""
    if is_int(value) and 0 < value < 65536:
        return value
    return default


def header(message_type):
    """The common fields every message starts with."""
    return {"v": PROTOCOL_VERSION, "t": message_type}


def hello(session, live_version, hz, curve):
    """`hello`: sent first on every new subscription."""
    message = header("hello")
    message["script"] = SCRIPT_VERSION
    message["live"] = clip_text(live_version, 32)
    message["session"] = session
    message["hz"] = hz
    message["vc"] = curve
    return message


def tracks_message(gen, part, parts, total, items):
    """One part of a full `tracks` list."""
    message = header("tracks")
    message["gen"] = gen
    message["part"] = part
    message["parts"] = parts
    message["total"] = total
    message["items"] = items
    return message


def tracks_parts(gen, records, max_bytes=MAX_DATAGRAM_BYTES, max_items=MAX_TRACKS_PER_PART):
    """Splits the full ordered track list into `tracks` messages.

    Every part holds at most `max_items` records and encodes to at most `max_bytes`.
    The header is sized with the widest possible part/parts numbers, so the real
    messages can only be smaller than the estimate.
    """
    total = len(records)
    widest = max(total, 1)
    overhead = len(encode(tracks_message(gen, widest, widest, total, [])))
    groups = []
    current = []
    size = overhead
    for record in records:
        item_size = len(encode(record))
        extra = item_size + (1 if current else 0)
        if current and (len(current) >= max_items or size + extra > max_bytes):
            groups.append(current)
            current = []
            size = overhead
            extra = item_size
        current.append(record)
        size += extra
    if current or not groups:
        groups.append(current)
    parts = len(groups)
    return [tracks_message(gen, index, parts, total, group) for index, group in enumerate(groups)]


def track(gen, record):
    """`track`: one complete track record that changed."""
    message = header("track")
    message["gen"] = gen
    message["item"] = record
    return message


def selection(track_id):
    """`sel`: the selected track's id, or None when it is not in the list."""
    message = header("sel")
    message["id"] = track_id
    return message


def surfaces(units, warn):
    """`surfaces`: Mackie units in physical order, plus an optional warning."""
    message = header("surfaces")
    message["units"] = units
    message["warn"] = clip_text(warn, MAX_TEXT_CHARS) if warn else None
    return message


def meters(seq, entries):
    """`m`: [[id, left, right], ...]."""
    message = header("m")
    message["seq"] = seq
    message["d"] = entries
    return message


def heartbeat(seq):
    """`hb`: sent every second while subscribed."""
    message = header("hb")
    message["seq"] = seq
    return message


def error(text):
    """`err`: a diagnostic for the app."""
    message = header("err")
    message["msg"] = clip_text(text, MAX_TEXT_CHARS)
    return message
