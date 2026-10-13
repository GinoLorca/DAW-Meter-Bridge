# Architecture

DAW Meter Bridge is a native macOS app that shows large per-track meters on a display above a hardware control surface. Each meter lines up with a physical channel strip, and clicks on a meter control the DAW. It is a Mac counterpart to the Windows-only DAWWAY.

Research behind these decisions is in [`research/`](research/). Start with [`research/01-technical-brief.md`](research/01-technical-brief.md) and [`research/02-ableton-live.md`](research/02-ableton-live.md).

## Scope (confirmed with the user, 2026-10-11)

| Area | Decision |
|---|---|
| DAW | **Ableton Live 11/12 first.** Pro Tools is deferred ([research](research/04-pro-tools-deferred.md)); keep it possible, build nothing for it yet. |
| Surfaces | SSL UF8 (primary) with UF1/UC1 alongside it in the Bronx studio, and Behringer WING in DAW-controller mode in the Brooklyn studio. They are never used together. |
| Tracks | Up to 24 strips on the bridge. |
| Mix focus | Show **and** control: reflect mute, solo, solo-implied mute, arm and selection; click to select, solo or mute; drag to set volume. |
| Fine control | Shift gives fine control for layout edits (move/resize) and for volume drags. |
| Displays | Develop and test on a strip along the bottom of the main LG ultrawide, which sits directly behind the UF8. Later, move the bridge to a dedicated bar display (12.6" 1920×515 or 14.1" 3840×1100) and recalibrate. |
| Hide | Global hotkey (default ⌃⌥⌘M) and menu-bar item. |

## Key decision: an Ableton Remote Script, not an MCU proxy

The technical brief recommended putting the bridge in the MIDI path between Live and SSL 360°, as an MCU proxy like DAWWAY. The Ableton deep-dive found a better route **for Live**, so we use that first:

- A small Python **MIDI Remote Script** (`AbletonRemoteScript/MeterBridge`) runs inside Live. It needs no MIDI ports, only a free Control Surface slot.
- It reads post-fader stereo meters (`Track.output_meter_left/right`, float 0..1), full names, colours, mute, solo, arm, `muted_via_solo`, selection and volume from the Live Object Model. It also applies commands from the app: select, mute, solo, arm and volume.
- **Bank follow without a proxy.** The script finds the `MackieControl`/`MackieControlXT` script instances that drive the UF8 or the WING through `Live.Application.get_application().control_surfaces`. It asks each hardware strip which track it shows with `ChannelStrip.assigned_track()`, so the bridge always matches the hardware exactly, including bank, channel-shift, folded groups and returns view.

Why this beats the proxy for Live:

| | Remote Script (chosen) | MCU proxy |
|---|---|---|
| Meter quality | Float stereo, post-fader, ~30 Hz | 13 steps, mono, ~10 Hz |
| Names / colours | Full names, colours | 7 chars, no colour |
| UF8 if the bridge app quits | Unaffected | Goes dead (the bridge is in its MIDI path) |
| Setup | Copy the script folder, pick it in one Control Surface slot | Re-route Live's Mackie ports through the bridge |
| Bank alignment | Exact (`assigned_track()`) | Exact |
| Fragility | Reads private attributes of Ableton's MackieControl script, which a Live update could rename. Detected at runtime with a clear fallback. | Depends on SSL 360 tolerating a proxy (untested) |

The MCU/HUI proxy stays in the plan for Pro Tools (HUI), which has no meter API.

## Components

```
┌──────────────────────── Ableton Live ────────────────────────┐
│ Control Surface slot 1: MackieControl ⇄ SSL V-MIDI Port 1 ⇄ SSL 360° ⇄ UF8
│ Control Surface slot N: MeterBridge (our script, no MIDI ports)
│   • polls meters at ~30 Hz (Live.Base.Timer)
│   • listens for track/mixer/selection changes
│   • reads MackieControl strips → assigned tracks
└───────────────┬───────────────────────────▲──────────────────┘
      UDP 127.0.0.1:47800 (state, meters)   │ UDP 127.0.0.1:47801 (commands)
┌───────────────▼───────────────────────────┴──────────────────┐
│ DAW Meter Bridge.app (Swift, AppKit, menu-bar only)          │
│  MeterSources → BridgeModel → MeterRendering → bank panels   │
└──────────────────────────────────────────────────────────────┘
```

The wire format is specified in [PROTOCOL.md](PROTOCOL.md).

## Swift package layout

A single SwiftPM package. `swift build` / `swift test` work from the command line and Xcode opens `Package.swift` directly. Deployment target is macOS 14 (needed for `NSView.displayLink`); language mode is Swift 6. There are no third-party dependencies.

Dependencies point downward only:

```
MeterBridgeApp (executable)  menu bar, panels, edit mode, hotkey, settings, display manager, persistence wiring
 ├─ MeterRendering           Core Animation strip/bank views, display-link driver, styling
 ├─ BridgeLayout             layout model (strip groups, bindings, templates), calibration and edit math, JSON persistence
 ├─ MeterSources             MeterSource implementations: SimulatedSource, LiveSource (UDP)
 │   └─ BridgeProtocol       wire messages (Codable) for the Live script ⇄ app protocol
 └─ MeterCore                track/snapshot model, BridgeCommand, MeterSource protocol, ballistics, mix focus, volume curve
```

| Module | Imports AppKit? | Unit tested |
|---|---|---|
| MeterCore | No | Yes |
| BridgeProtocol | No | Yes |
| MeterSources | No (Network.framework) | Yes |
| BridgeLayout | No (CoreGraphics types only) | Yes |
| MeterRendering | Yes | Smoke |
| MeterBridgeApp | Yes | Manual/run |

## Data model

- **Track** (`TrackInfo`): stable `TrackID` (Live's object pointer, or a simulator id), index, name, colour, kind (audio/MIDI/group/return/main), mute, solo, arm, `mutedViaSolo`, `hasAudioOutput`, volume (normalized 0..1 plus a display string).
- **Surface unit** (`SurfaceUnit`): one emulated Mackie device (UF8, an XT, or a WING section), with its 8 strips → `TrackID?`, in physical left-to-right order.
- **BridgeSnapshot**: everything the UI needs except meter levels. It is replaced as a value on each state change.
- **Meters**: `MeterStore` keeps the latest normalized left/right levels per track. The renderer pulls from it on every display-link frame, and `Ballistics` turns the samples into smooth bars, peak hold, the peak dB readout and a latched clip indicator.

## Layout model

The bridge is made of **strip groups**. Each group is one borderless panel holding `stripCount` equally spaced meters, and is bound to a source of tracks:

- `surfaceUnit(index, firstStrip)`: strips of a hardware unit. "UF8" is one group of 8 on unit 0.
- `selectedTrack` / `mainTrack`: a single focus meter, e.g. above the UF1.
- `trackList(offset)`: consecutive tracks, used when no surface is present (simulator, or extra context strips).

Groups of any size let the layout follow uneven hardware. The WING's DAW mode maps three 8-strip MCU units across fader sections of 12 + 8 + 4. Its faders come in blocks of four with a wider gap between blocks, so its template is six groups of four: L1–4, L5–8, L9–12, C1–4, C5–8 and R1–4. Each group's meters sit within about 0.4 mm of their faders; one L1–8 group would be up to about 5 mm off.

**Positioning**
- Group frames are stored relative to their display, so rearranging displays doesn't break them.
- Each layout is keyed by a display fingerprint: UUID, then vendor+model+serial, then name+size.
- **Two-point calibration:** drag a marker over the first and last fader, and the group's pitch and edges follow.
- **Move to display:** "slide it over" to the bar display keeps the group's relative position, then you recalibrate.

**Profiles**
- A profile, e.g. "Bronx — UF8" or "Brooklyn — WING", is a set of layouts.
- The app picks the profile whose displays and surfaces match what is connected. The user can also choose one manually.

## Interaction

| Gesture | Bridge mode | Edit mode |
|---|---|---|
| Click name / colour bar | Select track | Select group |
| Click **S** / **M** | Toggle solo (⌘ = additive) / mute | — |
| Vertical drag on meter | Set volume; **Shift = fine (×0.1)** | Move group; **Shift = fine (×0.1)** |
| Drag group edge | — | Resize; Shift = fine |
| Arrow keys | — | Nudge 1 px; ⌥ = 10 px |
| Double-click meter | Reset peak hold, clip and readout | — |
| ⌃⌥⌘M | Show/hide bridge | Show/hide bridge |
| ⌃⌥⌘E | Toggle edit mode | Toggle edit mode |

Clicks on the bridge never take keyboard focus from Live: panels are non-activating and views accept the first mouse click. Transparent gaps between groups pass clicks through to the window underneath.

A volume drag always goes to the track grabbed at mouse-down, even if the bank changes mid-drag. Its final value is sent on mouse-up with `"end": true`, and the script records the whole drag as one gesture and one undo step in Live ([PROTOCOL.md](PROTOCOL.md), `vol`).

## Windows

`BridgePanel` is a borderless, non-activating `NSPanel`:
- Level just below the Dock (`GroupPanelController.level(for:)`): above every app window, while a revealed Dock draws over the bridge and stays clickable. A group that covers a display's menu-bar strip (a short bar display) uses `.statusBar` instead.
- Collection behaviour `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, so it appears in every Space and next to full-screen apps.
- `hidesOnDeactivate = false` and `canHide = false`, so Live's "Hide Others" doesn't hide it.
- `canBecomeKey` only in edit mode, so it can take arrow keys there.

One `CADisplayLink` per display drives rendering, and it idles when all meters have decayed.

One running copy per data folder: the app holds an exclusive `flock` on `.meterbridge.lock` next to layouts.json for its lifetime. A second launch on the same folder asks the running copy to show itself and quits. Runs with another `--data-dir` lock their own folder, and `--snapshot` runs take no lock.

## Testing and tooling

- **`swift test`** uses Swift Testing (`import Testing`). It covers protocol coding, ballistics, mix focus, the volume curve, layout math, calibration, persistence and the simulator.
- **`python3 -m unittest`** in `AbletonRemoteScript/` runs the script's tests against a fake `Live` module.
- **`scripts/build-app.sh`** builds `build/DAW Meter Bridge.app` (LSUIElement, ad-hoc signed). `OUTPUT_DIR=<dir>` puts the bundle elsewhere (verification builds, so they never replace the copy you are running) and `SCRATCH_PATH=<dir>` builds in its own scratch folder.
- **`scripts/install-live-script.sh`** copies the script into `~/Music/Ableton/User Library/Remote Scripts/MeterBridge`.
- The **simulator source** (menu → Source → Simulator) drives the whole UI without Live. It provides 32 tracks, a virtual 8-strip surface you can bank, and musical meter motion. It is also the demo/calibration mode.

## Open items to settle with real hardware

These come from the research's UNVERIFIED list and need checking on the actual setup:
1. **UF8 bank step.** Live slots 4–6 hold port-less `MackieControlXT` entries left over from the WING setup. They probably make the UF8 bank by 32 instead of 8. Remove them, which also frees a slot for MeterBridge.
2. **Meter calibration.** The mapping of Live's 0..1 meter value to dBFS is undocumented. Calibrate it with test tones and store the result as a `MeterCalibration` (points plus the clip threshold `clipValue`) in the settings key `liveMeterCalibration`; the app applies it while the source is Live. Meter **height** uses Live's own scale, so it matches Live's meters even before calibration; only the numeric dB readout and the clip LED depend on it.
3. **Load.** Measure the real meter update rate and Live GUI load with 24+ tracks observed.
4. **UF8 layer.** The bridge cannot tell whether the UF8 is on another DAW layer or in the Plug-in Mixer.
