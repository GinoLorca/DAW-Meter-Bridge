# Ableton Live (11/12) research for the Mac meter bridge

## Bottom line
- **Use one custom Python MIDI Remote Script** placed in `~/Music/Ableton/User Library/Remote Scripts/`. It can do the whole Live side:
  - **Meters:** poll `output_meter_left/right` (or `output_meter_level` on MIDI-only tracks) with a `Live.Base.Timer` running at about 30 Hz. Push the values over a localhost UDP socket.
  - **Mix state:** read and set mute, solo, arm, selection, volume, names and colours through the Live Object Model (LOM).
  - **Bank follow:** look inside the MackieControl / MackieControlXT script instances that the UF8 and the Wing use. Read each hardware strip's `assigned_track()`.
- **Biggest unknown:** how the 0..1 meter value maps to dBFS. It is not documented, so it has to be calibrated (see §1.4).
- **Biggest fragility:** bank follow reads private, name-mangled attributes of Ableton's MackieControl script. They exist in both installed builds (11.3.42 and 12.4.6), but Ableton could rename them in any update.

---

## 1. Live MIDI Remote Scripts

### 1.1 Install, enable, slots, Python version
- **Install location:** `Macintosh HD/Users/<user>/Music/Ableton/User Library/Remote Scripts/<ScriptName>/__init__.py`. This location has worked since Live 10.1.13 and survives Live upgrades. Restart Live, then choose the script in Settings > Link, Tempo & MIDI > Control Surface ([Ableton KB 209072009](https://help.ableton.com/hc/en-us/articles/209072009); [AbletonOSC README](https://github.com/ideoforms/AbletonOSC)). Live 11 and later require Python 3 scripts.
- **No MIDI port is needed.** On this Mac, Live 12.4.5's `Log.txt` lists `MidiRemoteScript 3 [Control Surface="AbletonMCP" Input="None" Output="None"]`, and that script runs a TCP server. AbletonOSC also has you pick only the script, no ports.
- **Number of slots: 7.** The local logs show `MidiRemoteScript 1..7` in both Live 11.3.42 and Live 12.4.5 (`~/Library/Preferences/Ableton/Live 12.4.5/Log.txt`). The Live 12 manual text still says "up to six" ([manual](https://www.ableton.com/en/manual/midi-and-key-remote-control/)), which looks out of date.
- **All 7 slots are currently in use on this Mac:**

  | Slot | Script | Ports |
  |---|---|---|
  | 1 | MackieControl | SSL V-MIDI Port 1 |
  | 2 | SL_MkIII | none |
  | 3 | AbletonMCP | none |
  | 4–6 | MackieControlXT | none |
  | 7 | Launchkey_Mini_MK3 | none |

  One slot has to be freed for the bridge script.
- **Python version, checked from the `.pyc` magic numbers of the installed builds:**
  - Live 11.3.42 = magic 3394 = **Python 3.7**
  - Live 12.4.6 = magic 3495 = **Python 3.11**
  - To support both, write 3.7-compatible syntax: no walrus operator, no `match`. Live compiles `.py` files in the User Library itself.
  - Third-party confirmation: [Maus3rVonDutch/ableton-ssl-uf8-scripts](https://github.com/Maus3rVonDutch/ableton-ssl-uf8-scripts) says Live 12.1+ needs Python 3.11.

### 1.2 Live Object Model properties the bridge needs

| Item | Access | Notes |
|---|---|---|
| `Track.output_meter_left` / `_right` | get, observe | "Smoothed momentary peak value… 0.0 to 1.0. For tracks with audio output only… corresponds to the meters shown in Live… add a significant load to Live GUI" ([legacy LOM, Live 12.1](https://docs.cycling74.com/legacy/max8/vignettes/live_object_model); [current LOM](https://docs.cycling74.com/apiref/lom/track/)). Raises on MIDI tracks without an instrument (`Tracks with MIDI output have no 'output_meter_left' property`, [AbletonOSC #116](https://github.com/ideoforms/AbletonOSC/issues/116)), so check `has_audio_output` first. |
| `Track.output_meter_level` | get, observe | "Hold peak… max of the left and right channels. The hold time is 1 second." Works for MIDI tracks too (as a MIDI meter). The Python docstring says it is measured "behind the mixer_device", i.e. **post-fader** ([Live 11 Python API](https://nsuspray.github.io/Live_API_Doc/11.0.0.xml)). |
| `input_meter_left/right/level` | get, observe | Input meter. MackieControl shows this instead of the output meter when a track is armed. |
| Python listeners | — | `add_output_meter_left_listener` / `_right_` / `_level_listener` all exist ([Live 11 Python API](https://nsuspray.github.io/Live_API_Doc/11.0.0.xml)). |
| `name`, `color` (0x00rrggbb), `color_index`, `mute`, `solo`, `arm`, `muted_via_solo` | get / set / observe | `mute` does not exist on the master track. `arm` does not exist on return or master tracks. |
| `Song.view.selected_track` | get, set, observe | Can be set to any Track object, including returns and master ([LOM](https://docs.cycling74.com/apiref/lom/song_view/)). |
| `Song.visible_tracks` | get, observe | Excludes tracks inside folded groups. MackieControl banks over **this** list. |
| `Song.tracks`, `return_tracks`, `master_track` | get | `exclusive_solo` and `exclusive_arm` are read-only preferences. |
| `mixer_device.volume` (DeviceParameter) | get / set / observe | `value` runs from min to max (0.0–1.0). Third-party sources say about 0.85 ≈ 0 dB and 1.0 ≈ +6 dB (UNVERIFIED). Exact dB text comes from `str_for_value(v)` / `__str__`. Live 12 also has `display_value` ("the value as visible in the GUI"); it is in the [current LOM](https://docs.cycling74.com/apiref/lom/deviceparameter/) and the 12.4.6 binary, but not in the Live 11.0 Python docs. `automation_state` is 0 (none), 1 (active) or 2 (overridden); call `re_enable_automation()` to restore automation. |

### 1.3 Can the script set values? Yes.
- **Mute, solo, arm:** set `track.mute`, `track.solo` or `track.arm` directly.
  - Setting `solo` **bypasses exclusive solo**, so the script must clear the other solos itself when `song.exclusive_solo` is on. MackieControl does exactly this.
- **Selection:** assign `song.view.selected_track = track`.
- **Volume:** set `track.mixer_device.volume.value = v`.
  - Moving a parameter that has automation puts it into the "overridden" state.
- **Converting dB to a fader value:**
  - Build a lookup table at startup by sampling `volume.str_for_value(x)` across 0..1 and parsing the dB text.
  - Invert it with interpolation or binary search.
  - In Live 12, you can try `display_value` instead.
  - Shift fine control is handled entirely in the Mac app.
- **Threading rule:** every LOM write has to run on Live's main thread, and not from inside a listener callback. Doing that raises "Changes cannot be triggered by notifications" ([C74 forum](https://cycling74.com/forums/intermittent-error-changes-cannot-be-triggered-by-notifications)). Queue the commands that arrive over UDP and apply them in the timer callback. The user's installed AbletonMCP script uses this pattern (threads plus `schedule_message(0, …)`).

### 1.4 Meter value → dBFS: UNVERIFIED
- Ableton only says "scaled from 0.0 to 1.0". It does not say whether the scale is linear amplitude or the meter's display curve.
- Community conversions are guesses:
  - `20·log10(v)` treated as linear (several MCP projects, marked "approximate").
  - The LiveControl hack `(10**v − 1)/10` ([Ableton forum](https://forum.ableton.com/viewtopic.php?p=1470247)).
  - One third-party note says about 0.85 = 0 dB, "like faders".
- **Hypothesis to test:** the meter value uses the same curve as the volume fader. If so, `volume.str_for_value(meter_value)` would give dB directly.
- **Calibration procedure:**
  1. Play a sine at known peak levels (0, −6, −12, −18, −24, −40, −60 dBFS) through a track with the fader at 0 dB, using Utility gain steps.
  2. Log `output_meter_left` and `output_meter_level` at each level.
  3. Fit a lookup table, and check it in both Live 11 and Live 12. Live 12 reworked meter ballistics ([Live 12.0 release notes](https://www.ableton.com/en/release-notes/live-12/)).
- **The values are smoothed by Live's meter ballistics.** Peak-hold readouts may slightly under-read true sample peaks (amount UNVERIFIED). Live's meters also show RMS, but the LOM exposes only peak. No clip flag is exposed (UNVERIFIED), so compute clipping in the app.

### 1.5 Update rate
- **`update_display()`:** "Called every 100 ms" ([Live 9 _Framework docstring](https://github.com/gluon/AbletonLive9_RemoteScripts/blob/master/_Framework/ControlSurface.py)). `Defaults.TIMER_DELAY = 0.1`.
- **`schedule_message`:** delays are counted in these same 100 ms ticks.
- **Faster option, `Live.Base.Timer(callback, interval_ms, repeat)`:**
  - Documented in the [Live 11 Python API](https://nsuspray.github.io/Live_API_Doc/11.0.0.xml) as "A timer that will trigger a callback after a certain interval".
  - Ableton's own Push2 script uses it at **16 ms** (`LED_FADE_IN_FREQUENCY = 16`, [Push2/hardware_settings_component.py](https://github.com/gluon/AbletonLive11_MIDIRemoteScripts/blob/main/Push2/hardware_settings_component.py)).
  - ableton-js runs its receive loop with `Live.Base.Timer(callback=…, interval=1, repeat=True)` ([AbletonJS.py](https://github.com/leolabs/ableton-js/blob/master/midi-script/AbletonJS.py)).
- **How often the meter value itself changes is unclear:**
  - ableton-js reports listener events at "20-30 updates per second", and says `output_meter_level` listeners "hang every few 100ms"; `output_meter_left/right` behave better ([ableton-js README](https://cdn.jsdelivr.net/npm/ableton-js@4.1.0/README.md)).
  - The AbletonOSC maintainer says Live only delivers at about 100 ms intervals ([AbletonOSC #69](https://github.com/ideoforms/AbletonOSC/issues/69)).
  - A listener can also leave a stale non-zero value after the transport stops ([#70](https://github.com/ideoforms/AbletonOSC/issues/70)).
  - **Recommendation:** poll in a timer at about 30 Hz rather than relying on listeners. Measure the real number of distinct values per second (UNVERIFIED).

## 2. Getting data out of Live

### 2.1 Sockets work inside Remote Scripts
- **AbletonOSC:** non-blocking UDP, listens on 11000 and replies on 11001. It processes incoming data every 100 ms tick via `schedule_message(1, self.tick)` (source: `manager.py`, `osc_server.py`).
- **ableton-js:** UDP/WebSocket, gzip-chunked. It does use Python threads (the code notes "The send thread only gets scheduled every ~20ms inside Live").
- **On this Mac:** the user's AbletonMCP runs a TCP server on port 9877 with threads inside Live 12.4.5.
- AbletonOSC's comment says threads "beachball" Live. Newer projects use threads successfully, but non-blocking sockets driven by a timer are the safer design.

### 2.2 AbletonOSC as-is
- **Meters:** it exposes `/live/track/get/output_meter_level|left|right`. Because every read-only property also gets `start_listen`, `/live/track/start_listen/output_meter_left <i>` works. Replies arrive on `/live/track/get/output_meter_left <i> <v>`.
- **Selection:** `/live/view/start_listen/selected_track`.
- **Setters:** `/live/track/set/mute|solo|volume`.
- **Not suitable for production use here:**
  - Every listener event is logged at INFO to a file.
  - Replies go only to the last sender's IP address.
  - Track indices cover `song.tracks` only: no return or master tracks (PR #189 still open), and `get_selected_track` breaks when a return or master track is selected.
  - Incoming data is processed only every 100 ms.
  - Meter listener issues #69, #70 and #116.
  - It is MIT-licensed, so its OSC parsing code can be reused.

### 2.3 Recommended data path
- **One custom script, using `Live.Base.Timer` at about 33 ms**, that:
  - (a) reads L/R meters for the tracks on the bridge (up to 24 plus master) and sends one compact UDP datagram per frame to 127.0.0.1;
  - (b) attaches listeners for names, colours, mute, solo, arm, `muted_via_solo`, volume, `visible_tracks` and `selected_track`, and sends only changes;
  - (c) drains incoming commands (select, mute, solo, volume) and applies them on the main thread.
- **Expected latency:** localhost transport is under 1 ms. End-to-end latency is set by Live's meter refresh (about 33–100 ms, UNVERIFIED) plus one display frame.

### 2.4 Faster or true-dBFS alternatives
- **A Max for Live device or AU plugin on each track:**
  - Gives sample-accurate dBFS (e.g. `live.meter~`, whose interval goes down to 10 ms, [docs](https://docs.cycling74.com/reference/live.meter~)).
  - **But devices sit pre-fader in Live's chain**, so the app would have to add the fader's dB (and pan law) to match.
  - Means 24 inserts per session.
  - A plugin would also work in Pro Tools (AAX), which is the cross-DAW argument for it.
- **A single Max for Live device using `live.observer` on many tracks' `output_meter_level`:** this works across tracks ([C74 forum](https://cycling74.com/forums/topic/live-observer-input_meter_level-only-works-for-the-track-the-device-is-in/)). It returns the same 0..1 scale as Python, gains nothing over the script, and must be saved into every Live Set.
- **Live 12 internal meter subscription:** the binary contains `subscribe_to_meters` / `metering_services`, but it belongs to the private Push 3 "flip" protocol (UNVERIFIED as usable; do not rely on it).

## 3. Bank follow (most important part)

### 3.1 How each surface talks to Live
- **SSL UF8 (and UF1 in the same DAW layer):**
  - SSL's Live setup: "From the Control Surface drop-down list select MackieControl. Set the Input to SSL V-MIDI Port 1 Source… Output… Port 1 Destination". Additional UF8s go in slots 2–4 as MackieControl XTs on ports 2–4 ([SSL UF8 User Guide](https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide_Rev1.5.pdf), p. 63).
  - This Mac's SSL 360° config (`~/Library/Application Support/SSL/SSL360/ConfigFiles/SSL360CoreConsoleStorage.cfg`) sets ports 1–4 = `McuAbletonLive` and ports 5–12 = `Hui`.
  - **There is no SSL-specific Live script:**
    - none in Live 12.4.6's `MIDI Remote Scripts` bundle;
    - none in the SSL 360° 2.0.6 app bundle;
    - none in SSL 360 v2.0/v2.1 release coverage.
  - The UF8 LCD meters come from MackieControl, which sends `int(output_meter_level*12)` every 100 ms (12 segments).
- **Behringer Wing (as a DAW controller):**
  - Its USB ports are "MIDI DAW 1 (macOS: WING 1) – Master unit", "DAW 2 (WING 2) – Extender 1", "DAW 3 (WING 3) – Extender 2", "WING 4 – General".
  - For Live: "Select Mackie Control for the first device… WING (Port 1)… select Mackie ControlXT for second and third device… WING (Port 2) & WING (Port 3)" ([WING DAW-CONTROL V1.0](https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf)).
  - Which physical fader section maps to which MCU unit depends on the Wing's SETUP > DAW > CONFIGURATION setting. This has to be set in the bridge app.

### 3.2 MackieControl internals
Sources: decompiled [AbletonLive12_MIDIRemoteScripts/MackieControl](https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/tree/main/MackieControl) and the 11 version. The symbols were checked with `strings` against the installed 11.3.42 and 12.4.6 `.pyc` files.

- **Script-level attributes:**
  - `MackieControl._MackieControl__channel_strips`: the device's own 8 `ChannelStrip` objects.
  - `MackieControl._MackieControl__channel_strip_controller`: the controller that holds the bank state.
  - `MackieControlXT.channel_strips()`: a public method returning the XT's 8 strips.
- **Per-strip API:** `ChannelStrip.assigned_track()` is a **public** method that returns the Live `Track` on that strip, or `None`. The rule is `tracks[strip_index + stack_offset + offset]`, where `tracks` is `song.visible_tracks`, or `song.return_tracks` when "view returns" is on.
- **ChannelStripController bank state:**
  - `_ChannelStripController__bank_cha_offset`, `__bank_cha_offset_returns`, `__view_returns`.
  - `__channel_strips` (all strips including extensions).
  - `assignment_mode()` (public).
  - There is no listener for bank changes.
- **Extensions:** `MackieControl.connect_script_instances` claims **every** `MackieControlXT` instance in **any** slot. XTs in earlier slots become left extensions and XTs in later slots become right extensions. **A bank step equals the total number of strips** ([Live 11 source](https://github.com/gluon/AbletonLive11_MIDIRemoteScripts/blob/main/MackieControl/MackieControl.py)).
- **No session ring:** MackieControl never calls `set_session_highlight`, so there is no red session box to follow.
- **No highlight getter:** the Python API has no session-highlight getter (Live 11 API docs).
- **Session linking doesn't apply:** `_Framework` "session linking" (`SessionComponent._linked_session_instances`) only links `_Framework` SessionComponents, and MackieControl is not one.

### 3.3 Recommended strategy
1. **Find the scripts.** Use `Live.Application.get_application().control_surfaces`, which is indexed by slot and has `None` for empty slots ([Live 11 Python API](https://nsuspray.github.io/Live_API_Doc/11.0.0.xml); [LOM](https://docs.cycling74.com/apiref/lom/application/)). It returns the actual Python script objects; zcx-core reads `cs.zcx_api` from it ([zcx-core](https://github.com/odisfm/zcx-core/blob/main/user_actions/Zcx.py)). `connect_script_instances(instanciated_scripts)` is another hook that receives the same instances. Also add `add_control_surfaces_listener` to notice slot changes.
2. **Read the tracks on each strip.** About 10 times per second, for each instance whose class is `MackieControl` or `MackieControlXT`, get its own 8 strips and call `strip.assigned_track()`. Compare the results to `visible_tracks` + `return_tracks` using object `==` (MackieControl compares tracks the same way). Send `{slot → [track indices]}` whenever it changes.
   - This automatically handles view-returns mode, extensions, tracks being added or deleted, and folded groups.
3. **Map slots to physical devices.** Let the user assign them in the app (e.g. "slot 1 = UF8", "slots 4–6 = Wing"). As an optional automatic hint, the Mac app could parse `~/Library/Preferences/Ableton/Live <ver>/Log.txt`, which lists `MidiRemoteScript N [Control Surface=… Input="SSL V-MIDI Port 1 Source" …]` at startup (format checked locally; it is undocumented).
   - Live 12's binary also contains `control_surface_input_ports` and `set_control_surface_input_port_for_slot`, but whether Python can use them is UNVERIFIED.
4. **Fallbacks, in order:**
   - (a) Compute the tracks from `__bank_cha_offset` / `__view_returns` plus the strip count.
   - (b) Follow the selected track's 8-track bank.
   - (c) In the Mac app, listen to the virtual source "SSL V-MIDI Port 1 Source" for MCU bank/channel button notes (46/47, 48/49). This only gives relative movement and can drift.
   - (d) An MCU proxy: Live talks to the app's virtual ports and the app forwards to SSL 360 and parses the traffic. DAWWAY appears to use virtual MIDI ports ([dawway.co.uk](https://dawway.co.uk/)); this is an inference.

**Fragility:**
- The attributes are private and name-mangled. A Live update could rename them; 12.4.6 already added `_ChannelStrip__assigned_track_index`. Detect them with `getattr` and log clearly when they are missing.
- Python 3.7/3.11 differences don't matter here because nothing is subclassed.
- The bridge script must not subclass MackieControlXT, or MackieControl would claim it as an extension.

### 3.4 Problems in the current setup
- **Bank size is probably 32, not 8 (inferred from code and logs).** The three MackieControlXT scripts in slots 4–6 have no ports, but Live still instantiates them, so they become right extensions of the UF8's MackieControl in slot 1. MackieControl's strip list is then 32 strips, so UF8 bank left/right likely jumps **32 tracks**, and the UF8 shows strips 1–8 of a 32-wide window.
- **UF8 and Wing at the same time conflict.** Running the UF8's MackieControl and the Wing's MackieControl plus 2 XTs together means both MackieControl instances claim all XTs. Each XT keeps only the last `set_mackie_control_main` caller.
- **Possible ways to run both:**
  - Use only one surface's MCU stack in Live at a time.
  - Use copied or renamed scripts. Copying the factory `.pyc` files works; the decompiled Live 12 `.py` files have parse errors ([Ableton forum](https://forum.ableton.com/viewtopic.php?p=1833644)).
  - Decide this explicitly before building.

## 4. Existing tools and what they teach
- **[AbletonOSC](https://github.com/ideoforms/AbletonOSC):** meter getters and listeners exist but are limited (§2.2). TouchOSC users report choppy meters and stale values.
- **[ableton-js](https://github.com/leolabs/ableton-js):** uses a fast `Live.Base.Timer`, UDP/WebSocket and gzip. Prefer `output_meter_left/right` over `output_meter_level` for listeners.
- **[LiveGrabber](https://support.showsync.com/sync-tools/livegrabber/introduction):** Max for Live devices that send track data and audio analysis over OSC, but the device has to be in the Set.
- **TouchOSC / LiveControl:** used an ad-hoc meter curve ([forum](https://forum.ableton.com/viewtopic.php?p=1470247)).
- **Open Stage Control users:** went from LOM meters to per-track VSTs to Max for Live, and ran into OSC flooding at a 2.3 ms send rate. Throttle to about 25–40 ms ([thread](https://openstagecontrol.discourse.group/t/vu-metter-from-ableton-live-to-osc/1205)).
- **[Maus3rVonDutch UF8 scripts](https://github.com/Maus3rVonDutch/ableton-ssl-uf8-scripts):** a modified MackieControl that adds auto-banking, channel-encoder selection, and two-way bank/selection sync (selecting a track in Live updates the UF8 bank). This confirms stock MackieControl does not bank-follow selection.
- **MackieControl itself:** UF8 LCD metering has only 12 steps at 10 Hz, which is the shortcoming the bridge fixes.

## Open questions
- What is the exact mapping from output_meter_left/right/level (0..1) to dBFS in Live 11 vs Live 12? Is it the same curve as the volume fader (so volume.str_for_value(meter) gives dB)? Needs a calibration session with sine tones at known levels.
- How many distinct meter values per second does Live actually produce (20-30 Hz per ableton-js vs about 100 ms per AbletonOSC)? Measure by polling at 60 Hz with a Live.Base.Timer and counting changes.
- Does the user really want the 3 MackieControlXT scripts in slots 4-6? Removing them would make the UF8 bank by 8 (inferred to be 32 now) and free a slot for the bridge script. Need to confirm on the hardware.
- Will the UF8 and the Wing ever be used with Live at the same time? If so, two MackieControl stacks conflict over the XT instances, and a renamed or forked MCU script would be needed.
- How should the bridge map each MackieControl slot to a physical device: user configuration, parsing Live's Log.txt, or Live 12's control_surface_input_ports API (unverified whether Python can use it)?
- Which Wing fader section (left/center/right) maps to the MCU master and to each extender under SETUP > DAW > CONFIGURATION, and does that change with layers?
- How should the bridge detect that the UF8 has switched away from the Ableton layer (to Pro Tools/HUI or the SSL 360 plugin mixer)? Live can't see this, so it may need SSL 360-side detection.
- Does Live 12's DeviceParameter.display_value return the volume in dB as a float (and what does it return for -inf)? That would replace the str_for_value lookup table on Live 12.
- Should the bridge show input meters for armed/monitoring tracks, as Live's mixer and MackieControl do (input_meter_level when armed)?
- Is the stale-meter-after-stop behaviour (AbletonOSC #70) a listener-only problem, or does polling show it too?


## Verification
- [CONFIRMED] Custom Remote Scripts go in ~/Music/Ableton/User Library/Remote Scripts (Live 10.1.13+), are picked in the Control Surface dropdown, and need no MIDI ports. A local Live 12.4.5 log shows AbletonMCP running with Input/Output = None.
  - Confirmed. The Live 10.1.13 release notes say a 'Remote Scripts' folder can be created in the User Library and scripts in it 'will appear in the Link/MIDI Preferences tab'. On this Mac, ~/Music/Ableton/User Library/Remote Scripts/AbletonMCP/__init__.py exists. The Live 12.4.5 Log.txt shows 'MidiRemoteScript 3 [Control Surface="AbletonMCP" Input="None" Output="None"]', followed by '(AbletonMCP) Server started on port 9877'. Library.cfg uses the default User Library location. The help.ableton.com article returned HTTP 403, so the release notes are the primary source. Small caveat: the installed app is 12.4.6, but 12.4.6 has not been launched yet (no 'Live 12.4.6' prefs folder exists, and the last log entry is 12.4.5 on 2026-10-04). (https://www.ableton.com/en/release-notes/live-10/)
- [CONFIRMED] Live 11.3.42 runs Remote Scripts on Python 3.7 (pyc magic 3394) and Live 12.4.6 on Python 3.11 (magic 3495). One script supporting both must use 3.7-compatible syntax.
  - Confirmed for the installed builds. The MackieControl.pyc header is 420d0d0a (3394, Python 3.7) in 'Ableton Live 11 Suite.app' 11.3.42 and a70d0d0a (3495, Python 3.11) in 'Ableton Live 12 Suite.app' 12.4.6. Caveat: Python 3.11 does not cover all of Live 12. The decompiled gluon Live 12 repo is mostly Live 12.0 bytecode, and its headers say '3.7.0 (3394)', compiled 2024-03-09. Which 12.x release moved to 3.11 is UNVERIFIED. Ship .py source, not .pyc, and avoid 3.8+ syntax and stdlib (walrus, positional-only params, match, PEP 604 unions). (file:///Applications/Ableton%20Live%2011%20Suite.app/Contents/App-Resources/MIDI%20Remote%20Scripts/MackieControl/MackieControl.pyc)
- [UNCERTAIN] Live has 7 Control Surface slots (MidiRemoteScript 1-7 in the local Live 11 and 12 logs; the manual still says six). All 7 are currently occupied on the user's Mac.
  - The logs do list 7 entries. The Live 12 manual says 'Up to six supported control surfaces can be used simultaneously', and the accessibility chapter says the tab has 'six Control Surface drop-down menus'. Entry 7 has been Launchkey_Mini_MK3 with None/None in every Live 11.x and 12.x log on this Mac and never changes. That suggests a hidden or non-user slot, but this is UNVERIFIED (the web search budget ran out before it could be confirmed). 'All occupied' is misleading. In the 12.4.5 log only slot 1 (MackieControl on SSL V-MIDI Port 1) has ports. Slot 3 (AbletonMCP) is port-less by design. Slot 2 (SL_MkIII) and slots 4-6 (MackieControlXT, all None) have no ports; slots 4-6 are leftovers from the Wing setup (Preferences.cfg still names 'MackieControlXT Output (WING (Port 2/3/4))'). A slot can easily be freed. Cycling '74 LOM also notes that control_surfaces returns id 0 for slots set to None or holding an inactive script. (https://www.ableton.com/en/manual/midi-and-key-remote-control/)
- [CONFIRMED] output_meter_left/right are smoothed momentary peaks (0..1, audio-output tracks only). output_meter_level is a 1-second hold peak (max of L/R, MIDI tracks too). All are observable from Python and measured post-mixer.
  - The LOM text matches word for word. left/right: 'Smoothed momentary peak value ... 0.0 to 1.0. For tracks with audio output only. This value corresponds to the meters shown in Live.' level: 'Hold peak value of output meters of audio and MIDI tracks ... For audio tracks, it is the maximum of the left and right channels. The hold time is 1 second.' Access is get/observe. Caveats: (1) 'post-mixer/post-fader' is not stated in the LOM. The manual only says the meter 'shows ... output levels', and 'While monitoring, however, it shows peak and RMS input levels'. (2) The LOM warns that 'the left/right audio meters put a significant load onto the GUI part of Live'. (3) There is no RMS in the LOM. (4) input_meter_left/right/level also exist, and MackieControl uses input_meter_level for armed tracks. (https://docs.cycling74.com/apiref/lom/track/)
- [CONFIRMED] The mapping from meter value (0..1) to dBFS is not documented. Community conversions (20*log10, LiveControl hack, 0.85≈0 dB) are guesses, so it must be calibrated empirically.
  - Confirmed. The LOM only says '0.0 to 1.0'. In the forum thread, the only formula is the poster's reverse-engineered LiveControl expression 'level = (math.pow(10,level)-1.0)/10.0'; no Ableton staff replied and the question of units went unanswered. Supporting detail: Ableton's own MackieControl drives the UF8's 12-segment meter linearly with int(output_meter_level*12) (ChannelStrip.on_update_display_timer), which treats the value as display-scaled, not dB. Note that 0.85 ≈ 0 dB is the volume fader parameter's scale, not the meter's, so it should not be used for meters. Calibrate with test tones at known dBFS. (https://forum.ableton.com/viewtopic.php?p=1470247)
- [CONFIRMED] update_display / schedule_message tick every 100 ms, but Live.Base.Timer supports millisecond intervals. Ableton's own Push2 script uses a 16 ms timer, so polling meters at 30 Hz or more from a script is feasible.
  - Confirmed. _Framework/Defaults.py and ableton/v2/control_surface/defaults.py set TIMER_DELAY = 0.1, and update_display advances the task group by it. Push2/hardware_settings_component.py uses Live.Base.Timer(callback=..., interval=LED_FADE_IN_FREQUENCY) with LED_FADE_IN_FREQUENCY = 16. Other stock scripts confirm the unit is milliseconds: Push2 notification_component uses interval=int(1000*notification_time), Blackstar footswitch uses int(1000*pulse_length), and v3 display/state uses int(delay_time*1000). Caveat: the claim that 30 Hz or faster polling of 24 tracks is feasible is UNVERIFIED. Timer callbacks run on Live's main thread, and the LOM warns that L/R meters load the GUI. Benchmark it before relying on it. (https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/blob/main/Push2/hardware_settings_component.py)
- [UNCERTAIN] Meter listeners fire about 20-30 times/s for output_meter_left/right, while output_meter_level listeners stall every few hundred ms. Another maintainer reports about 100 ms delivery, so the true refresh rate is unverified.
  - The source is misread. The README's '20-30 updates per second are not unusual' is a general note about events ('for some values'), not a measured rate for output_meter_left/right. The README and issue #4 do say output_meter_level 'hangs every few 100ms', with values arriving in bursts then nothing for about half a second. Switching to output_meter_left gave 'a huge number of values per second', with no number given. I found no source for 'another maintainer reports about 100 ms'; it is UNVERIFIED. The level stalls are expected by design: it is a 1-second hold peak, and listeners fire only when the value changes. The true listener rate is UNVERIFIED and should be measured in Live 11.3.42 and 12.4.6. (https://github.com/leolabs/ableton-js/issues/4)
- [CONFIRMED] Remote Scripts can open UDP/TCP sockets. AbletonOSC uses non-blocking UDP on 11000/11001 and supports /live/track/start_listen/output_meter_level|left|right, but it logs every event, has no return/master tracks and processes input only every 100 ms.
  - Confirmed from source (master, last commit 2025-11-19). osc_server.py uses socket(AF_INET, SOCK_DGRAM) with setblocking(0) and binds 0.0.0.0, so it listens on every interface (a security note). The README gives port 11000 in and 11001 out. track.py lists output_meter_level/left/right as listenable properties. Track indexing uses self.song.tracks only, so there are no returns or master. handler.py logs every property change at INFO, which is the default level. manager.py tick() is 'Called once per 100ms', and that is where osc_server.process() runs. Nuance: outbound listener messages are sent immediately from the listener callback, so only inbound processing is limited to 100 ms. The user's AbletonMCP (TCP 9877) also proves sockets work in this Live. (https://github.com/ideoforms/AbletonOSC)
- [CONFIRMED] Scripts can set track.mute/solo/arm, song.view.selected_track and mixer_device.volume.value. Setting solo bypasses exclusive solo, and LOM changes can't be made inside listener callbacks (they must be deferred).
  - Confirmed. The LOM solo remark reads: 'when setting this property, the exclusive Solo logic is bypassed, so you have to unsolo the other tracks yourself. [not in master track]'. Arm is not available on return or master tracks. Ableton's MackieControl ChannelStrip.__toggle_solo_track clears other solos by hand. The Live 12.4.6 binary contains 'Changes cannot be triggered by notifications.' Also missed: changes are blocked during undo/redo too. The user's Live 11 log shows 'RemoteScriptError: Changes cannot be triggered during undo or redo. You will need to defer your response.' volume.value is a normalized 0..1 DeviceParameter, not dB; use str_for_value for display. (https://docs.cycling74.com/apiref/lom/track/)
- [CONFIRMED] The SSL UF8 connects to Live through Ableton's stock MackieControl script on SSL V-MIDI Port 1 (XTs on ports 2-4 for more UF8s). No SSL-specific Live script exists in Live 12.4.6 or SSL 360 2.0.6.
  - Confirmed. The UF8 User Guide Rev 1.5, Live tutorial (p. 56), says: 'select MackieControl. Set the Input to SSL V-MIDI Port 1 Source ... use drop-down lists 2-4 to add subsequent MackieControl XTs, incrementing the SSL V-MIDI Port number'. The local Live 12.4.6 'MIDI Remote Scripts' folder has no SSL, UF or UC1 entry, and SSL 360.app 2.0.6.67265 contains no .py or Ableton script. Caveat: ports depend on the UF8 DAW LAYER. Layer 1 uses V-MIDI 1-4, Layer 2 uses 5-8, Layer 3 uses 9-12 (guide p. 55). Port 1 is correct only while Live is on Layer 1. (https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide_Rev1.5.pdf)
- [REFUTED] The Behringer Wing connects to Live as MackieControl on WING Port 1 plus MackieControlXT on WING Ports 2 and 3 (24 strips).
  - This is wrong for the user's own setup. Every Live log with the Wing (11.0.12, 11.3.4-11.3.35, 12.2.5, 12.3.7) shows MackieControl on 'WING (Port 1)' plus MackieControlXT on 'WING (Port 2)', 'WING (Port 3)' AND 'WING (Port 4)'. That is 4 MCU units, or 32 strips. Preferences.cfg also lists four WING ports and a 'WING #2 (Port 1-4)'. The WING manual says SETUP → DAW → CONFIGURATION 'determines the number of DAW controllers emulated by the console', so the strip count is configurable, not fixed at 24. EMULATION can be MCU or HUI, and CONNECTION can be USB or DIN5. The WING DAW PDF returned HTTP 500, so its recommended preset and the mapping of MCU strips onto the 12/8/4 fader sections are UNVERIFIED. (file://~/Library/Preferences/Ableton/Live%2012.3.7/Log.txt)
- [CONFIRMED] Bank follow works by reading other scripts: application().control_surfaces returns the slot-indexed Python script instances. MackieControl._MackieControl__channel_strips / MackieControlXT.channel_strips() give the strips, and ChannelStrip.assigned_track() gives the exact Track on each hardware strip. These names exist in both installed builds (11.3.42 and 12.4.6) but are private.
  - Confirmed. _MxDCore/LomTypes.get_control_surfaces() filters None out of Live.Application.get_application().control_surfaces, which shows the list holds script instances, with None for empty or inactive slots. MackieControlXT defines channel_strips(), and ChannelStrip defines assigned_track(), which returns __assigned_track. A byte-grep of the installed .pyc files in both 11.3.42 and 12.4.6 finds _MackieControl__channel_strips, channel_strips, assigned_track, set_mackie_control_main and __bank_cha_offset. Caveat: the gluon Live 12 decompile is mostly Live 12.0 bytecode. The gluon Live 11 ChannelStripController.py contains unresolved git merge-conflict markers. Do not treat either as authoritative for 12.4.6. (https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/tree/main/MackieControl)
- [CONFIRMED] MackieControl claims every MackieControlXT instance in any slot as an extension, and its bank step equals the total strip count. MackieControl sets no session-ring highlight, so the 'session box' approach can't work.
  - Confirmed. connect_script_instances loops over every instantiated script. For each isinstance(s, MackieControlXT) it calls s.set_mackie_control_main(self) and appends the XT to left_extensions (slot before MackieControl) or right_extensions (slot after). Bank Prev/Next steps by len(__channel_strips), which includes the extension strips. Channel Prev/Next steps by 1, and Shift+Bank jumps to the first or last bank. Banking indexes song.visible_tracks, so folded group children are skipped, and a returns-view mode maps the strips to return_tracks. The MackieControl and MackieControlXT sources and the 12.4.6 bytecode contain no set_session_highlight or session ring. Because of this, follow the bank through assigned_track() rather than computing indexes. (https://github.com/gluon/AbletonLive11_MIDIRemoteScripts/blob/main/MackieControl/MackieControl.py)
- [CONFIRMED] In the user's current config, the 3 port-less MackieControlXT scripts in slots 4-6 probably extend the UF8's MackieControl to 32 strips, so UF8 banking likely jumps 32 tracks. Running the UF8 and the Wing MCU stacks at the same time would conflict.
  - The code supports this, but it has not been observed at runtime. Slot 1 is MackieControl (SSL V-MIDI Port 1) and slots 4-6 are MackieControlXT, so all three XTs are right extensions. Scripts load without ports, as AbletonMCP shows with None/None. That gives 8+24 = 32 strips and a 32-track bank step, while the UF8 itself shows strips 1-8. These XTs are leftovers from the Wing setup (Preferences.cfg names them 'WING (Port 2/3/4)'). A second MackieControl would also claim every XT, and set_mackie_control_main would be overwritten, so running both stacks at once conflicts. Check at runtime by pressing Bank > on the UF8 or by logging len(_ChannelStripController__channel_strips). (file://~/Library/Preferences/Ableton/Live%2012.4.5/Log.txt)
- [CONFIRMED] Per-track Max for Live / AU meters give true sample-accurate dBFS, but they sit pre-fader in Live's device chain, unlike output_meter_* which is post-mixer. The app would have to add the fader gain.
  - Mostly confirmed. The manual says 'When the signal has passed through the device chain, it ends up in Live's mixer', so devices are pre-fader. The cited nsuspray XML is not the right source for that point. Caveats: you would also need Live's pan law and mute/solo state, not just the fader gain. A per-track device has to be inserted on all 24 tracks and needs IPC to the app. That output_meter_* is post-fader is not stated in the LOM (UNVERIFIED in the docs, though the manual calls the meter the track's 'output levels'). (https://www.ableton.com/en/manual/live-concepts/)

### Missed points
- The user's own Wing setup is 4 MCU units, not 3. Live logs from 11.0.12 through 12.3.7 show MackieControl on WING (Port 1) plus MackieControlXT on WING Ports 2, 3 and 4. Preferences.cfg also remembers a second device, 'WING #2 (Port 1-4)'. The bridge must support 32 Wing strips, or the user should reduce the WING DAW CONFIGURATION.
- The WING's physical layout is uneven: three fader sections of 12 (left), 8 (center) and 4 (right), separated by gaps (WING manual 4.2). Meter alignment needs per-section offsets, not 24 equal widths. How MCU strips map onto the sections is set in SETUP → DAW → CONFIGURATION and is UNVERIFIED.
- UF8 DAW layers change the ports: Layer 1 uses SSL V-MIDI 1-4, Layer 2 uses 5-8, Layer 3 uses 9-12 (UF8 guide p. 55). A Live script cannot see which layer the UF8 is currently showing. If Pro Tools sits on another layer, the bridge needs a layer indicator or SSL 360 state to know which DAW the UF8 is following.
- The LOM warns: 'the left/right audio meters put a significant load onto the GUI part of Live.' 48 L/R listeners (24 tracks × 2) could affect Live's UI; benchmark this against polling.
- The LOM exposes peak only, with no RMS, even though Live's GUI meter shows peak and RMS. While a track is monitoring, Live's meter shows input level. MackieControl itself switches to input_meter_level for armed tracks, and input_meter_left/right/level exist in the LOM.
- MackieControl drives the UF8 LCD meters from output_meter_level (the 1-second hold value), scaled linearly to 12 segments with int(v*12) and sent as MCU channel pressure 0xD0. The bridge's meters will therefore not match the UF8's LCD ballistics.
- Banking follows song.visible_tracks, so collapsed group children are skipped. A returns-view mode remaps the strips to return tracks, and Channel </> shifts by 1. The bridge should read assigned_track() per strip rather than compute indexes.
- Live 12 renamed Master to 'Main' in the UI (the AbletonMCP log says 'Main and Return Tracks have no Arm state'), but the LOM still uses master_track. mute and solo are not available on master, and arm is not available on return or master tracks.
- LOM writes are also refused during undo/redo, not only inside notifications. This appears in the user's Live 11 log as 'Changes cannot be triggered during undo or redo. You will need to defer your response.'
- mixer_device.volume.value is a normalized 0..1 parameter. Use DeviceParameter.str_for_value() to get dB text. Shift fine-drag should change the normalized value in small steps. Ableton's own fader feedback uses a 200 ms feedback delay (MackieControl build_midi_map).
- A Max for Live device using LiveAPI on the master track can observe the same output_meter_* values and read control_surfaces without using a Control Surface slot. That is an alternative if slots are scarce. control_surfaces returns id 0 for slots set to None or holding an inactive script.
- Port and security notes: AbletonMCP already uses TCP 9877 and AbletonOSC binds 0.0.0.0:11000. A custom bridge script should bind 127.0.0.1 and use a port that does not collide with either.
- Live 12.4.6 is installed (build 2026-09-10) but has not been launched yet; the newest prefs and log are 12.4.5 (last run 2026-10-04). Re-check the control-surface slots after the first 12.4.6 launch.
- The decompiled sources are not authoritative. gluon's Live 12 repo is mostly Live 12.0 bytecode (Python 3.7, compiled March 2024), and gluon's Live 11 ChannelStripController.py contains merge-conflict markers. Verify behaviour against the installed 11.3.42 and 12.4.6 bytecode or at runtime.
- Research limits: the web search budget ran out mid-check, the WING DAW Documentation PDF returned HTTP 500, and help.ableton.com returned 403. The WING DAW preset details and the purpose of the 7th slot remain UNVERIFIED.
