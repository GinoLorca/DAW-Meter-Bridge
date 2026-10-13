# macOS app stack for the meter bridge: findings

## 0. Recommendation

**Build it natively in Swift 6.** The core should be AppKit: borderless, non-activating `NSPanel` windows, with meters drawn by Core Animation and driven by a per-display `CADisplayLink`. Use SwiftUI only for Settings, the layout inspector and the menu-bar popover. Meter rendering sits behind a protocol so a Metal renderer can replace it later. CoreMIDI is used through the UMP APIs (macOS 11+), either through a thin wrapper of our own or through `orchetect/swift-midi`, which is MIT-licensed.

- **Global hotkey:** Carbon `RegisterEventHotKey`, through the `KeyboardShortcuts` package.
- **Distribution:** Developer ID, notarization and Sparkle 2.
- **App Sandbox:** turn it on from the first build. I tested it on this Mac: a sandboxed app can create virtual MIDI ports with no extra entitlement.
- **Deployment target:** macOS 14.0.
- **Project layout:** an Xcode app target plus one local Swift package containing about 8 modules. A simulator feeds fake data through the same `MeterSource` protocol the MCU, HUI and Wing backends use.

JUCE and Electron/Tauri each lose on at least one requirement that matters here (section 2).

---

## 1. Facts found on this Mac that affect the design
Checked locally with `system_profiler`, `sysctl` and a small Swift probe.

**Machine and toolchain**
- MacBookPro18,2 with an **Apple M1 Max**, running macOS **26.4.1**.
- Xcode 26.6 and Swift 6.3.3.

**Displays**
| Display | Points (scale) | Refresh | Note |
|---|---|---|---|
| LG HDR WQHD (main) | 2560×1067 pt (scale 2) | 60 Hz | |
| Built-in XDR | — | 120 Hz | |
| S27R65 | 1920×1080 (scale 1) | 75 Hz | |
| SAMSUNG | 1920×1080 | 60 Hz | `CGDisplaySerialNumber` returns **0** |
| Sidecar (AirPlay, virtual) | — | — | |

- Global display coordinates include negative origins, for example the built-in display at (−1728, −393).
- **External display limit:** Apple's spec for this model is "up to three external displays with up to 6K … and one external display with up to 4K" ([Apple tech specs](https://support.apple.com/en-us/111901)). Three physical external displays are already connected, so a bar display would be the 4th and last one the hardware supports.
- UNVERIFIED: whether Sidecar counts toward that limit.

**Installed music software**
- SSL 360 is installed and publishes virtual ports "SSL V-MIDI Port 1…12 Source/Destination".
- Also installed: **Ableton Live 11 and 12 Suite**, **Pro Tools** and SoundFlow, which publishes HUI and Ableton ports.
- So the user's DAW is probably Ableton Live or Pro Tools. This decides MCU vs HUI, which in turn decides mono vs stereo meters (section 6.4).

---

## 2. Framework comparison

### Native Swift: AppKit with SwiftUI chrome (recommended)
- **Windows on a chosen display:** full control through `NSPanel`, window levels, `collectionBehavior`, `canHide` and `hidesOnDeactivate` (section 3).
- **Rendering cost:** Core Animation layers are composited by the window server on the GPU. `CADisplayLink` runs per display (macOS 14+). Metal is available if needed.
- **Virtual MIDI:** native CoreMIDI UMP APIs. Tested in a sandbox (section 7).
- **Robust display ID:** full access to `CGDisplayCreateUUIDFromDisplayID` plus vendor, model and serial.
- **Global hotkey:** Carbon `RegisterEventHotKey`, which needs no Accessibility permission.
- **Footprint:** smallest of the three.
- **Code sharing with a meter plugin:** the plugin would be a separate C++ build (JUCE, or AUv3 in Swift for Logic only). It would talk to the app over localhost UDP/OSC, so very little code is actually shared.

### JUCE 9 (C++)
- **Windows:** `setAlwaysOnTop` only switches between floating and pop-up levels. The macOS peer sets only the FullScreenPrimary/Auxiliary collection behaviours ([juce_NSViewComponentPeer_mac.mm](https://github.com/juce-framework/JUCE/blob/master/modules/juce_gui_basics/native/juce_NSViewComponentPeer_mac.mm)). Anything else (`canJoinAllSpaces`, `stationary`, `ignoresCycle`, non-activating panels) needs Objective-C++ through `getWindowHandle()`.
- **Rendering:** CoreGraphics, or OpenGL, which Apple has deprecated. There is no first-class Metal path. JUCE 9.0.0 notes "improved the performance of the software renderer" ([release notes](https://github.com/juce-framework/JUCE/releases)).
- **Virtual MIDI:** `MidiInput/MidiOutput::createNewDevice`, available on "Linux, macOS and iOS" ([juce_MidiDevices.h](https://github.com/juce-framework/JUCE/blob/master/modules/juce_audio_devices/midi_io/juce_MidiDevices.h)).
- **Display ID and hotkey:** both need native Objective-C++ code.
- **Footprint:** medium.
- **Code sharing:** this is JUCE's one real advantage, because the same code base could build an AU/VST3 meter plugin.
- **Licence:** AGPLv3, or Starter free up to $20k revenue, Indie $800 perpetual up to $300k, Pro $3,500 ([juce.com/get-juce](https://juce.com/get-juce/)). The latest release is 9.0.3 (2026-09-28).

### Electron or Tauri
- **Windows:**
  - Electron has `setAlwaysOnTop(level)` and `setVisibleOnAllWorkspaces({visibleOnFullScreen})` ([BrowserWindow docs](https://github.com/electron/electron/blob/main/docs/api/browser-window.md)).
  - In Tauri, `macOSPrivateApi` is now a "no-op in Tauri 2.12.1+ because the APIs are always enabled" ([Tauri config](https://v2.tauri.app/reference/config/)).
  - Non-activating panels need native code in both.
- **Rendering:** Canvas/WebGL inside a web view. It works, but carries a much larger baseline CPU and memory cost. UNVERIFIED: no numbers measured.
- **Virtual MIDI:** Web MIDI cannot create virtual ports ([W3C list](https://lists.w3.org/Archives/Public/public-audio-dev/2015Nov/0001.html)), so a native addon (RtMidi) or Rust code is required.
- **Display ID:** Electron's `Display` object exposes only `id`, `label` and bounds, with no EDID UUID or serial ([display.md](https://github.com/electron/electron/blob/main/docs/api/structures/display.md)). Native code is needed.
- **Global hotkey:** built in.
- **Footprint:** largest of the three.
- **Code sharing:** none.

**Verdict:** every hard requirement maps straight onto AppKit and CoreMIDI APIs. The cross-platform options only help with a Windows port, and DAWWAY already covers Windows.

---

## 3. Window system: borderless, always on top, placed on one display

Recommended configuration. Each item is backed by Apple docs or by local tests.
```swift
final class BridgePanel: NSPanel {
  init(frame: NSRect) {
    super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    level = .statusBar                 // 25: above .mainMenu (24), so it can cover the menu-bar strip on the bar display
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    hidesOnDeactivate = false          // NSPanel default is documented as true
    canHide = false                    // survives the DAW's "Hide Others" (⌥⌘H)
    isOpaque = false; backgroundColor = .black; hasShadow = false
    isMovable = false                  // we implement our own drag/resize in edit mode
  }
  var editMode = false
  override var canBecomeKey: Bool { editMode }   // borderless windows return false by default (tested)
}
```

**What each flag does**
- `canJoinAllSpaces` makes the window appear in every Space, the way the menu bar does.
- `stationary` means Mission Control leaves the window where it is.
- `fullScreenAuxiliary` lets the window share the Space of a full-screen window.
- `ignoresCycle` keeps it out of the "Cycle Through Windows" menu item.
- Sources: [canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces), [stationary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary), [fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary), [ignoresCycle](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/ignorescycle).
- **Stage Manager (macOS 13+):** `.canJoinAllApplications` marks a window as not taking part in Stage Manager layout. It is mutually exclusive with `.primary` and `.auxiliary` ([docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)).

**Hide and focus pitfalls**
- `NSPanel.hidesOnDeactivate` defaults to true ([docs](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate)).
- `canHide` defaults to true, which means "Hide Others" pressed in the DAW would hide the bridge ([docs](https://developer.apple.com/documentation/appkit/nswindow/canhide)).
- **Click-through without stealing focus:** a `.nonactivatingPanel` does not activate the owning app ([docs](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)). Add `acceptsFirstMouse(for:) → true` on the meter views so the first click acts immediately ([docs](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:))).
  - The result: solo, mute and select clicks on the bridge do not take keyboard focus away from the DAW.
  - `becomesKeyOnlyIfNeeded` and `needsPanelToBecomeKey` decide when the panel takes keyboard focus, which is only needed in edit mode ([docs](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)).
- **Lock mode:** set `ignoresMouseEvents = true` so clicks pass through to whatever is underneath ([docs](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)).

**Menu-bar strip on the bar display.** Tested locally with invisible windows:
- A borderless window asked to sit flush with the top of the screen kept its frame exactly (maxY 1067).
- A titled window was pushed down below the 30 pt menu bar (maxY 1037).
- This matches Apple's note that `constrainFrameRect` is invoked automatically "whenever a titled NSWindow object is placed onscreen" ([docs](https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:))).
- So on a 1920×480-class bar display, a `.statusBar`-level borderless panel can use the full height.

**Coordinates and pixel precision**
- Store each rectangle **relative to its display's frame**, in device pixels as well as points, never as absolute global coordinates. Global coordinates change whenever the arrangement changes.
- Align to the device-pixel grid using `backingScaleFactor` and `backingAlignedRect`. Bar displays usually run at scale 1, where 1 pt equals 1 px.

**App type**
- Set `LSUIElement` so the app has no Dock icon ([MenuBarExtra docs](https://developer.apple.com/documentation/swiftui/menubarextra)).
- Use `ProcessInfo.beginActivity` to opt out of App Nap while meters are live.

---

## 4. Edit mode: drag, resize, Shift for fine moves, nudging, snapping

**Model.** Each `BankWindow` holds 8 strips: `origin`, `stripPitch`, `stripWidth`, `gap`, `meterHeight`, style, and `displayFingerprint`. Three banks give 24 tracks, matching DAWWAY's "24 tracks + 2 extenders" ([dawway.co.uk](https://dawway.co.uk/)).

**Dragging and resizing** (suggested design)
- Use custom `mouseDown`/`mouseDragged` handles on the edges and corners.
- With **Shift** held, multiply the delta by 0.1 and accumulate sub-pixel movement, snapping to device pixels. This follows the DAW convention the user asked for ("Shift = micro").
- **Arrow keys** move by 1 device pixel. **⌥+Arrow** moves by 10 px. All steps are configurable.
- Hold **⌘** to temporarily turn snapping off.
- Wire everything to an `UndoManager`.

**Hardware calibration**
- **Two-point calibration:** the user drags the strip 1 and strip 8 markers over the centres of the UF8 faders, and the app sets `pitch = (x8 − x1) / 7`.
- **Optional millimetre entry:** `CGDisplayScreenSize` returns the panel size in mm from EDID. Without EDID it falls back to an assumed 72 dpi ([docs](https://developer.apple.com/documentation/coregraphics/cgdisplayscreensize(_:))). Cheap EDIDs can be wrong, so offer this only as a starting point.

**Snapping**
- Bank edges snap to each other, to screen edges and to the calibrated strip grid, within a threshold of about 6–8 px.

---

## 5. Identifying displays and restoring layout presets

**APIs**
- `NSScreen.deviceDescription["NSScreenNumber"]` gives the `CGDirectDisplayID` ([docs](https://developer.apple.com/documentation/appkit/nsscreen/devicedescription)). Display IDs and screen IDs are **not stable across reconnects or reboots**. The Zed editor's macOS code notes that "screen ids are not stable" and calls the UUID stable ([source](https://git.secluded.site/zed/blob/v0.101.1/crates/gpui/src/platform/mac/screen.rs?raw=1); secondary source).
- `CGDisplayCreateUUIDFromDisplayID` and `CGDisplayGetDisplayIDFromUUID` are in the **ColorSync** framework (macOS 10.13+) ([docs](https://developer.apple.com/documentation/colorsync/cgdisplaycreateuuidfromdisplayid(_:))).
  - The UUID is derived from EDID. Two identical monitors with the same EDID get the same UUID ([Lunar developer notes](https://notes.alinpanaitiu.com/Weird%20monitor%20bugs)).
- `CGDisplayVendorNumber`, `CGDisplayModelNumber` and `CGDisplaySerialNumber` exist. Serial is 0 when the manufacturer encoded none, and is "meaningful only in conjunction with a specific vendor and product" ([docs](https://developer.apple.com/documentation/coregraphics/cgdisplayserialnumber(_:))). Serial 0 was observed here on the SAMSUNG.
- `NSScreen.localizedName` (10.15+) and `maximumFramesPerSecond` (12+) are also available.
- `CGDisplayUnitNumber` can change between login sessions ([docs](https://developer.apple.com/documentation/coregraphics/cgdisplayunitnumber(_:))).

**Matching strategy** (design)
1. Build a fingerprint from UUID, vendor, model, serial, name, pixel size, size in mm and the built-in flag.
2. Match in this order:
   1. exact UUID;
   2. vendor + model + non-zero serial;
   3. vendor + model + name + pixel size;
   4. relative position in the arrangement.
3. If the result is still ambiguous, ask the user.
4. Key each preset by an **arrangement signature**: the sorted set of fingerprints, with "best partial match" as a fallback.

**Reconnect handling**
- Observe `NSApplication.didChangeScreenParametersNotification`, which is posted on the main actor ([docs](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)).
- Optionally also register `CGDisplayRegisterReconfigurationCallback`, which fires twice per display, before and after the change ([docs](https://developer.apple.com/documentation/coregraphics/cgdisplayregisterreconfigurationcallback(_:_:))).
- Debounce for about 0.5 s. If the target display is missing, keep that bank hidden rather than dropping it onto the main display.

**Storage**
- Codable JSON in Application Support.
- With the sandbox on, this lands in the container. Observed path: `~/Library/Containers/<bundle-id>/Data`.

---

## 6. Rendering 24 stereo meters at 60–120 fps with low CPU

### 6.1 Frame timing
- `NSView.displayLink(target:selector:)` (macOS 14+) returns a `CADisplayLink` synced to the display the view is on, and "if the view is hidden, or not on any display, the callback will not be invoked" ([docs](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:))).
- `CVDisplayLink` is deprecated as of macOS 15 ([docs](https://developer.apple.com/documentation/corevideo/cvdisplaylinkcreatewithactivecgdisplays(_:))).
- `CADisplayLink` (macOS 14+) supports `preferredFrameRateRange`. `CAMetalDisplayLink` (14+) is the Metal equivalent ([CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink), [CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)).
- **The display's refresh rate is the ceiling.** Observed here: 60, 75 and 120 Hz. Most bar monitors are probably 60 Hz (UNVERIFIED), so 120 fps will only happen on ProMotion screens.

### 6.2 Renderer for v1: Core Animation
- Each bank is one layer-backed `NSView`. Each strip has:
  - a static `CAGradientLayer` per channel, revealed through a mask layer whose height changes;
  - a peak-hold line;
  - a clip LED.
- That is about 120 property writes per frame, wrapped in `CATransaction.setDisableActions(true)` so implicit animations don't run ([docs](https://developer.apple.com/documentation/quartzcore/catransaction/setdisableactions(_:))).
- **dB text:** update at roughly 10–15 Hz through `CATextLayer` or a pre-rendered glyph atlas, never every frame.
- **Idle:** pause the display link once every meter has decayed to the floor, so CPU is near zero while the transport is stopped.
- **Metal option:** keep `MeterRenderer` as a protocol so a Metal renderer (`CAMetalLayer` with instanced quads) can be added later for richer styles such as DAWWAY-like cylinder or glow meters.
- **Not recommended:** one SwiftUI view per meter updated at 60–120 Hz, because of diffing overhead. UNVERIFIED quantitatively; SwiftUI `Canvas` with `TimelineView` is fine for prototypes.

### 6.3 Threading
1. CoreMIDI calls the receive block on its own high-priority thread ([MIDIReceiveBlock](https://developer.apple.com/documentation/coremidi/midireceiveblock)).
2. Parse there, then write into a lock-protected or atomic per-track snapshot:
   - `OSAllocatedUnfairLock` is available on macOS 13+ ([docs](https://developer.apple.com/documentation/os/osallocatedunfairlock));
   - `Synchronization.Atomic` and `Mutex` need **macOS 15+** ([Atomic](https://developer.apple.com/documentation/synchronization/atomic)).
3. The display-link callback on the main thread reads the snapshot and advances the ballistics.
4. Never allocate memory or hop to the main actor for each MIDI message.

### 6.4 Data resolution limits the "dB readout"
- **MCU meters** are mono per strip and use up to 13 segments. Ardour's implementation sends `0xD0, (strip<<4)|segment`, with segment = round(deflection/115 × 13); 0xE turns overload on and 0xF turns it off ([Ardour meter.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc)).
  - Decay of about 300 ms per LED on the device side appears only in community documentation (UNVERIFIED) ([MIDIbox forum](https://forum.midibox.org/t/ledmeters-in-mackie-control-emulation/5402)).
- **HUI meters** are **stereo** with 12 segments. Level 0xC means ≥ 0 dBFS, 0xB ≥ −2, 0x9 ≥ −6, 0x5 ≥ −20, 0x1 ≥ −60 ([swift-midi-controlsurfaces StereoLevelMeter](https://github.com/orchetect/swift-midi-controlsurfaces/blob/main/Sources/SwiftMIDIControlSurfaces/HUI/HUISurfaceModel/Storage/HUISurfaceModelState%20StereoLevelMeter.swift)).
- **Consequence:** the renderer should accept float dB and interpolate between levels. Numeric readouts will be coarse. Smooth, accurate dB values would need a metering plugin or a DAW-specific API.

---

## 7. CoreMIDI in Swift (verified on this Mac, macOS 26.4.1)

### APIs
- `MIDISourceCreateWithProtocol(client, name, protocol, &src)` and `MIDIDestinationCreateWithProtocol(client, name, protocol, &dest, receiveBlock)` are available from **macOS 11.0**.
  - The system converts between protocols automatically.
  - Data is sent with `MIDIReceivedEventList`.
  - The read block runs "on a separate high-priority thread owned by Core MIDI".
  - Sources: [source](https://developer.apple.com/documentation/coremidi/midisourcecreatewithprotocol(_:_:_:_:)), [destination](https://developer.apple.com/documentation/coremidi/mididestinationcreatewithprotocol(_:_:_:_:_:)), [MIDIReceivedEventList](https://developer.apple.com/documentation/coremidi/midireceivedeventlist(_:_:)).
- **Legacy APIs:** Apple's documentation metadata, fetched 2026-10-11, lists `MIDISourceCreate`, `MIDIReceived` and `MIDIDestinationCreateWithBlock` as deprecated at "27.2", renamed to the protocol and event-list versions ([MIDISourceCreate](https://developer.apple.com/documentation/coremidi/midisourcecreate(_:_:_:))). Do not use the MIDIPacketList APIs.
- `MIDIEventListForEachEvent` (macOS 12+) can visit parsed events ([docs](https://developer.apple.com/documentation/coremidi/midieventlistforeachevent(_:_:_:))).
- Notifications for `MIDIClientCreate` arrive "on the same run loop that you created the client on" ([docs](https://developer.apple.com/documentation/coremidi/midiclientcreate(_:_:_:_:))). In testing, a client's list of endpoints did not refresh until its run loop was serviced, so **create the MIDI client on the main thread**.

### Sandbox test result
- I built an app bundle signed ad hoc with **only** `com.apple.security.app-sandbox`.
- It created "MeterBridge Test In" (destination) and "MeterBridge Test Out/TX" (source).
- A separate unsandboxed process listed both, sent data to them and received data back.
- Its home directory resolved to the sandbox container.
- **No MIDI entitlement was needed.**

### MIDI 1.0 bytes as received through a `._1_0` destination (observed)
| Sent (MIDI 1.0 bytes) | Received UMP words |
|---|---|
| `D0 1C` (MCU meter) | `20D01C00` (message type 2, group 0) |
| `90 08 7F` | `2090087F` |
| `E0 00 40` (fader) | `20E00040` |
| `F0 00 00 66 14 12 00 "Hello World" F7` | one `MIDIEventPacket` holding three 64-bit SysEx7 messages: `30160000 66141200` (start, 6 bytes) · `30264865 6C6C6F20` (continue, 6) · `3035576F 726C6400` (end, 5). F0 and F7 are stripped. |

- In the other direction, a type-3 message with status 0 ("complete") sent from our source reached a legacy listener as `F0 00 00 66 14 00 F7`.
- A lone "start" message arrived without `F7`.
- **The parser therefore must:**
  1. walk packets with `MIDIEventPacketNext`;
  2. split words by message-type size (types 0–2 are 1 word, 3–4 are 2 words, 5 is 4 words);
  3. reassemble SysEx7 per group.
- Apple's own MIDI 2 sample indexes `evtlist->packet[i]` after computing `pkt` ([article](https://developer.apple.com/documentation/coremidi/incorporating-midi-2-into-your-apps)). That is wrong for variable-length packets, so don't copy that loop.

### Port identity
- A new virtual endpoint gets a random `kMIDIPropertyUniqueID` (observed −551403020).
- Setting a fixed value with `MIDIObjectSetIntegerProperty` worked (observed 0x4D425458).
- Apple recommends reusing the last ID so other clients keep their references, and warns it may fail on a collision ([kMIDIPropertyUniqueID](https://developer.apple.com/documentation/coremidi/kmidipropertyuniqueid), [MIDISourceCreate discussion](https://developer.apple.com/documentation/coremidi/midisourcecreate(_:_:_:))). Persist one ID per port.
- **Ports for 24 tracks:** three in/out pairs, one MCU main unit plus two extenders, for example "MeterBridge MCU 1/2/3".

### Library option
- `orchetect/swift-midi` (formerly MIDIKit) is MIT-licensed, at v1.1.0 (May 2026), Swift 6 strict-concurrency compliant, and offers "identity persistence" ([repo](https://github.com/orchetect/swift-midi)).
- Its control-surfaces extension covers HUI, including a stereo meter model. MCU is not mentioned ([repo](https://github.com/orchetect/swift-midi-controlsurfaces)).
- Recommendation: use it for HUI, or write our own roughly 300-line UMP layer and MCU parser and keep them fully unit-tested.

---

## 8. Global hotkey and menu bar

**Hotkey**
- **Carbon `RegisterEventHotKey`** needs no Accessibility permission.
  - `KeyboardShortcuts` (v3.1.0, macOS 10.15+) wraps it, provides a recorder UI and is "fully sandboxed and Mac App Store compatible". Its FAQ explains why it imports Carbon ([repo](https://github.com/sindresorhus/KeyboardShortcuts)).
- **macOS 15 caveat:** an Apple engineer said Sequoia "requires that a hotkey registration use at least one modifier that is not shift or option". Apple later wrote this "has been addressed in macOS 15.2 Beta 2". A user reported in Nov 2025 that the problem had come back ([Apple forum 763878](https://developer.apple.com/forums/thread/763878); [Eternal Storms](https://blog.eternalstorms.at/2024/09/23/keyboard-shortcuts-using-option-and-or-shift-modifiers-only-no-longer-allowed-on-macos-sequoia/)).
  - **Default to a shortcut that includes ⌘ or ⌃**, for example ⌃⌥⌘M.
- **Avoid `NSEvent.addGlobalMonitorForEvents` for keys:** "Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access" ([docs](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))).
- **Permission-free alternative:** toggle the bridge from a MIDI message, such as a UF8 or UF1 user key or any learned CC or note.

**Menu bar and login**
- `MenuBarExtra` (macOS 13+) with `.window` style. An app that lives only in the menu bar quits if the user removes the extra ([docs](https://developer.apple.com/documentation/swiftui/menubarextra)). An `NSStatusItem` gives finer control.
- Launch at login with `SMAppService.mainApp` (macOS 13+) ([docs](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)).

---

## 9. Distribution, signing and sandbox

**Developer ID and notarization**
- Notarization requires a Developer ID certificate, the Hardened Runtime, a secure timestamp and no `get-task-allow`. Uploads go through `notarytool`; altool and Xcode 13 have been rejected since Nov 2023 ([Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
- macOS Sequoia removed the Control-click way of bypassing Gatekeeper for software that isn't notarized ([pxlnv](https://pxlnv.com/linklog/macos-sequoia-gatekeeper/), [Cult of Mac](https://www.cultofmac.com/864843/macos-sequoia-removes-handy-shortcut-bypass-gatekeeper-security/); secondary sources). Notarization is effectively required.

**Sandbox: feasible for every planned feature**
- **Virtual MIDI:** tested working (section 7).
- **Behringer Wing over OSC/UDP:**
  - Needs **both** `com.apple.security.network.client` and `com.apple.security.network.server`. For UDP the sandbox restricts initiation and data flow, so "Apps using UDP usually require both entitlements" ([client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client), [server](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server)).
  - **Local Network privacy (macOS 15+)** applies to every app, sandboxed or not ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)):
    - sending UDP unicast, broadcast or multicast requires access; receiving unicast does not;
    - add `NSLocalNetworkUsageDescription` to Info.plist;
    - "The multicast entitlement isn't required on macOS";
    - the first operation may be denied before the user answers the prompt, so retry;
    - command-line tools run from Terminal are allowed automatically, so a test run from Terminal will hide the prompt.
- **Hotkeys:** Carbon hotkeys work in the sandbox.
- **Updates:** Sparkle 2 (2.10.0, Sep 2026) supports sandboxed apps through `Installer.xpc`, `SUEnableInstallerLauncherService=YES` and a mach-lookup exception. Don't sign with `--deep` ([Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/)).

**Recommendation**
- Ship v1 through Developer ID with the sandbox and Hardened Runtime on. This keeps a Mac App Store release possible later.
- Leaving the sandbox would only be justified by future features such as Accessibility-based DAW scraping or Apple Events automation of the DAW.

---

## 10. Minimum macOS version
- **API floor:**
  - UMP MIDI APIs: macOS 11;
  - `MIDIEventListForEachEvent`: 12;
  - `MenuBarExtra`, `SMAppService`, `.canJoinAllApplications`, `OSAllocatedUnfairLock`: 13;
  - `NSView.displayLink`, `CADisplayLink`, `@Observable` ([docs](https://developer.apple.com/documentation/observation/observable())), `CAMetalDisplayLink`: **14**;
  - `Synchronization.Atomic` and `Mutex`: 15.
- **Recommendation: target macOS 14.0.** That covers Sonoma, Sequoia, 26 and 27. Use `OSAllocatedUnfairLock` or the swift-atomics package instead of `Synchronization`.
- **Universal build:** macOS 26 is the last release for Intel Macs, and macOS 27 is Apple-silicon only ([9to5Mac](https://9to5mac.com/2025/06/09/apple-will-end-support-for-intel-macs/), [TidBITS](https://tidbits.com/2026/07/20/the-real-system-requirements-for-os-27/)). Building universal (arm64 + x86_64) costs little while macOS 14 is the floor.

---

## 11. Project structure
```
DAW-Meter-Bridge/
  MeterBridge.xcodeproj            (or XcodeGen/Tuist spec to avoid pbxproj churn)
  App/                             app target: AppDelegate, BridgePanel, MenuBarExtra/NSStatusItem,
                                   Settings (SwiftUI), hotkeys (KeyboardShortcuts), Sparkle, SMAppService,
                                   Info.plist (LSUIElement, NSLocalNetworkUsageDescription), entitlements
  Packages/MeterBridgeKit/Package.swift   (platforms: .macOS(.v14))
    Sources/
      MeterCore/        pure Swift: TrackState (name, color, solo/mute/select/rec, level L/R, clip),
                        Bank, MixFocus rules, dB<->segment tables, Ballistics (peak hold, decay, clip latch; injected clock)
      UMP/              MIDIEventList walking, message-type sizing, SysEx7 reassembly (no CoreMIDI deps in the logic)
      ProtocolMCU/      MCU decode/encode: meters (D0), faders (pitch bend), buttons (notes), LCD SysEx, banking, handshake
      ProtocolHUI/      later (or adapter over swift-midi-controlsurfaces)
      WingOSC/          later: Network-framework UDP client
      MIDITransport/    CoreMIDI client, virtual endpoints, persisted uniqueIDs, setup-change handling,
                        lock-protected snapshot handoff
      MeterSource/      protocol MeterSource { var snapshot: BridgeSnapshot; func send(_ cmd: SurfaceCommand) }
      Simulator/        SimulatedSource + scenario engine + "virtual DAW" that emits real MCU bytes
      DisplayManager/   fingerprints, arrangement signatures, reconnect debounce, preset matching
      Layout/           Codable layout model, persistence, snapping and calibration math
      MeterRendering/   layer-based bank view + MeterRenderer protocol (Metal later), display-link driver
      LayoutEditor/     edit-mode overlay, handles, Shift-fine drag, nudging, undo
    Tests/              one test target per module (Swift Testing)
```
Dependencies point only downward: App → LayoutEditor/MeterRendering → Layout/DisplayManager → MeterSource → ProtocolMCU/UMP → MeterCore. Everything below `MIDITransport` builds and tests with `swift test`, with no app host and no hardware.

## 12. Testing
- **Framework:** Swift Testing (Swift 6 / Xcode 16+) ([docs](https://developer.apple.com/documentation/testing)). Run `swift test` in CI on macOS runners.
- **UMP and parser tests:**
  - Use the observed word vectors from section 7 as golden fixtures.
  - Add a "capture" debug mode that records real DAW to MCU/HUI traffic as JSONL, then replay those recordings into the parsers and check the resulting `TrackState`.
  - Cover banking, solo/mute/select, the LCD SysEx track names, and meter overload set and clear.
- **Ballistics tests:** use an injected clock to check peak-hold timing, decay rate and clip latch.
- **Display matching tests:** synthetic fingerprints covering identical monitors with the same UUID, serial 0, a missing display, a swapped arrangement and a scale change.
- **Integration test:** loopback through CoreMIDI. The test creates a virtual source, sends MCU bytes, and checks the app's destination model. This is the same path exercised in this research.
- **Simulator:**
  - Feeds 1–24 tracks: random-walk RMS with transients, sine sweeps, sustained clipping, silence, solo/mute/select patterns, bank switches and long names.
  - Deterministic seed and adjustable update rate.
  - Two modes: directly into the model, or as real MCU bytes through the virtual port.
  - Doubles as a "demo/setup mode" so the user can align the layout without a DAW running.
- **Performance:**
  - Use Instruments (Time Profiler, Animation Hitches) with 24 stereo tracks at 60 and 120 Hz.
  - Suggested budget: under about 5% of one core while active, near zero when idle (UNVERIFIED target).

---

## UNVERIFIED items and caveats
- That Core Animation stays under the suggested CPU budget at 24 stereo meters × 120 Hz. This is reasoning, not a measurement.
- That most bar-type monitors are 60 Hz.
- Whether Sidecar counts toward the M1 Max external display limit.
- How touch input behaves on macOS with USB touch bar-displays (likely mouse emulation, or a third-party driver).
- MCU device-side meter decay of about 300 ms per segment.
- Whether Sequoia's Option-only hotkey restriction affects only sandboxed apps (a community claim).
- Whether Apple's "27.2" deprecation metadata for the legacy CoreMIDI calls reflects a shipping SDK.
- DisplayLink USB monitors route through DisplayLink Manager, which needs Screen Recording permission ([Plugable KB](https://kb.plugable.com/en_US/why-does-macos-say-displaylink-manager-is-capturing-your-screen)). The bridge should still work, but buying a DP Alt-mode or HDMI bar display is the safer choice.

## Open questions
- Which DAW will the user run with the bridge? Ableton Live 11/12 Suite and Pro Tools are both installed on this Mac. The answer decides MCU (mono meters, 13 steps) versus HUI (stereo meters, 12 steps) and whether stereo meters are possible without a plugin.
- Does 'fine movements on the levels' while holding Shift mean moving DAW faders and volume from the bridge? That would need bidirectional MCU (pitch-bend fader messages sent back to the DAW). Or does it only mean fine positioning and resizing of the meter windows?
- Which bar display will the user buy (resolution, refresh rate, HDMI or USB-C DisplayPort versus a DisplayLink USB connection, touch or not)? The M1 Max has only one external display slot left, and DisplayLink displays need DisplayLink Manager with Screen Recording permission.
- Is the app for personal use only or for public sale? This affects the Developer ID ($99/year), Mac App Store versus direct sale, licensing and payment, and whether JUCE licensing would matter.
- Are coarse MCU/HUI meter values acceptable for the dB readouts, or should a companion metering plugin (AU/VST3, probably JUCE) send true dB values to the app over localhost UDP? UNVERIFIED: the sandbox and network constraints for such a plugin inside Logic or Pro Tools.
- Can the DAW run the bridge's virtual MCU ports (main unit plus 2 extenders) alongside the SSL 360 UF8 connection, which uses the SSL V-MIDI ports? This depends on how many control-surface slots each DAW allows. The protocol research topic should cover it.
- Minimum macOS for the intended audience: 14 Sonoma (recommended) or 15 Sequoia (which allows the native Synchronization Atomic and Mutex types). Should Intel Macs be supported with a universal build?
- Should hide/show also be mappable to a UF8, UF1 or UC1 user key over MIDI, in addition to the global hotkey and the menu bar item?
- Is touch interaction on the bar display a requirement? UNVERIFIED: how USB touchscreens behave on macOS without third-party drivers.
- Which visual meter styles are wanted for v1 (flat segmented, gradient, DAWWAY-like cylinder)? This decides whether Core Animation is enough or a Metal renderer is needed early.

## Fact-check
- **CONFIRMED**: A sandboxed macOS app (signed with only com.apple.security.app-sandbox) can create CoreMIDI virtual sources and destinations visible to other apps and exchange data with them; no MIDI-specific entitlement needed (verified on macOS 26.4.1).
  - Reproduced independently on this Mac (MacBookPro18,2, macOS 26.4.1 build 25E253, SDK 26.5). I ad-hoc signed an .app with only app-sandbox. It really was sandboxed: HOME was ~/Library/Containers/com.factcheck.fcrecv/Data and it could not list ~/Documents. MIDIDestinationCreateWithProtocol and MIDISourceCreateWithProtocol both returned 0. An unsandboxed process found 'FC Test Dest', sent to it, and received three notes sent from 'FC Test Src' via MIDIReceivedEventList. Test code: .../scratchpad/factcheck/src/recv.swift and send.swift. (https://developer.apple.com/documentation/coremidi/midisourcecreatewithprotocol(_:_:_:_:))
- **CONFIRMED**: MIDISourceCreateWithProtocol / MIDIDestinationCreateWithProtocol are macOS 11+, the system converts protocols automatically, the receive block runs on a high-priority CoreMIDI-owned thread, and the docs mark legacy MIDISourceCreate, MIDIReceived and MIDIDestinationCreateWithBlock as deprecated with these as replacements.
  - The SDK 26.5 MIDIServices.h has API_AVAILABLE(macos(11.0)) on both. Its protocol parameter says 'The system will automatically convert to this protocol as needed.' The MIDIReceiveBlock typedef says CoreMIDI 'will create a high-priority receive thread on your client's behalf'. Caveat: the deprecation is soft. The legacy calls use API_DEPRECATED_WITH_REPLACEMENT(..., API_TO_BE_DEPRECATED), so the compiler gives no warning yet. Apple's docs JSON has a deprecationSummary ('Use … instead'), a 'renamed' replacement, deprecated:false and a placeholder deprecatedAt '27.2'. (https://developer.apple.com/documentation/coremidi/mididestinationcreatewithprotocol(_:_:_:_:_:))
- **CONFIRMED**: With a MIDI 1.0 (._1_0) virtual destination, MCU traffic arrives as UMP: D0 1C becomes 0x20D01C00; SysEx arrives as 64-bit type-3 SysEx7 start/continue/end with F0/F7 stripped, packed into one MIDIEventPacket, so the parser must reassemble SysEx.
  - Reproduced: D0 1C arrived as 0x20D01C00 and 90 08 7F as 0x2090087F. A 19-byte MCU LCD SysEx arrived as one packet of 6 words: start, continue, end (0x3016…, 0x3026…, 0x3035…), with F0/F7 stripped. Caveats: (a) A SysEx with 6 or fewer payload bytes arrives as one 'complete' type-3 message (status 0, e.g. 0x30047E7F 0x06010000), not start/continue/end. (b) A 608-byte SysEx arrived as one MIDIEventPacket with wordCount 202. The header says the packet 'may be larger than 64 words', but Swift's MIDIEventPacket.words is a fixed 64-word tuple. Copying p.pointee.words silently truncates long SysEx, so read the words through a raw pointer. (https://developer.apple.com/documentation/coremidi/incorporating-midi-2-into-your-apps)
- **CONFIRMED**: Virtual MIDI endpoints get a random kMIDIPropertyUniqueID; the app should persist an ID per port and re-set it with MIDIObjectSetIntegerProperty so DAWs keep port references.
  - Reproduced: the destination got a random ID (-197431226) and the source got -678956819. Setting 0x46430001 returned 0 and read back correctly. The MIDIServices.h discussion of MIDIDestinationCreateWithProtocol recommends reassigning 'the same unique ID it had the last time'. kMIDIPropertyUniqueID says setting it 'may fail if the chosen ID is not unique' (kMIDIIDNotUnique = -10843), so handle a collision. (https://developer.apple.com/documentation/coremidi/kmidipropertyuniqueid)
- **CONFIRMED**: Bridge windows should be borderless .nonactivatingPanel NSPanels with collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle], hidesOnDeactivate = false (NSPanel default is true) and canHide = false, so they survive the DAW's Hide Others and clicks don't steal DAW focus.
  - The docs say hidesOnDeactivate defaults to false for NSWindow and true for NSPanel, and canHide defaults to true. Locally, a panel with canHide=false stayed visible after NSApp.hide() while a default panel was hidden, for both .accessory and .regular apps. Nuance: in practice, panels created with .nonactivatingPanel already defaulted hidesOnDeactivate to false. Borderless and titled panels without it defaulted to true. Setting it explicitly is still correct. A borderless NSPanel reports canBecomeKey=false. Mouse handling in an inactive app also depends on acceptsFirstMouse(for:) (UNVERIFIED here). (https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate)
- **REFUTED**: constrainFrameRect is applied automatically only to titled windows; a borderless window at .statusBar level (25, above .mainMenu at 24) can cover the menu-bar strip (borderless kept maxY 1067, titled pushed to 1037).
  - The doc does say it is invoked for 'a titled NSWindow', but on macOS 26.4.1 it is also invoked for borderless windows, and the result depends on window level. In an instrumented test, a borderless NSWindow or NSPanel at level 0 or 3 was pushed to maxY 1037 (below the 30pt menu bar). Borderless windows at .mainMenu (24) or .statusBar (25) kept 1067. A titled window at level 25 was still constrained to 1037. The practical conclusion holds: the levels are 24 and 25 per CGWindowLevel.h, and borderless at .statusBar covers the strip. The robust fix is to override constrainFrameRect(_:to:) and return the frame unchanged, which kept 1067 locally even at .floating. A level of at least .mainMenu is still needed to draw over the menu bar. (https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:))
- **CONFIRMED**: NSView.displayLink(target:selector:) (macOS 14+) returns a CADisplayLink synced to the view's display and paused when the view is hidden; CVDisplayLink is deprecated as of macOS 15, so macOS 14 is the natural deployment floor.
  - AppKit headers declare -(CADisplayLink *)displayLinkWithTarget:selector: on NSView, NSWindow and NSScreen, and the docs show macOS 14.0. The doc says the callback 'will not be invoked' if the view is hidden or not on any display. CVDisplayLink.h has API_DEPRECATED_BEGIN("use NSView.displayLink…, NSWindow.displayLink…, or NSScreen.displayLink…", macos(10.4, 15.0)). The macOS 14 floor is a design choice, not a requirement: CVDisplayLink still works when deprecated. (https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:))
- **CONFIRMED**: CGDirectDisplayID is not stable across reconnects; CGDisplayCreateUUIDFromDisplayID (ColorSync, macOS 10.13+) is stable but EDID-derived so identical monitors can share a UUID; CGDisplaySerialNumber may be 0; a multi-field fingerprint with fallbacks is needed.
  - Apple's CGDirectDisplayID doc says an ID 'typically remains constant until the machine is restarted'. It is derived from vendor, model, serial and I/O Kit registry position, so it is not guaranteed across reboots or port changes. CGDisplaySerialNumber doc: returns 0x00000000 when no serial is encoded. Observed locally on the 2013 SAMSUNG display (vendor 4c2d, model b7c, serial 0). The availability dates disagree: the ColorSync docs show macOS 10.13, but ColorSyncDevice.h says CS_AVAILABLE_STARTING(10.4). The shared-UUID point for identical monitors comes from the Lunar developer's notes (third-party), not Apple. Also note that CG global coordinates are top-left origin while NSScreen frames are bottom-left: the SAMSUNG is y=-1080 in CG and y=1067 in NSScreen here. (https://developer.apple.com/documentation/coregraphics/cgdirectdisplayid)
- **CONFIRMED**: Carbon RegisterEventHotKey (wrapped by the sandbox/MAS-compatible KeyboardShortcuts package) gives global hotkeys without Accessibility permission; macOS 15 briefly rejected Option-only and Option-Shift-only hotkeys; Apple says fixed in 15.2, later regressions were reported, so defaults should include Command or Control.
  - KeyboardShortcuts' README says it is 'fully sandboxed and Mac App Store compatible', and HotKey.swift calls RegisterEventHotKey. On the forum, an Apple engineer called the macOS 15 change intentional and later said it was 'addressed in macOS 15.2 Beta 2 (24C5073e)'. The only later report is one user post from Nov 2025, not a confirmed regression. Local test on 26.4.1, sandboxed: Option+K and Option+Shift+K register with status 0, while Shift-only+K fails with -9868 (eventInternalErr). Shift-only succeeds unsandboxed, so the restriction is sandbox-specific. Defaults that include Cmd or Ctrl remain the safe choice. (https://developer.apple.com/forums/thread/763878)
- **CONFIRMED**: NSEvent.addGlobalMonitorForEvents can monitor key events only if the app is trusted for Accessibility, so it is the wrong tool for a permission-free hide/show hotkey.
  - The docs say: 'Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access', and the handler is not called for events sent to your own app. (https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))
- **CONFIRMED**: UDP to a Behringer Wing from a sandboxed app needs both network.client and network.server; since macOS 15 Local Network privacy applies (user approval + NSLocalNetworkUsageDescription), the multicast entitlement isn't required on macOS, and Terminal-launched tools are auto-allowed, hiding the prompt during testing.
  - Local sandbox test over loopback, which avoids the LAN privacy prompt: with client only, sendto succeeded but recv of the reply failed with EPERM and bind failed with EPERM. With server only, sendto failed with EPERM. With both, the full round trip worked. DTS (forum thread 72620) gives the same advice for UDP. TN3179 says local network privacy was introduced on macOS at WWDC24, i.e. macOS 15. It covers outgoing traffic to LAN, broadcast and multicast addresses and tells you to add NSLocalNetworkUsageDescription. It also says 'The multicast entitlement isn't required on macOS' and that command-line tools run from Terminal or SSH are allowed automatically. Extra caveat: the system 'may deny the operation immediately, before the user has responded', so Wing discovery needs a retry or a Network-framework waitsForConnectivity path. (https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- **CONFIRMED**: Direct distribution needs Developer ID signature, Hardened Runtime, secure timestamp and notarization via notarytool; Sparkle 2 supports sandboxed apps via its Installer XPC service with SUEnableInstallerLauncherService.
  - Apple's notarization page lists Developer ID signing, Hardened Runtime, a secure timestamp, no get-task-allow and the 10.9+ SDK. altool and Xcode 13 have not been accepted since Nov 1, 2023 (use notarytool). Incomplete on Sparkle: besides SUEnableInstallerLauncherService=YES, its sandboxing doc also requires a com.apple.security.temporary-exception.mach-lookup.global-name array containing $(PRODUCT_BUNDLE_IDENTIFIER)-spks and -spki, unless Sparkle is built with the Installer Connection and Status XPC services. SUEnableDownloaderService is only needed when the app lacks network.client. Do not sign with --deep. (https://sparkle-project.org/documentation/sandboxing/)
- **CONFIRMED**: JUCE (now 9.0.3) is AGPLv3 or Starter free up to $20k, Indie $800 up to $300k, Pro $3,500; its macOS peer sets only full-screen collection behaviours and always-on-top uses only floating or pop-up levels, so the required behaviours need Objective-C++ either way.
  - The GitHub releases API shows 9.0.3 published 2026-09-28. juce.com/get-juce lists Starter free up to $20k, Indie $40/mo or $800 perpetual up to $300k, Pro $175/mo or $3,500 perpetual, and says JUCE is dual-licensed with AGPLv3. In juce_NSViewComponentPeer_mac.mm, getCollectionBehavior returns only FullScreenPrimary or FullScreenAuxiliary, and setAlwaysOnTop uses NSPopUpMenuWindowLevel or NSFloatingWindowLevel. Also, JUCE's window class is an NSWindow subclass (JuceNSWindowClass), not an NSPanel, so .nonactivatingPanel is not available without custom native code. (https://github.com/juce-framework/JUCE/blob/master/modules/juce_gui_basics/native/juce_NSViewComponentPeer_mac.mm)
- **CONFIRMED**: MCU meters are mono with up to 13 segments per strip (0xD0, strip<<4 | level; 0xE/0xF set/clear overload); HUI meters are stereo with 12 segments (0xC = >=0 dB down to 0x1 = >=-60 dB); protocol dB is coarse and fine dB needs a plugin or DAW-specific API.
  - Ardour's meter.cc sends 0xD0 with (id<<4)|segment, uses 0xE for overload on and 0xF for off, and computes segment = lrintf(def/115*13), so up to 0xD. REAPER's csurf_mcu.cpp also sends up to 0xD and comments '0xe turns on clip indicator, 0xf turns it off'. Ableton's MackieControl script uses int(value*12), i.e. 0x0–0xC. So expect 0x0–0xD in the wild. The UF8 manual describes '12-segment track metering + clip'. The HUI table (A0 0y sv; s = side; v 0x1 = ≥-60 dB … 0xC = ≥0 dB/clip, 0x0 = off) comes from a reverse-engineered document (theageman), not an official Mackie spec. It says 'dB', not 'dBFS'. (https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc)
- **CONFIRMED**: The user's Mac is an M1 Max MacBook Pro (macOS 26.4.1) supporting at most 3 external displays at 6K plus 1 at 4K; three external displays are already connected, so a bar display would use the last slot (Sidecar is a separate virtual AirPlay display).
  - Locally, hw.model is MacBookPro18,2, i.e. the 16-inch 2021 model that support article 111901 covers, on macOS 26.4.1 (25E253). The connected external displays are LG HDR WQHD (main, 2560x1067 points), Samsung S27R65 and a 2013 SAMSUNG. Sidecar shows Connection Type: AirPlay, Virtual Device: Yes. Caveat: Apple's port spec gives the 4K slot to the HDMI port. If the HDMI port is already used by one of the current monitors (LG and SAMSUNG both report 'Television: Yes', which often indicates HDMI; UNVERIFIED), the bar display must go on a Thunderbolt port instead. Whether Sidecar counts against the hardware limit is UNVERIFIED. (https://support.apple.com/en-us/111901)

### Missed points
- The app has to sit in the middle of the MIDI connection. CoreMIDI has no API to listen in on traffic between the DAW and SSL 360's ports. The UF8 manual says SSL 360 exposes 'SSL V-MIDI Port N' (Layer 1 = ports 1-4, one per UF8; Layer 2 = 5-8; Layer 3 = 9-12). The DAW's MCU/HUI device must therefore point at the bridge's virtual ports, and the bridge forwards traffic both ways to and from the SSL V-MIDI ports. DAWWAY works the same way ('DAW → Dawway → Control Surface'; see dawway.co.uk).
- 24 tracks with one UF8: one UF8 is one MCU device, so the DAW only sends meters for the 8 banked strips. To show 24 tracks, the bridge must emulate two extra MCU extender devices. That means device ID 0x15 and the Logic Control challenge/response handshake (query 0x00, challenge 0x01, reply 0x02, confirm 0x03), as implemented in Ardour's surface.cc. The DAW then banks those devices separately from the UF8.
- MCU meter decay happens on the surface, so the bridge must do it. REAPER's csurf_mcu.cpp only sends rising values and models the hardware falloff ('they claim 1.8s for falloff'). Without local decay, meters freeze at their peaks.
- Whether the DAW sends meters at all depends on the DAW. Ardour enables meters with the 0x20 channel-meter SysEx and only sends them while the transport is rolling, unless the device has separate meters. Ableton's MackieControl script only meters in certain assignment modes (from decompiled code, so less reliable). The bridge may show nothing when stopped, so plan a plugin or DAW-API fallback.
- Pro Tools drives the UF8 over HUI, which has stereo meters and a ping/keepalive. Logic, Cubase/Nuendo, Live and Studio One use MCU (UF8 manual). SSL's Plug-in Mixer uses a proprietary protocol and VST3 extensions, so the bridge cannot see that data. Logic Pro is not on DAWWAY's tested-DAW list, so there is no prior art for it. Whether Logic's MCU auto-scan grabs both the bridge ports and the SSL V-MIDI ports is UNVERIFIED.
- Behringer Wing DAW control is MCU or HUI emulation over USB MIDI or DIN5 (Wing manual: SETUP → DAW → CONNECTION and EMULATION). DAW meters on the Wing therefore follow the same MIDI path as the UF8. The UDP/OSC protocols (OSC on 2223; native protocol on 2222 TCP/UDP with meters on UDP channel #3; discovery by sending 'WING?' to UDP 2222, per Maillot's 'WING Remote Protocols' v3.0.6) only expose the console's own mixer, not the DAW's.
- Window coordinates: CGDisplayBounds uses a global top-left origin, while NSScreen.frame and NSWindow use bottom-left. Saved layouts should be stored relative to a matched display, not as raw global coordinates.
- On macOS 26.4.1, sandboxed apps cannot register Shift-only global hotkeys (RegisterEventHotKey returns -9868), while Option-only and Option+Shift now register fine.
- CoreMIDI callbacks run on a real-time thread. Parse there into a lock-free buffer and render meters on the display-link or main thread. MIDIEventPacket must always be accessed by pointer (header: 'variable-length struct').
- Process note: the web search budget ran out partway through this check. The rest was verified by fetching primary URLs directly (Apple docs JSON, GitHub raw, juce.com, sparkle-project.org), reading local SDK 26.5 headers, using the researcher's downloaded manuals, and running local tests whose code is in .../scratchpad/factcheck/src/.
