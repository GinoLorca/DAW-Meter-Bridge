"""Subscription lifecycle (`sub` keep-alive and `watch`). Pure module: no Live import.

The app sends `sub` every second. A `sub` from a new port, with a new `app`
value (the app restarted its Live source), or the first one after 5 s of
silence, starts a new subscription: the bridge then sends the full state. With
no `sub` for 5 s the subscription ends and meters and deltas stop.
"""

from .protocol import APP_PORT, MAX_HZ, clamp_hz, is_int, valid_port

#: Seconds without a `sub` before the subscription ends.
TIMEOUT_SECONDS = 5.0
#: Watch-list entries kept at most.
MAX_WATCH = 256


class Subscription(object):
    """State of the app's subscription."""

    def __init__(self, timeout=TIMEOUT_SECONDS, max_hz=MAX_HZ):
        self.timeout = timeout
        self.max_hz = max_hz
        #: Port the app listens on, from its latest `sub`.
        self.port = None
        #: Meter rate in use.
        self.hz = clamp_hz(None, max_hz)
        self.active = False
        self.last_sub = None
        #: `app` value of the latest `sub` that carried one; it changes when the app restarts its source.
        self.app = None
        #: Extra track ids to meter, from the latest `watch`.
        self.watch = []

    @property
    def reply_port(self):
        """Where to send: the subscribed port, else the default app port."""
        return self.port if self.port is not None else APP_PORT

    def on_sub(self, message, now):
        """Records a `sub`. Returns True when it starts a new subscription.

        An absent or non-integer `app` never starts one by itself and keeps the stored value.
        """
        port = valid_port(message.get("port"), APP_PORT)
        hz = clamp_hz(message.get("hz"), self.max_hz)
        app = message.get("app")
        app_changed = is_int(app) and app != self.app
        expired = self.last_sub is None or now - self.last_sub >= self.timeout
        is_new = not self.active or expired or port != self.port or app_changed
        if (self.port is not None and port != self.port) or (app_changed and self.app is not None):
            self.watch = []
        self.port = port
        self.hz = hz
        if is_int(app):
            self.app = app
        self.last_sub = now
        self.active = True
        return is_new

    def on_watch(self, message):
        """Replaces the watch list from a `watch` message."""
        ids = message.get("ids")
        if not isinstance(ids, list):
            return
        watch = []
        seen = set()
        for tid in ids:
            if is_int(tid) and tid not in seen:
                seen.add(tid)
                watch.append(tid)
                if len(watch) >= MAX_WATCH:
                    break
        self.watch = watch

    def expire(self, now):
        """Ends the subscription after `timeout` seconds without a `sub`. Returns True when it just ended."""
        if self.active and (self.last_sub is None or now - self.last_sub >= self.timeout):
            self.active = False
            self.watch = []
            return True
        return False
