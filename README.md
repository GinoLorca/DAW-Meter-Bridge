# DAW Meter Bridge

A macOS app that acts as a second-screen meter bridge for hardware control surfaces and DAWs. Large track meters sit on a display above the control surface, each one lined up with its physical channel strip. Clicking a meter selects, solos or mutes the track, and dragging it changes the volume, with Shift for fine control.

- **DAW:** Ableton Live 11/12. Pro Tools is planned.
- **Surfaces:** SSL UF8 (with UF1/UC1), and the Behringer WING in DAW-controller mode.
- **Following the hardware:** a small Ableton Remote Script reports which track is on each hardware strip, so the bridge stays in step when you bank.

## Status

The first version is built: the menu-bar app, a built-in simulator, the layout editor with two-point calibration, and the Ableton Remote Script. It has been tested against a simulated Live, not yet inside real Ableton Live or with the hardware.

## Quick start

```bash
scripts/build-app.sh                        # builds build/DAW Meter Bridge.app
open "build/DAW Meter Bridge.app"           # starts with the simulator
scripts/install-live-script.sh              # installs the Ableton Remote Script
```

To connect Ableton, see [AbletonRemoteScript/README.md](AbletonRemoteScript/README.md).

| Shortcut | Action |
|---|---|
| ⌃⌥⌘M | Show/hide the bridge |
| ⌃⌥⌘E | Edit layout (drag to move, Shift = fine, arrows to nudge, right-click → Calibrate…) |

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design, modules, layout model
- [docs/PROTOCOL.md](docs/PROTOCOL.md): the Live ⇄ app protocol
- [docs/research/](docs/research/): background research (DAWWAY, SSL 360°, WING, Ableton, displays)
