# DAW Meter Bridge

A native macOS menu-bar app that draws large DAW track meters on a display above a hardware control surface (SSL UF8, Behringer WING), aligned to the physical channel strips, with click-to-select/solo/mute and drag-for-volume. It is the Mac counterpart of the Windows-only DAWWAY. Ableton Live comes first; Pro Tools is deferred.

Read before changing things:
- `docs/ARCHITECTURE.md`: scope, decisions, modules, layout model, interactions.
- `docs/PROTOCOL.md`: the UDP/JSON protocol between the Live Remote Script and the app. **Change the doc first**, then both sides.
- `docs/CONTROL.md`: the control protocol (Stream Deck plugin ⇄ app) and the `dawmeterbridge://` URL scheme. Same rule: doc first.
- `docs/research/`: the research behind the decisions. Claims marked UNVERIFIED there are not facts.

## Layout

- `Package.swift`: one SwiftPM package, macOS 14+, Swift 6 language mode, **no third-party dependencies**.
- `Sources/MeterCore`: model (`TrackInfo`, `BridgeSnapshot`, `SurfaceUnit`), `BridgeCommand`, `MeterSource` protocol, `MeterStore` + ballistics, mix focus, `VolumeCurve`, `MeterCalibration`. No AppKit.
- `Sources/BridgeProtocol`: Codable wire messages for docs/PROTOCOL.md.
- `Sources/MeterSources`: `SimulatedSource`, `LiveSource` and `UDPEndpoint` (BSD socket + DispatchSource UDP).
- `Sources/BridgeLayout`: strip groups, bindings, templates (UF8, WING), the Main meter (`MainMeter.swift`), calibration and edit math, persistence. No AppKit.
- `Sources/BridgeControl`: the control protocol of docs/CONTROL.md: `ctl` message coding, subscribers, `ControlServer` (UDP), `ControlURL`. No AppKit.
- `Sources/MeterRendering`: Core Animation strip/bank views.
- `Sources/MeterBridgeApp`: the executable (menu bar and its drawn icon, panels, edit mode, hotkeys, settings, `Control/` for the control server and URL handler).
- `AbletonRemoteScript/MeterBridge`: the Python Remote Script that runs inside Live.
- `StreamDeckPlugin/`: the Stream Deck plugin (Node 24 built-ins only, no npm; tests with `node:test`).
- `Resources/AppIcon.icns`: the app icon, drawn by `scripts/make-icons.swift` (which also draws the Stream Deck images).
- `scripts/`: build the .app bundle, install the Live script, package/install the Stream Deck plugin, draw the icons.

## Commands

```bash
swift build                                    # build everything
swift test                                     # Swift Testing suites
swift run MeterBridge                          # run the app from the command line
scripts/build-app.sh                           # build/DAW Meter Bridge.app (ad-hoc signed)
OUTPUT_DIR=<dir> SCRATCH_PATH=<dir> scripts/build-app.sh  # bundle elsewhere, e.g. while build/ is running
scripts/install-live-script.sh                 # copy the Remote Script into Live's User Library
cd AbletonRemoteScript && python3 -m unittest  # Remote Script tests (fake Live module)
"$HOME/Library/Application Support/com.elgato.StreamDeck/NodeJS/24.13.1/node" --test StreamDeckPlugin/tests/*.test.mjs  # plugin tests
<bin>/MeterBridge --source simulator --data-dir <tmp> --control-port 47892  # a test copy beside the installed app
```

Ports, all UDP on 127.0.0.1: **47800** the app (from the Live script), **47801** the Live script (from the app), **47802** the app's control server (Stream Deck; `--control-port` for test copies). URL scheme: `dawmeterbridge://bridge|main|edit/toggle|show|hide`.

Running a test copy while the user's app runs: execute the binary directly with its own `--data-dir` and `--control-port`, never `open` a second .app bundle (that registers another copy for the bundle id and the URL scheme). `--snapshot` and `--demo-edit` runs never start the control server or take URLs.

When several agents build at once, give each its own `--scratch-path` so they don't wait on the shared `.build` lock.

## Conventions

- Swift 6 strict concurrency. UI, sources and `MeterStore` are `@MainActor`. Network callbacks hop to the main actor before touching state.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Keep AppKit out of MeterCore, BridgeProtocol, MeterSources, BridgeLayout and BridgeControl so they stay unit-testable. App-only logic that needs tests goes into one of them (e.g. `MainMeter` in BridgeLayout, `ControlURL` in BridgeControl).
- The Remote Script must run on Live 11 (Python 3.7) and Live 12 (Python 3.11). Use only Python 3.7 syntax and stdlib (no walrus, no `match`, no PEP 604 unions). A test enforces this with `ast.parse(..., feature_version=(3, 7))`.
- The Remote Script never writes to the Live Object Model from a listener callback; it queues the change and applies it in its timer tick.
- Network sockets bind 127.0.0.1 only.
- Opening a `dawmeterbridge://` URL, a Stream Deck press and clicks on the bridge must never take keyboard focus from the DAW.
- The user's hardware facts (UF8 fader pitch 38.5 mm, WING 12+8+4 sections, displays) live in `docs/research/03-physical-layouts-and-displays.md`.
