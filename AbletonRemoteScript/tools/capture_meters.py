"""Records Live's track meter while the calibration tone plays, and fits a dB table.

Stands in for the app (docs/PROTOCOL.md): binds the app's port, subscribes to the
MeterBridge script, watches one track, and records its `m` values. Quit DAW Meter
Bridge first, because this needs the app's port. Start this, then press Play in Live.

    python3 tools/capture_meters.py --track CAL --out calibration.json
"""

import argparse
import json
import os
import random
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_calibration_tone as tone  # noqa: E402

HOST = "127.0.0.1"
#: Readings are taken from this part of each step, after Live's meter has settled.
SETTLE_SECONDS = 1.0
END_MARGIN_SECONDS = 0.2
#: A frame louder than this marks the start of the first (0 dBFS) step...
ONSET_VALUE = 0.05
#: ...but only after at least this much silence, so a tone already playing is not mistaken for the start.
QUIET_BEFORE_ONSET_SECONDS = 0.5


def find_onset(frames):
    """Time of the first loud frame that follows at least QUIET_BEFORE_ONSET_SECONDS of silence."""
    quiet_since = None
    for t, left, right in frames:
        if max(left, right) > ONSET_VALUE:
            if quiet_since is not None and t - quiet_since >= QUIET_BEFORE_ONSET_SECONDS:
                return t
            quiet_since = None
        elif quiet_since is None:
            quiet_since = t
    return None


def matches(item, names):
    """True when the track's name equals one of `names` (case-insensitive)."""
    return item.get("n", "").strip().lower() in names


def send(sock, port, message):
    sock.sendto(json.dumps(message, separators=(",", ":")).encode("utf-8"), (HOST, port))


def bind(port, wait_seconds):
    """Binds the app's port, waiting up to `wait_seconds` for DAW Meter Bridge to quit."""
    give_up = time.monotonic() + wait_seconds
    announced = False
    while True:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind((HOST, port))
            return sock
        except OSError as error:
            sock.close()
            if time.monotonic() >= give_up:
                sys.exit("cannot bind %s:%d (%s). Quit DAW Meter Bridge first." % (HOST, port, error))
            if not announced:
                print("port %d is in use; waiting for DAW Meter Bridge to quit…" % port)
                announced = True
            time.sleep(0.5)


def capture(track_name, seconds, port, script_port, hz, wait_seconds=0):
    sock = bind(port, wait_seconds)
    sock.settimeout(0.05)
    app_token = random.randint(1, 2 ** 31 - 1)
    info = {"live": None, "track": None, "volume_text": None, "warnings": []}
    parts = {}
    track_id = None
    frames = []
    deadline = None
    next_sub = 0.0
    onset = None
    total = tone.total_seconds() - tone.LEAD_SECONDS + 1.0
    names = [name.strip().lower() for name in track_name.split(",") if name.strip()]

    def adopt(item):
        print("found %r (%s), fader %s" % (item["n"], item["k"], item.get("vs")))
        info["track"] = item["n"]
        info["volume_text"] = item.get("vs")
        send(sock, script_port, {"v": 1, "t": "watch", "ids": [item["id"]]})
        print("recording for up to %d s — press Play in Live now" % seconds)
        return item["id"]

    print("waiting for the MeterBridge script and a track named %s…" % " or ".join(repr(n) for n in names))
    while True:
        now = time.monotonic()
        if now >= next_sub:
            send(sock, script_port, {"v": 1, "t": "sub", "port": port, "hz": hz, "app": app_token})
            if track_id is not None:
                send(sock, script_port, {"v": 1, "t": "watch", "ids": [track_id]})
            next_sub = now + 1.0
        if track_id is not None and deadline is None:
            deadline = now + seconds
        if deadline is not None and now >= deadline:
            break
        if onset is not None and now - onset > total:
            break
        try:
            data, _ = sock.recvfrom(65536)
        except socket.timeout:
            continue
        try:
            message = json.loads(data.decode("utf-8"))
        except ValueError:
            continue
        kind = message.get("t")
        if kind == "hello":
            info["live"] = message.get("live")
            print("connected to Live %s (script %s)" % (message.get("live"), message.get("script")))
        elif kind == "tracks":
            gen = message.get("gen")
            parts.setdefault(gen, {})[message.get("part")] = message.get("items", [])
            if len(parts[gen]) == message.get("parts"):
                items = [item for index in sorted(parts[gen]) for item in parts[gen][index]]
                for item in items:
                    if matches(item, names) and track_id is None:
                        track_id = adopt(item)
        elif kind == "track":
            item = message.get("item", {})
            if track_id is None and matches(item, names):
                track_id = adopt(item)
            elif item.get("id") == track_id:
                info["volume_text"] = item.get("vs")
        elif kind == "m" and track_id is not None:
            for entry in message.get("d", []):
                if entry[0] == track_id:
                    frames.append((now, float(entry[1]), float(entry[2])))
                    if onset is None and max(entry[1], entry[2]) > ONSET_VALUE:
                        onset = find_onset(frames)
                        if onset is not None:
                            print("tone detected; recording %d steps (%.0f s)…" % (len(tone.LEVELS_DB), total))
    sock.close()
    if track_id is None:
        sys.exit("no track named %r was reported by Live" % track_name)
    if info["volume_text"] not in ("0.0 dB", "0 dB"):
        info["warnings"].append("track fader was %s, not 0.0 dB" % info["volume_text"])
    return info, frames


def median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def analyse(frames):
    onset = find_onset(frames)
    if onset is None:
        raise ValueError("no tone start found after silence; start the capture, then press Play from the beginning")
    steps = []
    for start, end, level in tone.schedule():
        window = [f for f in frames
                  if onset + start + SETTLE_SECONDS <= f[0] <= onset + end - END_MARGIN_SECONDS]
        if not window:
            raise ValueError("no readings for the %.1f dB step" % level)
        left = [f[1] for f in window]
        right = [f[2] for f in window]
        steps.append({
            "decibels": level,
            "left": median(left),
            "right": median(right),
            "value": median(left + right),
            "spread": max(left + right) - min(left + right),
            "readings": len(window),
        })
    return steps


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--track", default="CAL",
                        help="name of the track playing the tone; several names separated by commas (default CAL)")
    parser.add_argument("--seconds", type=int, default=180, help="give up this many seconds after the track is found (default 180)")
    parser.add_argument("--out", default="calibration.json", help="where to write the results")
    parser.add_argument("--port", type=int, default=47800, help="the app's port (default 47800)")
    parser.add_argument("--script-port", type=int, default=47801, help="the script's port (default 47801)")
    parser.add_argument("--hz", type=int, default=60, help="meter rate to request (default 60)")
    parser.add_argument("--wait-for-port", type=int, default=0, metavar="SECONDS",
                        help="keep retrying the port this long while DAW Meter Bridge still holds it")
    args = parser.parse_args()

    info, frames = capture(args.track, args.seconds, args.port, args.script_port, args.hz, args.wait_for_port)
    result = {"live": info["live"], "track": info["track"], "fader": info["volume_text"],
              "warnings": info["warnings"], "frames": len(frames), "steps": [], "raw": frames}
    try:
        result["steps"] = analyse(frames)
    except ValueError as error:
        result["warnings"].append(str(error))
    with open(args.out, "w") as handle:
        json.dump(result, handle, indent=1)

    for warning in result["warnings"]:
        print("warning: " + warning)
    if result["steps"]:
        print("\n  dBFS    meter    left     right    spread  n")
        for step in result["steps"]:
            print("%6.1f  %.5f  %.5f  %.5f  %.5f  %d" % (
                step["decibels"], step["value"], step["left"], step["right"], step["spread"], step["readings"]))
    print("\nwrote %s (%d meter frames)" % (args.out, len(frames)))


if __name__ == "__main__":
    main()
