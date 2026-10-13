"""Rate-limited logging into Live's Log.txt. Pure module: no Live import."""

import time
import traceback

#: A given key is logged at most once per this many seconds.
DEFAULT_INTERVAL = 10.0


class RateLimitedLog(object):
    """Writes through `sink` (ControlSurface.log_message inside Live).

    `info` always writes. `limited` writes a key at most once per interval and
    reports how many messages for that key it held back in between, so a fault
    that repeats every timer tick cannot flood Log.txt.
    """

    def __init__(self, sink, clock=time.monotonic, interval=DEFAULT_INTERVAL, prefix=""):
        self._sink = sink
        self._clock = clock
        self._interval = interval
        self._prefix = prefix
        self._last = {}
        self._suppressed = {}

    def info(self, message):
        """Writes `message` unconditionally."""
        self._write(message)

    def limited(self, key, message):
        """Writes `message` unless `key` was written less than an interval ago. Returns True if written."""
        now = self._clock()
        last = self._last.get(key)
        if last is not None and now - last < self._interval:
            self._suppressed[key] = self._suppressed.get(key, 0) + 1
            return False
        held_back = self._suppressed.pop(key, 0)
        self._last[key] = now
        if held_back:
            message = "%s (%d similar messages held back)" % (message, held_back)
        self._write(message)
        return True

    def exception(self, key, message):
        """Like `limited`, with the current exception's traceback appended."""
        return self.limited(key, "%s: %s" % (message, short_traceback()))

    def _write(self, message):
        try:
            self._sink(self._prefix + message)
        except Exception:
            pass


def short_traceback(max_lines=8):
    """The current exception's traceback on one line, newest frames last."""
    try:
        lines = [line.strip() for line in traceback.format_exc().splitlines() if line.strip()]
    except Exception:
        return "(no traceback)"
    if len(lines) > max_lines:
        lines = lines[-max_lines:]
    return " | ".join(lines)
