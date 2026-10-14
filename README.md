# DAW Meter Bridge

A macOS app that acts as a second-screen meter bridge for hardware control surfaces and DAWs. Large track meters sit on a display above the control surface, each one lined up with its physical channel strip. Clicking a meter selects, solos or mutes the track, and dragging it changes the volume, with Shift for fine control.

- **DAW:** Ableton Live 11/12. Pro Tools is planned.
- **Surfaces:** SSL UF8 (with UF1/UC1), and the Behringer WING in DAW-controller mode.
- **Following the hardware:** a small Ableton Remote Script reports which track is on each hardware strip, so the bridge stays in step when you bank.
- **Main meter:** the Main (master) track's meter at the right edge of the bridge display, straight from Live. Switch it on and off from the menu or a Stream Deck key.
- **Stream Deck:** keys that show and hide the bridge and the Main meter, and light up with the app's real state.

## Status

Version 0.2.0. It works with Ableton Live 12 and an SSL UF8 on an LG ultrawide, and its dB readouts are calibrated to Live 12's meters. The WING profile has not been tried on the console yet.

## Quick start

```bash
scripts/build-app.sh                        # builds build/DAW Meter Bridge.app
open "build/DAW Meter Bridge.app"           # starts with the simulator
scripts/install-live-script.sh              # installs the Ableton Remote Script
scripts/install-streamdeck-plugin.sh        # installs the Stream Deck plugin (optional)
```

To connect Ableton, see [AbletonRemoteScript/README.md](AbletonRemoteScript/README.md). For the Stream Deck keys, see [StreamDeckPlugin/README.md](StreamDeckPlugin/README.md).

| Shortcut / menu item | Action |
|---|---|
| ⌃⌥⌘M | Show/hide the bridge |
| ⌃⌥⌘E | Edit layout (drag to move, Shift = fine, arrows to nudge, right-click → Calibrate…) |
| Show Main Meter | Show/hide the Main track meter at the right edge of the bridge display |

The menu-bar icon is a small meter bridge, five segmented LED meters on a rail. They are lit at uneven levels while the bridge is shown, only the bottom LEDs light while Live isn't connected, and all are unlit while the bridge is hidden.

## Control from Stream Deck, Shortcuts and scripts

The Stream Deck plugin talks to the app over UDP on `127.0.0.1:47802`. Anything that can open a URL can use these too:

| URL | Effect |
|---|---|
| `dawmeterbridge://bridge/toggle`, `…/show`, `…/hide` | Show/hide the bridge |
| `dawmeterbridge://main/toggle`, `…/show`, `…/hide` | Show/hide the Main meter |
| `dawmeterbridge://edit/toggle` | Edit layout on/off |

Opening a URL starts the app if needed and never takes keyboard focus from Live. Details are in [docs/CONTROL.md](docs/CONTROL.md).

| Port (127.0.0.1, UDP) | Who listens | For |
|---|---|---|
| 47800 | the app | state and meters from the Live script |
| 47801 | the Live script | commands from the app |
| 47802 | the app | the Stream Deck plugin (`--control-port` changes it) |

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design, modules, layout model
- [docs/PROTOCOL.md](docs/PROTOCOL.md): the Live ⇄ app protocol
- [docs/CONTROL.md](docs/CONTROL.md): the control protocol and URL scheme (Stream Deck)
- [docs/research/](docs/research/): background research (DAWWAY, SSL 360°, WING, Ableton, displays)
