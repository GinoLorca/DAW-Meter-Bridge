# MeterBridge Remote Script for Ableton Live

`MeterBridge` is a Python MIDI Remote Script that runs inside Ableton Live 11 (Python 3.7) and Live 12 (Python 3.11). It sends track state and meters to the DAW Meter Bridge app over UDP on `127.0.0.1`, applies the app's select, mute, solo, arm and volume commands, and reports which track each MackieControl hardware strip (SSL UF8, Behringer WING) is showing. The wire format is specified in [`docs/PROTOCOL.md`](../docs/PROTOCOL.md).

## Install

1. Copy the `MeterBridge` folder into Live's User Library:

   ```bash
   scripts/install-live-script.sh
   ```

   This copies `AbletonRemoteScript/MeterBridge` to `~/Music/Ableton/User Library/Remote Scripts/MeterBridge` and leaves out `__pycache__`. To do it by hand, copy the folder to that location yourself.

2. Quit and restart Live. Live only scans Remote Scripts at startup.
3. Open **Settings > Link, Tempo & MIDI**. In a free **Control Surface** slot, choose **MeterBridge**. Set its **Input** and **Output** to **None**. The script needs no MIDI ports.
4. Start DAW Meter Bridge and choose **Source > Ableton Live**.

Live has 7 Control Surface slots. If they are all taken, free one first.

### Leftover MackieControlXT slots change the UF8 bank step

Ableton's MackieControl script claims **every** `MackieControlXT` in **any** slot as an extension, even one with no MIDI ports. Each XT adds 8 strips to the bank. With the UF8's MackieControl in slot 1 and three leftover XTs in slots 4–6 (from a WING setup), the UF8 banks by 32 tracks instead of 8. Remove the leftover XT entries if you want the UF8 to bank by 8. This also frees slots for MeterBridge. The bridge always follows what the hardware actually shows, so it stays aligned either way.

The UF8 and the WING Mackie setups should not be enabled in Live at the same time. Two MackieControl units compete for the same XTs. MeterBridge reports this as a warning.

## How it works

- **Timer.** A `Live.Base.Timer` fires every 16 ms on Live's main thread. Each tick is wrapped in `try/except`, so an error is logged and never stops the timer or breaks Live. If the timer is missing, the script falls back to Live's 100 ms `update_display` and meters at 10 Hz.
- **Idle until subscribed.** The script only reads its UDP socket until the app sends `sub`. Without a `sub` for 5 s, it stops sending meters and updates. A `sub` with a new `app` value (the app restarted its Live source) gets the full state again at once.
- **Track state.** The script polls the ordered track list about 10 times a second (`song.visible_tracks`, then return tracks, then the main track) and sends only what changed. It doesn't use per-track listeners. Track ids are `track._live_ptr`. The track poll and the bank-follow poll run half a period apart, so one tick never does both. A track poll slower than 2 ms is logged (at most once every 10 s) with the track count.
- **Meters.** At the rate the app asks for (default 30 Hz, at most 60 Hz), the script reads `output_meter_left/right`, or `output_meter_level` for tracks without audio output. It meters the tracks on surface strips, the selected track, the main track and the app's watch list, up to 64 of them.
- **Bank follow.** Every 100 ms the script asks each `MackieControl`/`MackieControlXT` strip for `assigned_track()`. MackieControl keeps its strips in a private attribute (`_MackieControl__channel_strips`). If a Live update renames it, the unit is still reported, with empty strips, and the `surfaces.warn` message says why. Nothing crashes.
- **Commands.** Commands are queued on arrival and applied in the next tick, never from a listener. If Live refuses a change during undo/redo, the script retries it on the next tick, up to 3 times. Exclusive solo and arm follow Live's preferences (`song.exclusive_solo`, `song.exclusive_arm`) unless the app asks for exclusive or additive explicitly. A volume drag is wrapped in `begin_gesture()`/`end_gesture()` and one undo step, like a mouse drag on Live's fader. It ends on the app's `"end": true`, after 0.5 s without a `vol`, before any other command, or when the subscription ends.
- **Logging.** Messages go to Live's `Log.txt` (`~/Library/Preferences/Ableton/Live <version>/Log.txt`) with the prefix `(MeterBridgeSurface)`. A repeating error is logged at most once every 10 s.

## Files

| File | Role |
|---|---|
| `MeterBridge/__init__.py` | `create_instance(c_instance)`, which Live calls |
| `MeterBridge/live_surface.py` | The only module that imports Live: a `_Framework` ControlSurface that owns the timer |
| `MeterBridge/bridge.py` | The protocol state machine; one `tick()` per timer callback |
| `MeterBridge/protocol.py` | Constants, compact JSON, message builders, `tracks` chunking (≤ 8192 bytes, ≤ 32 items) |
| `MeterBridge/transport.py` | Non-blocking UDP bound to `127.0.0.1:47801` |
| `MeterBridge/tracks.py`, `lom.py` | Track snapshots and diffs; defensive Live Object Model access |
| `MeterBridge/surfaces.py` | MackieControl introspection and physical unit order |
| `MeterBridge/commands.py` | Command parsing, queue, solo exclusivity, retries |
| `MeterBridge/meters.py` | Meter selection, rounding, drop-out frames |
| `MeterBridge/subscription.py` | `sub` keep-alive and 5 s timeout, `watch` list |
| `MeterBridge/volume_curve.py` | The 101-point `hello.vc` curve from `str_for_value` |
| `MeterBridge/log.py` | Rate-limited logging |
| `tools/fake_live.py` | Fake Live harness (see below) |
| `tools/make_calibration_tone.py` | Writes the meter-calibration test tone: a 997 Hz sine at 19 known levels |
| `tools/capture_meters.py` | Stands in for the app, records a track's meter while the tone plays, and prints the dB table |
| `tests/` | Unit and end-to-end tests |

To measure how Live's meter values map to dBFS, see [docs/research/05-live-meter-calibration.md](../docs/research/05-live-meter-calibration.md). Live 12 is already measured and built into the app.

Only Python 3.7 syntax and stdlib are allowed: no walrus, no `match`, no positional-only parameters, no annotations. A test enforces this.

## Test without Live

Run the tests from the repository root:

```bash
python3 -m unittest discover -s AbletonRemoteScript/tests
```

Or from this folder:

```bash
cd AbletonRemoteScript && python3 -m unittest
```

`tools/fake_live.py` runs the **real** script against a fake Live, with real UDP on `127.0.0.1:47801`, so the app's Live source can be tested end to end:

```bash
python3 AbletonRemoteScript/tools/fake_live.py --tracks 24 --xts 0 --bank-step-seconds 0 --duration 0
```

| Option | Meaning |
|---|---|
| `--tracks N` | Number of tracks (default 24). Two returns and the main track are always added. |
| `--xts N` / `--left-xts N` | MackieControlXT units right / left of the main unit. |
| `--bank-step-seconds S` | Bank the surface every S seconds (0 = never). |
| `--duration S` | Stop after S seconds (0 = run until Ctrl-C). |
| `--group`, `--fold-seconds S` | Put the first three tracks in a "Drums" group, and fold/unfold it every S seconds. |
| `--no-exclusive-solo` | Turn Live's Exclusive Solo preference off. |
| `--quiet` | Print only the script's log. |

The harness applies the app's commands to the fake song and prints them. Its meters move like music: kick, snare, hats, pads and vocal phrases. Mute, solo and the fader all affect them. Don't run it while Live has MeterBridge loaded, because both need port 47801. The script logs a bind error and retries every 5 s.
