"""Non-blocking UDP on 127.0.0.1. Pure module: no Live import.

Driven from the Live timer: `receive` drains whatever is waiting and returns at
once, `send` never blocks. No threads.
"""

import errno
import socket

from .protocol import HOST, SCRIPT_PORT

#: Larger buffers absorb a burst (full track list plus meters) without dropping.
SOCKET_BUFFER_BYTES = 256 * 1024
#: Big enough for any datagram macOS will deliver.
RECEIVE_BYTES = 65535

_WOULD_BLOCK = (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINTR)


class UdpTransport(object):
    """One UDP socket bound to `host:port`, used for both directions."""

    def __init__(self, host=HOST, port=SCRIPT_PORT):
        self.host = host
        self.port = port
        #: The port actually bound (differs from `port` when `port` is 0).
        self.bound_port = None
        #: Text of the most recent socket error, for logging.
        self.last_error = None
        self._sock = None

    @property
    def is_open(self):
        """True while the socket is bound."""
        return self._sock is not None

    def open(self):
        """Binds the socket. Returns False (and sets `last_error`) if that fails."""
        if self._sock is not None:
            return True
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setblocking(False)
            for option in (socket.SO_SNDBUF, socket.SO_RCVBUF):
                try:
                    sock.setsockopt(socket.SOL_SOCKET, option, SOCKET_BUFFER_BYTES)
                except (OSError, ValueError):
                    pass
            sock.bind((self.host, self.port))
            self.bound_port = sock.getsockname()[1]
        except (OSError, ValueError) as exc:
            self.last_error = str(exc)
            if sock is not None:
                try:
                    sock.close()
                except OSError:
                    pass
            return False
        self._sock = sock
        self.last_error = None
        return True

    def receive(self, limit=64):
        """Up to `limit` waiting datagrams as [(bytes, (host, port))]. Never blocks."""
        received = []
        if self._sock is None:
            return received
        while len(received) < limit:
            try:
                data, address = self._sock.recvfrom(RECEIVE_BYTES)
            except (BlockingIOError, InterruptedError):
                break
            except OSError as exc:
                if exc.errno not in _WOULD_BLOCK:
                    self.last_error = str(exc)
                break
            received.append((data, address))
        return received

    def send(self, data, port, host=HOST):
        """Sends one datagram. Returns False (and sets `last_error`) if it was not sent."""
        if self._sock is None:
            self.last_error = "socket is not open"
            return False
        try:
            self._sock.sendto(data, (host, port))
        except (BlockingIOError, InterruptedError):
            self.last_error = "send buffer full"
            return False
        except OSError as exc:
            self.last_error = str(exc)
            return False
        return True

    def close(self):
        """Closes the socket. Safe to call more than once."""
        sock = self._sock
        self._sock = None
        self.bound_port = None
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
