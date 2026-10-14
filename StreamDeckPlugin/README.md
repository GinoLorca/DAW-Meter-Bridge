# DAW Meter Bridge for Stream Deck

A Stream Deck plugin with two keys: one shows or hides the meter bridge, the other shows or hides the Main (master) meter at the right edge of the bridge. The keys always show the app's real state, also when you switch from the menu or with ⌃⌥⌘M.

It runs on Stream Deck's bundled Node 24 and has no npm dependencies. It talks to the app over the control protocol in [docs/CONTROL.md](../docs/CONTROL.md) (UDP on 127.0.0.1, port 47802).

## Install

Requirements: macOS 14 or later, Stream Deck 7.1 or later (the first version that runs plugins on Node 24; it was written against 7.4.2), and a DAW Meter Bridge build that has the control protocol (the "Show Main Meter" menu item is a sign of it). Rebuild the app with `scripts/build-app.sh` if yours is older.

```bash
scripts/install-streamdeck-plugin.sh      # builds the package and opens it; click Install
```

Or build the package and install it by hand:

```bash
scripts/package-streamdeck-plugin.sh      # writes build/DAW Meter Bridge.streamDeckPlugin
open "build/DAW Meter Bridge.streamDeckPlugin"   # or double-click it in Finder
```

`OUTPUT=<file>.streamDeckPlugin` writes the package somewhere else. Installing a newer package replaces the old version: Stream Deck asks first.

To remove the plugin, select it in Stream Deck's Preferences › Plugins and uninstall it there.

## The two actions

The actions are in the **DAW Meter Bridge** category of Stream Deck's action list.

| Action | Pressing it | Key lit | Key dim |
|---|---|---|---|
| **Show/Hide Bridge** | Shows or hides the whole bridge | The bridge is shown | The bridge is hidden, or the app isn't running |
| **Show/Hide Main Meter** | Shows or hides the Main meter at the right edge of the bridge display | The Main meter is shown | The Main meter is hidden, or the app isn't running |

- **The key state comes from the app.** Pressing a key doesn't flip it. The app answers within a few milliseconds and the key follows. When something else changes the bridge (menu, hotkey, URL), the keys update too.
- **Show/Hide Bridge starts the app.** When DAW Meter Bridge isn't running, pressing it runs `open -g -b com.ginolorca.DAWMeterBridge`. The app starts in the background, so the DAW keeps keyboard focus. When the app comes up with the bridge hidden, the plugin shows it. If the app doesn't answer within 15 s, the key shows a warning triangle.
- **Show/Hide Main Meter needs the app.** When the app isn't running, the key shows a warning triangle and nothing else happens. If there's no Main meter yet, turning it on creates one along the right edge of the bridge display.
- **Multi-actions.** Both actions work in a multi-action. When you add one, Stream Deck asks which state to use: "Bridge shown" always shows, "Bridge hidden" always hides (the same goes for the Main meter). This is handy for a "mixing" key that also shows the bridge.
- **Offline.** If the app stops answering for 5 s, both keys go dim. They come back by themselves when the app is running again.

The key images carry their own labels, so the keys need no title. If you add one, it sits at the top of the key, clear of the Main key's label and the bridge key's track colours.

## Without the plugin: the URL scheme

Anything that can open a URL can drive the app. In Stream Deck, use **System › Website**, enter one of these URLs, and leave "Access in background" off. These keys don't show the app's state.

| URL | Effect |
|---|---|
| `dawmeterbridge://bridge/toggle` | Toggle the bridge |
| `dawmeterbridge://bridge/show` | Show the bridge |
| `dawmeterbridge://bridge/hide` | Hide the bridge |
| `dawmeterbridge://main/toggle` | Toggle the Main meter |
| `dawmeterbridge://main/show` | Show the Main meter |
| `dawmeterbridge://main/hide` | Hide the Main meter |
| `dawmeterbridge://edit/toggle` | Toggle edit mode |

Opening a URL starts the app if needed and never takes focus from the DAW. A toggle that starts the app shows the bridge (or the Main meter), like the plugin's key, even if the app was shown when it last quit. From Terminal: `open -g dawmeterbridge://bridge/toggle`.

## Troubleshooting

| Problem | What to check |
|---|---|
| The keys stay dim while the bridge is shown | The app must be a build with the control protocol: rebuild it with `scripts/build-app.sh`. Something else may use UDP port 47802: `lsof -nP -iUDP:47802` should list only MeterBridge. |
| Pressing Show/Hide Bridge shows a warning triangle | The app didn't start or didn't answer within 15 s. Check that macOS can find it: `open -g -b com.ginolorca.DAWMeterBridge` in Terminal. Keep one copy of the app, in /Applications or in the repository's build/ folder. |
| Pressing Show/Hide Main Meter shows a warning triangle | The app isn't running. Start it, or press Show/Hide Bridge first. |
| The actions don't appear in Stream Deck | Quit and reopen Stream Deck. Check that the plugin folder exists (below). |
| Anything else | Read the plugin log (below). |

**Logs**

- Plugin log: `~/Library/Application Support/com.elgato.StreamDeck/Plugins/com.ginolorca.dawmeterbridge.sdPlugin/logs/com.ginolorca.dawmeterbridge.0.log`. Each start begins a new file; the last 5 are kept, at most 256 KB each.
- Warnings and app online/offline changes also go to Stream Deck's own log in `~/Library/Logs/ElgatoStreamDeck/`, prefixed with `[DAW Meter Bridge]`.
- More detail: set `DAWMB_DEBUG=1` in the plugin's environment (development only).

## Development

```text
StreamDeckPlugin/
  com.ginolorca.dawmeterbridge.sdPlugin/   the plugin folder that gets packaged
    manifest.json
    bin/plugin.js            entry point: arguments, log, wiring
    bin/lib/streamdeck.js    WebSocket connection to Stream Deck (Node's built-in WebSocket)
    bin/lib/app-link.js      UDP control client: ctl.sub keep-alive, ctl commands, online/offline
    bin/lib/bridge-plugin.js key states, presses, launch-then-show
    bin/lib/launcher.js      open -g -b com.ginolorca.DAWMeterBridge
    bin/lib/logger.js        rotating log in logs/
    imgs/                    plugin, category, action-list and key images (1x and @2x PNG)
  tests/                     node:test suites, fake Stream Deck (RFC 6455 server) and fake app
  tools/check-manifest.mjs   checks the manifest and every image it names
```

Run the tests with Stream Deck's bundled Node 24:

```bash
"$HOME/Library/Application Support/com.elgato.StreamDeck/NodeJS/24.13.1/node" --test StreamDeckPlugin/tests/*.test.mjs
node StreamDeckPlugin/tools/check-manifest.mjs     # manifest and images only
```

The end-to-end tests run `bin/plugin.js` from a temporary copy of the plugin folder, against a fake Stream Deck and a fake app on ephemeral ports. They never contact the real app and never launch anything.

Environment variables (for tests):

| Variable | Effect |
|---|---|
| `DAWMB_CONTROL_PORT=<n>` | The app's control port (default 47802). |
| `DAWMB_NO_LAUNCH=1` | Never run `open`; only log what would have been launched. |
| `DAWMB_DEBUG=1` | Debug lines in the plugin log. |

Bump `Version` in `manifest.json` and `PLUGIN_VERSION` in `bin/lib/constants.js` together; a test checks that they match.
