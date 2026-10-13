# DAW Meter Bridge

A native macOS menu-bar app that draws large DAW track meters on a display above a hardware control surface (SSL UF8, Behringer WING), aligned to the physical channel strips, with click-to-select/solo/mute and drag-for-volume. It is the Mac counterpart of the Windows-only DAWWAY. Ableton Live comes first; Pro Tools is deferred.

Read before changing things:
- `docs/ARCHITECTURE.md`: scope, decisions, modules, layout model, interactions.
- `docs/PROTOCOL.md`: the UDP/JSON protocol between the Live Remote Script and the app. **Change the doc first**, then both sides.
- `docs/research/`: the research behind the decisions. Claims marked UNVERIFIED there are not facts.

## Layout

- `Package.swift`: one SwiftPM package, macOS 14+, Swift 6 language mode, **no third-party dependencies**.
- `Sources/MeterCore`: model (`TrackInfo`, `BridgeSnapshot`, `SurfaceUnit`), `BridgeCommand`, `MeterSource` protocol, `MeterStore` + ballistics, mix focus, `VolumeCurve`, `MeterCalibration`. No AppKit.
- `Sources/BridgeProtocol`: Codable wire messages for docs/PROTOCOL.md.
- `Sources/MeterSources`: `SimulatedSource` and `LiveSource` (Network.framework UDP).
- `Sources/BridgeLayout`: strip groups, bindings, templates (UF8, WING), calibration and edit math, persistence. No AppKit.
- `Sources/MeterRendering`: Core Animation strip/bank views.
- `Sources/MeterBridgeApp`: the executable (menu bar, panels, edit mode, hotkeys, settings).
- `AbletonRemoteScript/MeterBridge`: the Python Remote Script that runs inside Live.
- `scripts/`: build the .app bundle, install the Live script.

## Commands

```bash
swift build                                    # build everything
swift test                                     # Swift Testing suites
swift run MeterBridge                          # run the app from the command line
scripts/build-app.sh                           # build/DAW Meter Bridge.app (ad-hoc signed)
OUTPUT_DIR=<dir> SCRATCH_PATH=<dir> scripts/build-app.sh  # bundle elsewhere, e.g. while build/ is running
scripts/install-live-script.sh                 # copy the Remote Script into Live's User Library
cd AbletonRemoteScript && python3 -m unittest  # Remote Script tests (fake Live module)
```

When several agents build at once, give each its own `--scratch-path` so they don't wait on the shared `.build` lock.

## Conventions

- Swift 6 strict concurrency. UI, sources and `MeterStore` are `@MainActor`. Network callbacks hop to the main actor before touching state.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Keep AppKit out of MeterCore, BridgeProtocol, MeterSources and BridgeLayout so they stay unit-testable.
- The Remote Script must run on Live 11 (Python 3.7) and Live 12 (Python 3.11). Use only Python 3.7 syntax and stdlib (no walrus, no `match`, no PEP 604 unions). A test enforces this with `ast.parse(..., feature_version=(3, 7))`.
- The Remote Script never writes to the Live Object Model from a listener callback; it queues the change and applies it in its timer tick.
- Network sockets bind 127.0.0.1 only.
- The user's hardware facts (UF8 fader pitch 38.5 mm, WING 12+8+4 sections, displays) live in `docs/research/03-physical-layouts-and-displays.md`.
