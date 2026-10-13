# Live ⇄ App wire protocol (v1)

This protocol connects the Ableton Remote Script (`AbletonRemoteScript/MeterBridge`) to the app (`MeterSources.LiveSource`). Both sides must follow this document exactly. Change it here first when the protocol evolves.

## Transport

- **UDP on 127.0.0.1 only.** Never bind `0.0.0.0`.
- **Ports.**
  - The app listens on **47800** for messages from the script.
  - The script listens on **47801** for messages from the app.
  - The script sends to the port named in the app's `sub` message, defaulting to 47800.
- **Framing.** One JSON object per datagram, UTF-8, compact (no extra whitespace).
- **Size.** Every datagram must be **≤ 8192 bytes**. macOS caps UDP datagrams at 9216 bytes (`net.inet.udp.maxdgram`). Senders split large payloads as described below. Receivers drop larger datagrams unread.
- **Common fields.** Every message has `"v": 1` (protocol version) and `"t"` (message type). Receivers ignore unknown fields and unknown types, and drop messages whose `v` differs, with a single logged warning.
- **Not representable in JSON.** `-inf` dB is encoded as `null`.

## Lifecycle

1. The app sends `sub` every **1 s**. This is both the subscription and the keep-alive.
2. When the script receives a `sub` from a new port, with a new `app` value, or after **≥ 5 s** with no `sub`, it treats the subscription as new. It sends `hello`, then the full `tracks` list, then `sel` and `surfaces`. The `app` value changes every time the app (re)starts its Live source, so an app that restarts within 5 s still gets the full state.
3. While subscribed, the script sends `m` (meters) at the requested rate, deltas as state changes, and `hb` every 1 s.
4. If no `sub` arrives for **5 s**, the script stops sending meters and deltas. This keeps Live idle when the app isn't running. Its socket stays open.
5. The app marks the source **disconnected** if it hears nothing (no `m`, `hb` or other message) for **3 s**.
6. When the app sees a `hello` with a new `session` value (the script restarted, or Live reloaded the set), it drops all cached state and waits for the full state that follows.

## Track record

The same object appears in `tracks` and in `track`.

```json
{"id": 140523312345, "i": 3, "n": "Lead Vox", "c": 16725558, "k": "audio",
 "m": false, "s": false, "a": false, "ms": false, "ao": true,
 "vol": 0.85, "vs": "0.0 dB"}
```

| Key | Type | Meaning |
|---|---|---|
| `id` | int | Stable track id: Live's `track._live_ptr`. |
| `i` | int | Position in the ordered list: visible tracks, then return tracks, then the main track. |
| `n` | string | Track name. |
| `c` | int or null | Colour as `0xRRGGBB`. |
| `k` | string | `"audio"`, `"midi"`, `"group"`, `"return"` or `"main"`. |
| `m` | bool | Muted. Always `false` for the main track, which has no mute. |
| `s` | bool | Soloed. Always `false` for the main track. |
| `a` | bool or null | Armed. `null` when the track can't be armed (group, return, main). |
| `ms` | bool | Muted via another track's solo (`muted_via_solo`). |
| `ao` | bool | Has audio output (`has_audio_output`). |
| `vol` | float | Mixer volume, normalized 0..1 (`mixer_device.volume.value`). |
| `vs` | string | Volume as Live displays it (`str(volume)`), e.g. `"-6.0 dB"`. |

Tracks folded inside a collapsed group are **not** in the list. This matches `song.visible_tracks`, which is also what Mackie banking uses.

## Script → app messages

### `hello`
```json
{"v":1,"t":"hello","script":"0.1.0","live":"12.4.6","session":918273,"hz":30,
 "vc":{"x":[0.0,0.01,...,1.0],"db":[null,-70.0,...,6.0]}}
```
- `session`: random int chosen when the script instance is created.
- `hz`: the meter rate the script will actually use.
- `vc`: the **volume curve**. It has 101 samples, `x = k/100` for `k = 0..100`. `db` holds the result of parsing `volume.str_for_value(x)` (`null` for `-inf`). The app interpolates in this table to convert between normalized volume and dB during fader drags. Sample it from the main track's volume parameter.

### `tracks`: full ordered track list, chunked
```json
{"v":1,"t":"tracks","gen":12,"part":0,"parts":2,"total":40,"items":[<track>, ...]}
```
- `gen` increases on every full-list send.
- Items are split into parts so each datagram stays ≤ 8192 bytes. At most 32 items per part, fewer if the names are long.
- The app replaces its list once **all** parts of a `gen` have arrived. Incomplete generations are discarded after 1 s, or when a newer `gen` starts.
- The script sends a full list after subscribing and whenever the set of visible tracks, return tracks or their order changes, including folding or unfolding a group.

### `track`: one track changed
```json
{"v":1,"t":"track","gen":12,"item":<track>}
```
The record is complete, not a diff. The script coalesces changes and sends at most one `track` per track per timer tick. The app ignores a `track` whose id isn't in its current list.

### `sel`: selected track
```json
{"v":1,"t":"sel","id":140523312345}
```
`id` is `null` when the selected track isn't in the list, for example inside a folded group.

### `surfaces`: what each hardware strip shows
```json
{"v":1,"t":"surfaces","units":[
  {"slot":1,"script":"MackieControl","role":"main","strips":[id,id,id,id,id,id,id,null]},
  {"slot":4,"script":"MackieControlXT","role":"xt","strips":[...8 ids or null...]}
],"warn":null}
```
- `units` covers every `MackieControl` / `MackieControlXT` instance in Live's control-surface slots, in **physical left-to-right order**. Live's MackieControl rule decides that order: XTs in slots before the main unit are left extensions, XTs in later slots are right extensions, and each side keeps its slot order.
- `slot` is 1-based.
- `strips[k]` is the id of `strip.assigned_track()` for the unit's k-th strip, or `null` if the strip is empty.
- The script polls about every 100 ms and sends only when something changed. It also sends after subscribing.
- `warn` is a human-readable string when introspection partly failed, e.g. a private attribute was renamed in a newer Live. When that happens the unit is still listed, with all-`null` strips.
- An empty `units` list means no Mackie surfaces are configured.

### `m`: meters
```json
{"v":1,"t":"m","seq":5531,"d":[[140523312345,0.6123,0.5871],[140523319999,0.0,0.0]]}
```
- **Rate:** about `hz` times per second (the default 30).
- **Values:** Live's own normalized meter scale, 0..1, from `output_meter_left` / `output_meter_right`, rounded to 4 decimals. In Live 12 this scale is linear in dB: `value = (dBFS + 70) / 76`, measured in [research/05-live-meter-calibration.md](research/05-live-meter-calibration.md).
  - For a track without audio output, both values are `output_meter_level`.
  - The app draws meter height directly from these values, so the bridge matches Live's meters. The dB readout and the clip LED threshold go through the app's `MeterCalibration`.
- **Which tracks are included:** the union of
  - every track on any surface strip,
  - the selected track,
  - the main track,
  - the app's current `watch` list.

  At most 64 entries. A track that just went silent is still sent with zeros for one more frame, so the app can drop it.
- `seq` increases by one per message. The app ignores a message whose `seq` is older than one it has already applied, unless the `session` changed.

### `hb`: heartbeat
```json
{"v":1,"t":"hb","seq":77}
```
Sent every 1 s while subscribed.

### `err`: diagnostic
```json
{"v":1,"t":"err","msg":"unknown track id 123 in cmd"}
```

## App → script messages

### `sub`: subscribe and keep alive (every 1 s)
```json
{"v":1,"t":"sub","port":47800,"hz":30,"app":1730591}
```
- `app` (optional int): a random value the app picks each time it starts its Live source. It stays the same in every `sub` until the source stops. A `sub` whose `app` differs from the previous one starts a new subscription even within 5 s on the same port (see Lifecycle). Absent means "unknown" and never starts a new subscription by itself.

### `watch`: extra tracks to meter
```json
{"v":1,"t":"watch","ids":[140523312345,140523319999]}
```
Lists tracks the app shows through `trackList` bindings that aren't on a surface. It replaces the previous list. The app re-sends it whenever it changes, and with every 5th `sub`.

### `cmd`: change something in Live
```json
{"v":1,"t":"cmd","op":"select","id":140523312345}
{"v":1,"t":"cmd","op":"mute","id":140523312345,"on":true}
{"v":1,"t":"cmd","op":"solo","id":140523312345,"on":true,"excl":null}
{"v":1,"t":"cmd","op":"arm","id":140523312345,"on":true,"excl":null}
{"v":1,"t":"cmd","op":"vol","id":140523312345,"val":0.8123}
{"v":1,"t":"cmd","op":"vol","id":140523312345,"val":0.8001,"end":true}
```

- **Main-thread rule.** The script applies commands on Live's main thread from its timer callback, never from inside a listener callback, because Live raises "Changes cannot be triggered by notifications".
- **Retries.** If Live is in undo/redo and refuses the change, the script retries on the next tick, at most 3 times.
- **`solo` exclusivity:**
  - `excl: true` unsolos every other track and return track first.
  - `excl: false` is additive.
  - `excl: null` follows Live's "Exclusive Solo" preference (`song.exclusive_solo`). Setting `track.solo` directly bypasses that preference, so the script implements it.
  - The app sends `null` for a plain click and `false` for ⌘-click.
- **`arm` exclusivity:** the same as solo, with Live's "Exclusive Arm" preference (`song.exclusive_arm`).
  - `excl: true` disarms every other armable track first (including tracks in folded groups).
  - `excl: false` is additive. `excl: null` (or absent) follows `song.exclusive_arm`. Setting `track.arm` directly bypasses that preference, so the script implements it, as Ableton's MackieControl does.
  - Disarming (`on: false`) never touches other tracks. The app currently omits `excl` (the same as `null`), so arming follows Live's preference.
- **`vol`:** `val` is clamped to the parameter's min/max.
  - A drag on the bridge sends a stream of `vol` for one track (about 30 per second at most) and sends its final value, when the mouse is released, with `"end": true` (optional, default false). That final message may follow the previous one immediately.
  - The script treats the stream as one gesture, like a mouse drag on Live's fader: before the first write that changes the value it calls `parameter.begin_gesture()` and, when no other gesture is open, `song.begin_undo_step()`. It closes the gesture (`end_gesture()`, then `end_undo_step()` when the last gesture closes) when a `vol` with `end: true` is applied, when no `vol` for that track arrived for **0.5 s**, before any other command is applied, and when the subscription ends or the script closes. Begin and end calls always stay balanced.
- **Ops on the main track:** `mute` and `solo` don't apply, and the script ignores them with an `err`. `arm` is ignored for tracks that can't be armed.
- **Echo:** the result comes back through the normal `track` / `sel` deltas. There is no separate ack.

## Example session

```
app → script  {"v":1,"t":"sub","port":47800,"hz":30,"app":1730591}
script → app  {"v":1,"t":"hello",...}
script → app  {"v":1,"t":"tracks","gen":1,"part":0,"parts":1,"total":12,"items":[...]}
script → app  {"v":1,"t":"sel","id":...}
script → app  {"v":1,"t":"surfaces","units":[{"slot":1,"script":"MackieControl","role":"main","strips":[...]}],"warn":null}
script → app  {"v":1,"t":"m","seq":1,"d":[...]}          (~30/s)
app → script  {"v":1,"t":"cmd","op":"solo","id":...,"on":true,"excl":null}
script → app  {"v":1,"t":"track","gen":1,"item":{... "s":true ...}}
```
