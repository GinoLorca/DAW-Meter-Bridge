# App control (v1): Stream Deck plugin and URL scheme

DAW Meter Bridge can be controlled from outside the app in two ways:

1. **The control protocol.** UDP/JSON on localhost. The Stream Deck plugin uses it so its keys can switch the bridge and the Main meter **and** always show their real state, even when the user toggles them from the menu or a hotkey.
2. **The `dawmeterbridge://` URL scheme.** Fire-and-forget commands for anything that can open a URL: Stream Deck's built-in *Open* or *Website* actions, Shortcuts, scripts.

Both drive the same two switches:

| Switch | Meaning | Same as |
|---|---|---|
| `bridge` | The whole bridge is shown (true) or hidden (false) | Menu "Show/Hide Bridge", ⌃⌥⌘M |
| `main` | The Main track meter group at the right edge of the bridge display is shown | Menu "Show Main Meter" |

The two switches are independent. While `bridge` is false nothing is drawn, but `main` keeps its value.

## Control protocol

**Transport**
- UDP on `127.0.0.1` only.
- The app listens on **47802**. `--control-port <n>` changes this, for tests.
- One compact JSON object per datagram, under 2 KB. Every message has `"v": 1` and `"t"`. Unknown fields are ignored. Messages with another `v` or an unknown `t` are dropped.

**Subscribing**
- A client (such as the Stream Deck plugin) binds its own UDP port on 127.0.0.1. It sends `ctl.sub` from that port at once and then every **2 s** as a keep-alive.
- The app keeps every client that sent a `ctl.sub` in the last **6 s**, up to 8 of them.
- The app replies to each `ctl.sub` with `ctl.state`. It also sends `ctl.state` to every live client whenever any field changes, or a client's command was handled.

### Client → app

```json
{"v":1,"t":"ctl.sub","port":51234,"client":"streamdeck"}
{"v":1,"t":"ctl","op":"bridge","on":null}
{"v":1,"t":"ctl","op":"bridge","on":true}
{"v":1,"t":"ctl","op":"main","on":false}
```

| Field | Meaning |
|---|---|
| `port` (`ctl.sub`) | Where the app sends `ctl.state`. |
| `client` (`ctl.sub`) | Free text for logs. |
| `op` (`ctl`) | `"bridge"` or `"main"`. |
| `on` (`ctl`) | `true` = show, `false` = hide, `null` or absent = toggle. |

- A `ctl` command is answered with `ctl.state` to the sender's address, whether or not it subscribed, and the change is pushed to every subscriber. A subscribed sender gets one `ctl.state`, not two.
- A `ctl` with an unknown `op` (including `"edit"`), or an `on` that is not `true`, `false` or `null`, is dropped without an answer.
- **The Main meter** is every group of the active profile bound to the main track. `main` is true when any of them is visible and at least partly on its display; showing and hiding switch all of them (showing also moves one that is entirely off its display back onto it), and hiding keeps their place, so the meter comes back where the user left it. Each switch is one undo step in the app and is saved.
- **When the Main meter has no group yet**, `{"op":"main","on":true}` creates one. It goes along the right edge of the display that holds the active profile's first visible group, at the same height and vertical position as that group. The same applies to a toggle that turns the meter on.
  - It is about 1.5 times that group's strip pitch wide (90 pt when there is no group to measure), at most a quarter of the display's width, 8 pt from the display's right edge, snapped to whole pixels.
  - If another group already reaches into that spot, the meter narrows to the free space beside it, down to 40 pt. If even that doesn't fit, it goes just above the group when there is room; otherwise it stays at the right edge, overlapping the group, to be moved in Edit Layout.
- **Moving the bridge** to another display (menu "Move Bridge to…") puts the Main meter back at that display's right edge by the same rules, shown or hidden as it was.

### App → client

```json
{"v":1,"t":"ctl.state","bridge":true,"main":true,"edit":false,"source":"live","connected":true,"app":"0.2.0"}
```

| Field | Type | Meaning |
|---|---|---|
| `bridge` | bool | The bridge is shown. |
| `main` | bool | The Main meter group exists, is visible and is at least partly on its display in the active profile. It doesn't account for `bridge`. |
| `edit` | bool | Edit mode is on. |
| `source` | string | `"live"` or `"simulator"`. |
| `connected` | bool | The source is connected. Always true for the simulator. |
| `app` | string | App version. |

**Clients must**
- treat a missing field as unknown,
- consider the app **offline** after 5 s without a `ctl.state` (they get one every 2 s in reply to their keep-alive),
- tolerate an app restart: just keep sending `ctl.sub`.

## URL scheme

| URL | Effect |
|---|---|
| `dawmeterbridge://bridge/toggle` | Toggle the bridge |
| `dawmeterbridge://bridge/show` | Show the bridge |
| `dawmeterbridge://bridge/hide` | Hide the bridge |
| `dawmeterbridge://main/toggle` | Toggle the Main meter |
| `dawmeterbridge://main/show` | Show the Main meter |
| `dawmeterbridge://main/hide` | Hide the Main meter |
| `dawmeterbridge://edit/toggle` | Toggle edit mode |

- `dawmeterbridge://edit/show` and `dawmeterbridge://edit/hide` work too. Scheme and path are case-insensitive, and a trailing slash, query or fragment is ignored.
- Opening a URL launches the app if it isn't running, then applies the command. A toggle that launches the app shows (the bridge or the Main meter), like the plugin's key, even when the app restores it as shown.
- Opening a URL never activates the app or takes keyboard focus from the DAW. The one exception: when you are working in the app's Settings window (or one of its alerts) as the URL arrives, that window keeps the keyboard. A Settings window left open behind the DAW doesn't.
- Unknown paths are ignored and logged.

## Stream Deck plugin

The plugin `com.ginolorca.dawmeterbridge` lives in `StreamDeckPlugin/com.ginolorca.dawmeterbridge.sdPlugin` and runs on Stream Deck's bundled Node 24, with no npm dependencies. It has two key actions:

| Action UUID | Key | State 0 | State 1 |
|---|---|---|---|
| `com.ginolorca.dawmeterbridge.bridge` | Show/hide the bridge | bridge hidden (unlit meters) | bridge shown (lit meters) |
| `com.ginolorca.dawmeterbridge.main` | Show/hide the Main meter | Main meter hidden | Main meter shown |

**Behavior**
- **States follow the app.** Both actions set `DisableAutomaticStates`, so the key state always comes from `ctl.state`.
- **Pressing a key** sends the matching `ctl` toggle. Inside a multi-action, where the user picks the key's state, it sends that state as an explicit `"on":true` or `"on":false` instead.
- **If the app is offline:**
  - Pressing **bridge** launches the app with `open -g -b com.ginolorca.DAWMeterBridge` (`-g` keeps the DAW in front). The press means "turn the bridge on", so when the first `ctl.state` arrives within 15 s with `bridge: false`, the plugin sends `{"op":"bridge","on":true}` once. If the app never comes online, the key shows an alert.
  - Pressing **main** shows a Stream Deck alert.
- **While offline**, both keys show state 0.
  - At startup the plugin doesn't wait the full 5 s: if its first `ctl.sub` gets no answer within 1.5 s, the app counts as offline.
  - The manifest lists the app's bundle id in `ApplicationsToMonitor`. When Stream Deck reports that the app quit, the keys go to state 0 at once; when it reports that the app started, the plugin sends `ctl.sub` every 500 ms until the app answers (for up to 15 s).
