# Mac Meter Bridge for SSL UF8 (and Behringer WING): Technical Brief

**Audience:** the user (producer, macOS) and the engineer who will build it
**Date:** 2026-10-11
**Repo:** `~/Documents/Cowork Playground/DAW-Meter-Bridge` (currently README + .gitignore only)

**What we observed on this Mac** (read-only inspection during research):
- **Hardware:** MacBook Pro M1 Max (MacBookPro18,2), macOS 26.4.1. Three external displays are already connected.
- **DAWs and tools installed:** Ableton Live 11 and 12 Suite (12.4.6), Pro Tools 24.6.0, FL Studio 2025, SSL 360 **2.0.6.67265**, WING-Edit 3.3.0 and SoundFlow. Logic, Cubase and Reaper are **not** installed.
- **Live's current setup:** Live 12's log shows control surface slot 1 = `MackieControl` on "SSL V-MIDI Port 1 Source/Destination". Slots 4–6 are `MackieControlXT` with no ports assigned.
- **SSL 360 setup:** SSL 360's log shows Layer 1 = Ableton Live MCU.
- **Behringer WING:** a class-compliant USB MIDI device named "WING" was seen (offline at the time). That name suggests a full-size WING; this is UNVERIFIED.
- **Working assumption:** the main DAW is **Ableton Live 12**, with Pro Tools second. The user still needs to confirm this (section 8).

---

## 1. What DAWWAY is, how it works, and what a Mac version must match

### 1.1 Facts

**Product**
- DAWWAY Lite is a Windows desktop app written by Ian Walker. It is not a plugin. Evidence:
  - It ships as a .NET Framework 4.5 ClickOnce app. The manifest is `DAWWAY_V2.application`, v1.0.0.58, MSIL ([manifest](https://dawway.co.uk/DAWWAY_V2.application), [download page](https://dawway.co.uk/DAWWAY-lite.html)).
  - None of its code can be ported to macOS.
- **Price:** Lite is free ([Lemon Squeezy, $0](https://dawway.lemonsqueezy.com/)). Free registration unlocks 24 tracks, meaning one surface plus 2 extenders ([dawway.co.uk](https://dawway.co.uk/)).
- **Pro edition:** announced but not released. It is meant to add track names and labels, analogue meters, theming, long names, marker buttons and automatic track numbering. Status is UNVERIFIED.

**How it gets its data: a transparent MIDI pass-through**
- The signal chain is DAW → DAWWAY → surface. DAWWAY "sits in between the two from a midi perspective" ([forum t17](https://dawway.forumotion.com/t17-introduction-to-dawway)).
- Each 8-strip unit gets one virtual port pair, `WAY_IN_n`/`WAY_OUT_n`. On Windows these are created with loopMIDI, Bome or LoopBe ([t43](https://dawway.forumotion.com/t43-creating-virtual-midi-ports-for-dawway)).
- In the DAW, the surface's normal MCU script is pointed at those ports. That includes vendor dialects: the Ableton guide's screenshot uses the "Icon V and P Series" script ([t19](https://dawway.forumotion.com/t19-setting-up-dawway-to-work-with-ableton), [t21 Cubase](https://dawway.forumotion.com/t21-setting-up-dawway-to-work-with-cubase-nuendo)).
- DAWWAY then forwards everything to the real surface ports. On the way it reads:
  - MCU meters (`D0 sv`)
  - solo, mute, select and rec LED notes
  - LCD SysEx

  The demo video ([video, 12 Feb 2026](https://www.youtube.com/watch?v=QI_99Q6Yizg)) is shown on an **SSL UF8**.
- **It also sends commands into the DAW stream.** These are fine-resolution "micro fader" moves and "Full Bank Up/Down" buttons that bank by the full width, e.g. 16 tracks for 16 strips ([screenshot](https://dawway.co.uk/screenshot-3.png)). How the bank command is sent on the wire is UNVERIFIED.
- **Private SysEx extension** `F0 7D 44 57 <cmd>`: 01 = full track name, 02 = marker list, 10/11 = colours (proposed). It also uses CC#100/101 for markers. These are sent by a DAW-side script (an FL Studio script is the reference) on a separate loopback port ([t40](https://dawway.forumotion.com/t40-long-file-names), [t41](https://dawway.forumotion.com/t41-marker-go-to-buttons-in-dawway-ui), [t46](https://dawway.forumotion.com/t46-dawway-sysex-extension-command-0x11-bank-color-burst)).
  - Note that `0x7D` is the MIDI "non-commercial" manufacturer ID, so it is not appropriate for a product that will be sold.
- **Meter fidelity is MCU-limited.** That means about 13 levels, mono, per strip. DAWWAY's screenshots repeat the same quantised peak readouts (−1.7, −2.9, −7.0 dB), and both columns of each "stereo" meter are always the same height.
- **Some DAWs don't send meters by default.** DAWWAY itself says: "Host-dependent. Some DAWs do not emit meters by default" (t40).

**Coverage**
- **Surfaces:** it lists SSL UF1, UF8, Nucleus and **Behringer WING**. The **UC1 is not listed**.
- **DAWs:** Logic and Pro Tools are unsupported. The developer's Logic note reads: "Requires Multi-platform development though use of RTP-Midi may be a possibility" ([t37](https://dawway.forumotion.com/t37-dawway-lite-release-countdown)).
- **No Mac version exists**, and no Mac product combines a surface-aligned layout, an MCU proxy and surface-driven mix focus:
  - [Evergreen Meter Bridge Pro](https://evergreen.audio/pages/documentation) is plugin-fed and does not know about the control surface.
  - Kaizen PRISM is plugin-fed as well.

### 1.2 Feature parity: what the Mac version must match, and where it can do better

| Capability | DAWWAY Lite (Win) | Mac version | Phase |
|---|---|---|---|
| One "bank window" per 8-strip unit, freely placed on any display, layout saved | Yes | Yes. Strip groups can be any size, which the WING's 12/8/4 layout needs | P0/P1 |
| Multi-monitor / ultrawide | Yes | Yes | P1 |
| Touchscreen | Yes | How USB touch works on macOS is UNVERIFIED | P4 |
| Segmented "Standard" meter, peak hold, clip | Yes | Yes | P1 |
| "Cylinder" style, animation controls, "fireworks" | Yes | Later, with a Metal renderer | P4 |
| Mix Focus: solo highlight, solo/cut dimming 10–90%, selected indicator | Yes | Yes. Exact solo-implied muting arrives with the Live API | P1 / P2 |
| Peak alert when a track beats its previous maximum | Yes | Yes | P1 |
| Click to solo/mute/select from the bridge | Not documented | Yes, by sending MCU button presses | P1 |
| Bank up/down buttons on the bridge | Yes | Yes | P1 |
| Fine fader moves from the bridge | Yes; the trigger is UNVERIFIED | Yes: drag with **Shift = fine** | P1b |
| Track names | No (shows a placeholder) | 7-char MCU names in P1; full names in P2 | P1 / P2 |
| Track colours | Pro only (planned) | Yes, through the Live API | P2 |
| Hi-res stereo meters, accurate dB readout | No (MCU only) | Yes, through the Live API | P2 |
| 24 tracks | Only with 3 physical units | With 1–3 UF8s, or with 1 UF8 plus 16 "context" strips from the Live API | P1 / P2 |
| Logic, Pro Tools | No | Pro Tools (HUI + PTSL) in P3; Logic through generic MCU | P3 |
| Hide/show the bridge | Not documented | Global hotkey, menu bar, optional MIDI-learned key | P0 |

---

## 2. How the SSL UF8, UF1 and UC1 reach the DAW, and how to stay in sync with the UF8's bank

### 2.1 Signal path

```
UF8/UF1/UC1 --USB (vendor-specific, FTDI D2XX; VID 0x31E9)--> SSL360Core
SSL360Core <--> "SSL V-MIDI Port N Source/Destination" (app-owned virtual CoreMIDI endpoints) <--> DAW
```

**The hardware is not class-compliant.** SSL360Core drives it through the bundled `ssld2xx.dylib`/`libFtdiUnixHelper` (local inspection). Consequences:
- The bridge **cannot talk to the units directly**.
- SSL 360 must be running.
- Everything goes through the V-MIDI ports.

**Port map.** Sources: [SSL: UF8 DAW compatibility](https://support.solidstatelogic.com/hc/en-gb/articles/4410043451537-UF8-DAW-Compatibility), [UF8 User Guide](https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide.pdf), and the local SSL 360 log ("set 1 to Ableton Live Master; 2/3/4 to Ableton Live Extender").

| Layer | UF8 #1 | UF8 #2 | UF8 #3 | UF8 #4 |
|---|---|---|---|---|
| Layer 1 | Port 1 | 2 | 3 | 4 |
| Layer 2 | 5 | 6* | 7* | 8* |
| Layer 3 | 9 | 10* | 11* | 12* |

\* Inferred by analogy; UNVERIFIED.

- A **UF1** uses the layer's first port (1, 5 or 9). That is why the UF1 and UF8 stay in sync by default.
- Making them independent in Logic requires separate layers and groups ([SSL](https://support.solidstatelogic.com/hc/en-gb/articles/11252527531037-How-to-make-UF1-and-UF8-act-as-independent-control-surfaces-in-Logic-Pro)).

**Which protocol each DAW profile uses.** Source: the [SSL FAQ](https://support.solidstatelogic.com/hc/en-gb/articles/4408132094865-Which-DAWs-work-with-UF8-UF1), plus the profile names found inside the SSL360Core binary.
- **HUI:** Pro Tools.
- **MCU:** Logic, Cubase/Nuendo, Live, Studio One, LUNA, Pyramix, REAPER, Mixbus.
- **Probably MCU, UNVERIFIED:** Bitwig, Digital Performer, FL Studio, Samplitude.
- **Not supported:** Cakewalk.
- **Plug-in Mixer layer:** SSL's proprietary protocol over VST3 extensions, **not MIDI**. While the UF8 is on that layer, the bridge sees nothing.

**What is not in the MIDI stream**
- With SSL 360 v2.1.12+ and Pro Tools 2025/2026, the 8-character Pro Tools names and colours come from SSL 360 through Avid's **PTSL**, not from HUI ([SSL](https://support.solidstatelogic.com/hc/en-gb/articles/38295880789789-Which-versions-of-Pro-Tools-and-SSL-360-are-required-to-access-the-enhanced-UC1-UF8-UF1-DAW-integration-features)).
- SSL Meter Pro data shown on the UF1 travels over SSL's plug-in link, so the bridge cannot see it.

**UF8 metering**
- The guide describes "12-segment track metering + clip". Two of the reports read the guide; the verifier could not re-fetch it.
- The DAW's MCU/HUI stream supplies these meters.
- SSL documents a bug where meters and clip indicators stick on bank changes with no audio, "inherited from the MCU and HUI protocols" ([UF8 FAQ](https://support.solidstatelogic.com/hc/en-gb/articles/4404925512605-UF8-FAQs)). The bridge must therefore decay and clear meters itself.

**UF1 and UC1**
- **UF1:** one fader. It follows strip 1 of the current bank, or the master in MCU DAWs ([UF1](https://www.solidstatelogic.com/products/uf1)). If the bridge proxies Port 1, the UF1 comes along automatically, because it shares that port. How SSL 360 merges the UF1 and UF8 on Port 1 is UNVERIFIED.
- **UC1:** controls only 360-enabled and [360 Link](https://solidstatelogic.com/products/ssl-360-link) plug-ins, through the Plug-in Mixer. It plays no part in MCU banking. For the UC1, "compatible" means "the bridge doesn't break it", which is true by design.

### 2.2 What a third-party app can see

The SSL V-MIDI endpoints are **virtual endpoints owned by SSL360Core** (verified locally).
- **UF8 → DAW traffic:** any app can open the **"Source"** endpoints and read it (fader moves, touches, buttons).
- **DAW → UF8 traffic:** meters, names and LEDs are sent to SSL 360's **"Destination"**. Only SSL 360 can read that with normal CoreMIDI calls. There are three ways around this:

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Transparent proxy** (DAWWAY's design) | The DAW's MCU/HUI slot is pointed at the bridge's virtual ports. The bridge forwards every byte both ways to SSL V-MIDI Port N. | Exact mirror of the UF8 for every MCU and HUI DAW. Lets the bridge send clicks, banks and faders. Works in the App Sandbox (virtual MIDI tested sandboxed). | The UF8 goes dead if the bridge quits. One-time port reassignment in the DAW. SSL doesn't support it. Can't tell which layer the UF8 is on (UNVERIFIED). |
| **B. Passive spy driver** | A CoreMIDI CFPlugin calls `MIDIDriverEnableMonitoring` and so receives "every outgoing MIDI packet, to all destinations" ([MIDIDriverInterface](https://developer.apple.com/documentation/coremidi/mididriverinterface); prior art: [SnoizeMIDISpy, BSD-3](https://github.com/krevis/MIDIApps)). | No change to the DAW setup, and the bridge isn't in the UF8's path. | Plugin runs inside MIDIServer. Can't be sandboxed or sold on the App Store. Legacy driver model. Packets can arrive out of order. **Not yet tested on SSL's app-owned virtual destinations (UNVERIFIED).** Read-only, so no clicks or faders. |
| **C. DAW-native extenders** | The bridge registers as extra MCU XT or HUI units. | No proxy needed. | In Live, Logic and Pro Tools these show the **adjacent** 8 tracks, not the UF8's own, and they **change the UF8's BANK step** (8 → 24). In REAPER an MCUEX at offset 0 mirrors exactly ([csurf_mcu.cpp](https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)). |

**MCU sends no bank-offset message.** Live and Logic never transmit "you are on tracks 17–24"; REAPER is the exception, writing it to the 2-digit display. Any DAW-API data therefore has to be lined up with the UF8 by **inference** (section 5.4).

### 2.3 Bank-sync recommendation per DAW

| DAW (on this Mac?) | Mirror the UF8's 8 strips | Extra strips (9–24) | Hi-res / colour source |
|---|---|---|---|
| **Ableton Live 12 (yes)** | Proxy on Port 1 | **Live Object Model (LOM) via a bridge Remote Script.** Do not add XTs: they turn the UF8 bank step into 24. | LOM `output_meter_left/right` (post-fader, float), name, colour, mute/solo/arm, `muted_via_solo` ([LOM Track](https://docs.cycling74.com/apiref/lom/track/)) |
| **Pro Tools 24.6 (yes)** | HUI proxy (stereo 12-seg meters, 4-char names) | Extra HUI units use up Pro Tools' **4 HUI slots** ([SSL](https://support.solidstatelogic.com/hc/en-gb/articles/4410035394321-Using-UF8)); SoundFlow may already hold one | PTSL for names, colours and state ([py-ptsl](https://github.com/iluvcapra/py-ptsl)), polled on 24.6 (no events before PTSL 2025.6/2025.10). **PTSL has no meters**, so a hi-res meter needs an AAX plugin. |
| **FL Studio 2025 (yes)** | Proxy (SSL's `McuFLStudio` profile) | FL MIDI script | `mixer.getTrackPeaks` L/R, name, colour, mute/solo/selected ([FL scripting](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/midi_scripting.htm)) |
| Logic (no) | Proxy | XTs in the UF8's group (changes bank step), or a separate group (doesn't follow). Mirroring with offset 0 is UNVERIFIED ([Logic CS guide](https://help.apple.com/pdf/logicpro-css/en_US/logic-pro-control-surfaces-support-guide.pdf)). | No public meter or colour API |
| Cubase (no) | Proxy | MIDI Remote script | `mVUMeter*` floats over a virtual MIDI port ([MIDI Remote API](https://github.com/steinbergmedia/midiremote_api_doc)) |
| REAPER (no) | MCUEX at offset 0 (no proxy needed) | Offsets 8 and 16; note the bank step becomes 24 | OSC `/track/@/vu` or the extension API |

**Live-specific check to run first (UNVERIFIED).** Live's `MackieControl` attaches XTs listed after it as right-hand extensions and banks by the total strip count. If the three port-less XTs in slots 4–6 are being instantiated, the UF8 may currently bank by **32**, not 8.
- Test: press BANK on the UF8.
- Fix either way: remove the unused XT slots. This also frees a slot for the bridge's Remote Script; the log shows all control-surface slots in use.

### 2.4 Physical sizing for the display

**Dimensions**
- **UF8:** 431 × 266 × 62.7 mm ([SSL](https://www.solidstatelogic.com/products/uf8)).
- **UF1:** 205 mm wide ([SSL](https://www.solidstatelogic.com/products/uf1)).

**Strip pitch: about 38.5 mm** (UNVERIFIED). This was measured from SSL's to-scale panel drawing, not from a published spec:
- strip 1 centre about 80.7 mm from the left edge
- 8-strip zone about 308 mm wide, centre-to-centre span about 270 mm
- two UF8s side by side: about 161 mm from strip 8 to strip 9

So each UF8 needs its **own bank window**. The app's two-point calibration (drag the strip-1 and strip-8 markers over the faders) makes the exact pitch unimportant.

**Candidate displays.** Goal: active width ≥ about 300 mm, so meters sit over the strips, and outline ≤ 431 mm, so the display doesn't overhang the neighbouring unit.

| Panel | Active area | Verdict |
|---|---|---|
| 14" 3840×1100 (also sold as 1920×550), e.g. [DFRobot DFR1125](https://wiki.dfrobot.com/dfr1125/) | **344.2 × 98.6 mm**, outline 369.5 mm (confirmed) | **Recommended.** Covers the 8 strips with about 18 mm spare each side, about 430 px per strip. |
| 12.6" 1920×515 | About 309 × 83 mm (seller data; geometry agrees; UNVERIFIED) | Closest 1:1 match with the 8-strip zone |
| 12.3" 1920×720 | About 292 × 110 mm (UNVERIFIED) | Works. Meter centres can sit over the strip centres, but the outer meters lose about 8 mm of width. |
| 8.8" 1920×480 | About 219 mm | Too narrow (about 5.7 strips) |

**Connecting it to this Mac**
- The M1 Max supports 3 external displays at 6K plus 1 at 4K ([Apple](https://support.apple.com/en-us/111901)). Three are already connected, so the bar display takes the **last** slot.
- Use HDMI or USB-C DisplayPort Alt-mode, **not DisplayLink**. DisplayLink needs DisplayLink Manager with Screen Recording permission.
- Check which port is free: Apple's spec gives the 4K slot to HDMI.

---

## 3. Behringer WING: what "compatible" can mean

There are two different integrations. They share almost no code.

**3a. WING as a DAW controller (MCU/HUI over USB MIDI). This is what DAWWAY means by compatible.**
- **Full WING:** 4 USB MIDI ports. On macOS: `WING 1` = master, `WING 2/3` = extenders, `WING 4` = control. That gives up to 24 DAW faders (MCU + 2 XT); DIN is limited to a single MCU ([WING DAW doc](https://wing-docs.com/pdf/DAW_Documentation.pdf)).
- **Pro Tools:** must use HUI. All other DAW presets use MCU.
- **Compact / Rack:** only 2 USB MIDI ports. Rack DAW mode allows one MCU device ([Remote Protocols 3.0.6](https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf), p.11, p.137). The Compact appears limited to 8 DAW faders (from a schema dump; UNVERIFIED on hardware).
- **The WING never republishes DAW track data over the network.** Its parameter tree has only DAW-mode *configuration* nodes, and its meter tokens cover console objects only. Bridge meters therefore come from the **same MCU/HUI proxy as the UF8**:
  - the DAW's Mackie slots point at the bridge
  - the bridge forwards to `WING 1–3`
  - the WING ports are ordinary class-compliant endpoints, so this is simpler than SSL
- **What it requires:**
  - a "WING" port profile, with port names matched for both the full-size and Compact/Rack naming
  - Cubase's reversed port order handled
  - resilience to USB MIDI dropping for a few seconds when the WING's clock or USB channel count changes, including on snapshot load (CoreMIDI setup-change handling)
  - a layout template for the **12 + 8 + 4** physical strip groups. How MCU's 3×8 maps onto 12/8/4 is UNVERIFIED.
- **Unknowns:**
  - Whether the WING's own strip LEDs show DAW meters is UNVERIFIED.
  - Scribble strips are black and white; DAW colours are not shown.

**3b. WING console meters (its own channels). This is the precise path, but it only shows DAW tracks if they are routed into the WING over USB.**
- **Discovery:** send UDP `WING?` to port 2222.
- **Session:** native TCP 2222 with keep-alive under 10 s. Meter request on channel `DF D3`: `D3 <udp port>`, `D4 <report id>`, `DC <type> <0-based idx>… DE`.
- **Meter packets:** UDP `<id><int16 BE…>`. Levels are in **1/256 dB**; each channel gives in L/R, out L/R and gate/dyn values. They arrive "approximately every 50ms" and must be renewed within 5 s (official doc, p.122; current spec is [V3.1.2-a](https://drive.google.com/file/d/1-iptgd2Uxw4qPEbmegG2Sqccf8AbRRfk/view)).
- **Names, colours, mute, solo, select:** native hashes or OSC on UDP 2223. OSC allows only **one** event subscriber at a time, and Bitfocus Companion would fight over it. Native TCP pushes changes to up to 16 clients (24 on 3.1.x is UNVERIFIED).
- **USB returns:** the source-group meters (`0xa7`) include "usb audio", so DAW outputs routed to separate USB channels can be metered at 1/256 dB.
- **Reference code:** [libwing](https://github.com/dannyfiresnake/libwing) (Rust with a C FFI; licence files disagree, MIT vs Apache-2.0). No Swift library exists, but the protocol is small enough for Network.framework.
- **macOS requirements:** network.client and network.server entitlements (both verified as needed for UDP in the sandbox), `NSLocalNetworkUsageDescription`, and a retry if the first send is denied ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)).

**Recommendation:** "WING compatible" in v1 means **3a**, delivered as a port profile plus a layout template on top of the proxy (Phase 3). Treat **3b** as optional (Phase 4), and only if the user mixes through the WING as a console or hybrid summing setup.

---

## 4. Meter data sources compared

| Source | Meter quality | Names / colours | Mute / solo / select | Follows the UF8 bank | Setup friction | Build effort | DAWs |
|---|---|---|---|---|---|---|---|
| **MCU proxy** (on SSL V-MIDI / WING ports) | 13–14 levels (`0x0–0xD`), **mono**. Live sends `int(level*12)` at about **10 Hz**; Live sends the input meter when a track is armed. The bridge must decay meters itself. | 7-char LCD names (6 usable); **no colour** | Yes: LED notes for rec (0x00–07), solo (08–0F), mute (10–17), select (18–1F); faders as pitch bend | **Exact, by construction** | Low–medium: reassign 1–3 DAW port pairs; bridge must stay running | Low–medium | Live, Logic, Cubase, Studio One, FL, LUNA, Mixbus, Bitwig… |
| **HUI proxy** | 12 levels, **stereo** (`A0 0c sv`) | 4-char names | Yes; must answer the HUI ping (`90 00 00` → `90 00 7F`) | Exact | Same as MCU | Medium ([swift-midi-controlsurfaces](https://github.com/orchetect/swift-midi-controlsurfaces), MIT) | Pro Tools |
| **Spy driver** | Same data as the proxy | Same | Same (read-only) | Exact | Low for the DAW, but needs an admin driver install | Medium–high; UNVERIFIED on SSL destinations | All MCU/HUI DAWs |
| **Emulated MCU XT / HUI units** | Same as MCU/HUI | Same | Same | Adjacent banks only (REAPER offset 0 mirrors); changes the UF8 bank step | Medium | Low (shares the proxy code) | Fallback for Logic and Pro Tools |
| **Per-track meter plugin** (AU/VST3/AAX/CLAP) | Float peak/RMS, stereo, any rate; **pre-fader** in Live and most inserts | VST3/CLAP give name and colour; AU/AAX give name only | Only through PreSonus extensions (Live support UNVERIFIED) | None (needs inference) | High: 24 inserts per session | Medium–high (+ AAX signing) | All |
| **Live LOM** (custom Remote Script, AbletonOSC or Max for Live) | Float 0–1 smoothed peak L/R, **post-fader**. Listener rate and dB mapping UNVERIFIED. Ableton warns of GUI load. | Full names, colour | Mute, solo, arm, **`muted_via_solo`**, selected track | Inferred by matching against proxy names (5.4) | Medium: drop the script into the User Library and use one control-surface slot | Medium | Live |
| **Pro Tools PTSL** | **None** | Name, colour | Muted, soloed, selected, rec (poll on 24.6) | Inferred | Medium | Medium | Pro Tools |
| **Cubase MIDI Remote** | Float `mVUMeter`, peak, clip | Title, colour | Yes | Inferred | Medium | Medium | Cubase (not installed) |
| **REAPER OSC / extension** | Float L/R | Name (+ colour through the API) | Yes | MCUEX offset trick | Low | Low–medium | REAPER (not installed) |
| **FL MIDI script** | Float L/R | Name, colour | Yes | Inferred | Medium | Medium | FL Studio |
| **WING native protocol** | 1/256 dB, about 20 Hz, console channels only | 16-char names, palette colour | Yes | N/A (console channels) | Low (network) | Medium | WING console mode |

Sources:
- MCU and HUI: [TouchMCU](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md), [Ardour meter.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc), [REAPER csurf_mcu.cpp](https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp).
- Live's MCU behaviour: [decompiled MackieControl, Live 10.1](https://github.com/gluon/AbletonLive10.1_MIDIRemoteScripts/blob/master/MackieControl/ChannelStrip.py). Correction to an earlier report: Live sends meters by default when the surface does **not** answer the firmware-version query. Only a "pro" reply gates meters behind meter mode and the Vol/Pan assignment. What SSL 360 replies is UNVERIFIED.
- [AbletonOSC](https://github.com/ideoforms/AbletonOSC) (MIT) exposes meters, name, colour, mute and solo listeners, but not `muted_via_solo`.

---

## 5. Recommended architecture

### 5.1 Decision

**Build the MCU transparent proxy first, aimed at Ableton Live 12 on SSL Layer 1 (V-MIDI Port 1 through Port N for N UF8s). Add a Live Remote Script second, for high-resolution data.**

Why the proxy first:
1. **It shows exactly what the UF8 shows.** Bank alignment comes for free in every MCU DAW, with no inference. That is the core promise.
2. **The same stream carries everything mix focus needs** (solo, mute, select, rec, names and fader positions) and lets the bridge **send** clicks, bank moves and Shift-fine fader moves, which makes it "an extension of my DAW".
3. **It is proven.** DAWWAY ships this design and demonstrates it on a UF8. On macOS no driver is needed, and virtual ports work in the sandbox (tested locally).
4. **It reuses well.** The same code serves WING DAW mode, any other MCU DAW and, with a HUI codec, Pro Tools.

Why not the others first:
- **Spy driver:** UNVERIFIED on SSL's destinations, can't be sandboxed, and runs inside MIDIServer. Keep it as an optional "no reconfiguration" mode later, if Spike C passes.
- **Plugins:** 24 inserts per session, and pre-fader in Live.
- **Emulated XTs in Live:** they change the UF8's bank step.

Why the Live Remote Script second: MCU meters (13 steps, about 10 Hz, mono) will look visibly stepped on a 344 mm display. LOM gives post-fader float stereo meters, colours, full names, exact solo-implied muting and the full track list. That list is what fills **24 strips from a single UF8** without touching its bank step.

### 5.2 Stack

- **Language and UI**
  - Swift 6 (strict concurrency), Xcode 26.x. **Deployment target macOS 14.0** (needed for `NSView.displayLink`/`CADisplayLink` and `@Observable`; `CVDisplayLink` is deprecated in 15). Universal binary.
  - **AppKit core:**
    - borderless `.nonactivatingPanel` `NSPanel`s
    - `collectionBehavior` = `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
    - `hidesOnDeactivate = false` and `canHide = false`, so the DAW's "Hide Others" doesn't hide the bridge (verified)
    - `acceptsFirstMouse` so clicks act immediately without stealing DAW focus
    - **override `constrainFrameRect(_:to:)`** and use level ≥ `.mainMenu`, so the panel can cover the menu-bar strip on a short bar display. Borderless windows at low levels *are* constrained on 26.4.1 (verified).
    - `ignoresMouseEvents` in "locked" mode
  - **SwiftUI** only for Settings, the setup assistant and the menu-bar popover. `LSUIElement`; App Nap disabled while meters are live.
- **Rendering:** Core Animation layers. Each strip has a gradient behind a mask that changes height, a peak line and a clip LED. Implicit actions are off. Text updates at 10–15 Hz. The renderer pauses when everything has decayed to idle. A `MeterRenderer` protocol leaves room for Metal later (cylinder and analogue styles).
- **MIDI:**
  - CoreMIDI UMP APIs (`MIDISourceCreateWithProtocol` / `MIDIDestinationCreateWithProtocol`, `MIDIReceivedEventList`); the legacy calls are marked to-be-deprecated.
  - Our own thin UMP and MCU layer; [swift-midi-controlsurfaces](https://github.com/orchetect/swift-midi-controlsurfaces) for HUI.
  - Gotchas verified locally:
    - SysEx arrives as type-3 SysEx7 start/continue/end messages with F0/F7 stripped. SysEx of 6 bytes or fewer arrives as a single "complete" message.
    - Read `MIDIEventPacket` words **through a raw pointer**. The Swift `words` tuple holds 64 words and silently truncates long SysEx (a 608-byte SysEx arrived as 202 words).
    - **Persist and reassign `kMIDIPropertyUniqueID`** for each port, so the DAW keeps its assignment. Handle `kMIDIIDNotUnique`.
    - Create the MIDI client on the main thread.
- **Networking:** Network.framework UDP on localhost for the Live script, and later for the WING. Entitlements: network.client + network.server.
- **Other:**
  - Hotkey: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon, no Accessibility permission). Default **⌃⌥⌘M**. In a sandboxed app on 26.4.1, Shift-only hotkeys fail (verified).
  - Launch at login with `SMAppService.mainApp`.
- **Distribution:** Developer ID, Hardened Runtime and notarization, with the **App Sandbox on**. Sparkle 2 later. Installing the Live script from inside the sandbox goes through a user-chosen User Library folder (security-scoped bookmark), or the app reveals the file for the user to copy.

### 5.3 Modules (Swift package `MeterBridgeKit`, dependencies point downward only)

```
App (menu bar, settings, setup assistant, diagnostics/capture, hotkey, login item)
 ├─ LayoutEditor   edit mode: drag/resize handles, Shift = 0.1x fine, arrows 1px / Option+arrows 10px, Cmd = no snap, undo, 2-point calibration
 ├─ MeterRendering CA layer bank views, per-display CADisplayLink driver, MeterRenderer protocol
 ├─ Layout / DisplayManager   strip groups of N strips (not fixed 8), coordinates stored in display-relative pixels,
 │                            display fingerprint (UUID > vendor+model+serial≠0 > vendor+model+name+size > position), reconnect debounce
 ├─ BankResolver   merges per-unit SurfaceState with a full TrackList into BridgeSnapshot (24 slots)
 ├─ Sources        ProxySurfaceSource (MCU/HUI), LiveSource (UDP), SimulatedSource, [WingConsoleSource]
 ├─ SurfaceProxy   port-pair router: app virtual ports <-> SSL V-MIDI N / WING N; forward-first, then tap;
 │                 injection queue (never inside a SysEx), fader-touch arbitration, endpoint vanish/reappear
 ├─ MIDITransport  CoreMIDI client, virtual endpoints, persisted unique IDs, name matching, setup notifications
 ├─ ProtocolMCU / ProtocolHUI   decode/encode: meters, LEDs, LCD 2x56 buffer, pitch bend, touch, handshake recognition
 ├─ UMP            event-list walking, message sizing, SysEx7 reassembly (pointer-based)
 └─ MeterCore      TrackState, MixFocus rules, dB<->segment tables per host, Ballistics (injected clock)
```

### 5.4 Data flow

```
Live "MackieControl" slot --> [vDest "MeterBridge UF8-1 In"] --Router--> "SSL V-MIDI Port 1 Destination" --> SSL360Core --> UF8/UF1
                          <-- [vSrc  "MeterBridge UF8-1 Out"] <--Router-- "SSL V-MIDI Port 1 Source"      <-- SSL360Core <-- UF8/UF1
                                        |  tap (DAW->surface)          ^ inject (clicks, bank, fader+touch)
                                        v                              |
                                MCU decoder -> SurfaceState[unit] -> BankResolver <- LiveSource <- UDP 127.0.0.1 <- MeterBridge Remote Script (P2)
                                                                        |
                                              BridgeSnapshot (OSAllocatedUnfairLock) -> CADisplayLink (per display) -> bank NSPanels
```

**Threading**
- On the CoreMIDI receive thread: **forward first** (latency target well under 1 ms, UNVERIFIED), then parse into a lock-protected snapshot. No allocation on this path.
- The display link on the main thread advances the ballistics: peak hold, decay (MCU hosts send only *rising* values), clip latch, and a forced clear on bank change.

**Bank alignment, Phase 2.** Match the UF8's 8 LCD names (truncated, 6–7 chars) as a sliding window against LOM's ordered list of visible tracks. Tie-breakers:
- fader values (MCU pitch bend vs LOM volume)
- mute/solo/arm patterns
- the selected-track LED vs the LOM selection

Re-solve whenever the LCD is rewritten. The result is a bank offset, which lets the bridge fill 24 slots (for example the UF8's 8 plus the next 16) from LOM.

**Bridge interactions**
- **Solo/mute/select/bank:** send an MCU note-on `7F` followed by `00` into the DAW-bound stream.
- **Fader:** touch-on (`0x68+n`), 14-bit pitch bend, touch-off. **Shift scales the drag by 0.1×.** If the UF8 reports a touch on the same strip, the bridge yields. Live's MCU fader resolution is UNVERIFIED; in Phase 2, fine moves go through LOM `volume` instead.

### 5.5 Coexistence with SSL 360

- **SSL 360 still owns the hardware, profiles, layers, UC1, Plug-in Mixer, 360 Link and PTSL.** The only change the user makes: in Live, slot 1 `MackieControl` In/Out goes from "SSL V-MIDI Port 1 Source/Destination" to "MeterBridge UF8-1 Out/In". The same applies to ports 2–4 if more UF8s are added.
- **The bridge must forward every byte unchanged**, including:
  - the device query and firmware-version SysEx (`…14 00`, `…14 13`)
  - meter-mode SysEx (`…14 20/21`)
  - any SSL-specific traffic
- **Never use SSL360Core's undocumented localhost TCP/UDP ports.**
- **Failure modes:**
  - If SSL360Core restarts, its endpoints vanish. The bridge reconnects by name.
  - If the bridge quits, the UF8 loses the DAW. Mitigations: a login item, "hide" never stops the router, and the setup assistant documents a one-step revert.
  - The bridge cannot tell whether the UF8 is on Layer 2/3 or the Plug-in Mixer (UNVERIFIED). Possible heuristic: which SSL Source port the touch events arrive on.

---

## 6. Phased roadmap

Durations are rough estimates for one experienced Swift engineer.

### Phase 0: skeleton, simulator, de-risking spikes (about 2 weeks)

**De-risking spikes. Run these on the user's machine first; each is cheap and changes decisions.**
- **A. Proxy transparency.** A small Swift CLI forwards "MB Test In/Out" ⇄ SSL V-MIDI Port 1 and logs everything as JSONL. Point Live's slot 1 at it and check:
  - names, meters, LEDs, banking, FINE, SSL soft keys and transport behave normally
  - capture SSL 360's reply to the `0x13` version query, the meter rate and the meter-mode SysEx
- **B.** Press BANK on the UF8 with the current Live config: is the step 8 or 32?
- **C.** Run MIDI Monitor's "Spy on output to destinations" on "SSL V-MIDI Port 1 Destination". Does the spy see DAW→SSL traffic? This decides whether a no-reconfiguration mode is possible later.
- **D.** Quick AbletonOSC test: LOM meter listener rate, the 0–1→dB curve and GUI load with 24 tracks observed.

**Deliverables**
- Xcode app target plus the `MeterBridgeKit` package (macOS 14, Swift 6), and CI running `swift test`.
- MeterCore, UMP and ProtocolMCU, with golden test vectors taken from the observed UMP words and captures from Spike A.
- Ballistics tests driven by an injected clock.
- **Simulator** with two modes:
  - feeding the model directly
  - a "virtual DAW" that sends real MCU bytes through a virtual port

  Scenarios: random-walk levels, sweeps, clipping, silence, solo/mute/select patterns, bank switches. It doubles as **setup/demo mode**, so the layout can be aligned without a DAW running.
- One bank window (8 meters at 60 Hz) on a chosen display. Edit mode with Shift-fine drag, nudges and snapping; display fingerprinting; saved presets.
- Hide/show via hotkey and menu bar.

**Exit criteria**
- 24 simulated stereo meters at 60 Hz with **< about 5% of one core** in Instruments (UNVERIFIED target).
- The layout survives unplugging and replugging the display.

### Phase 1: MVP, UF8 + Live through the MCU proxy (about 3–4 weeks)

- SurfaceProxy for Layer 1 with 1–4 units, persistent unique IDs and hot-plug recovery.
- Setup assistant:
  - shows the exact Live preference changes
  - live "traffic flowing" health light
  - detects a double assignment (Live still also connected to SSL Port 1)
- Per-UF8 bank windows with two-point calibration.
- 7-char names; meters with decay, peak hold, clip latch and peak alert; clear on bank change.
- **Mix focus:** dim muted strips, dim non-soloed strips when any visible strip is soloed (10–90%), highlight the selected strip, show rec state.
- Clickable solo/mute/select and bank ◀▶ on the bridge.
- **Phase 1b:** fader drag with Shift-fine and touch arbitration.
- A notarized personal build.

### Phase 2: Live high-resolution layer and 24 tracks from one UF8 (about 3 weeks)

- "MeterBridge" Live Remote Script (Python, User Library). AbletonOSC serves as the reference. It streams to localhost UDP, rate-limited to about 30 Hz:
  - post-fader `output_meter_left/right`
  - name, colour, mute/solo/arm, `muted_via_solo`
  - selected track and visible-track list
  - accepts commands (volume, mute, solo, select)
- It takes over a freed slot (one of the unused XT slots).
- BankResolver alignment. Up to 24 strips: the UF8's 8 aligned, plus 16 context strips in separate windows.
- True stereo meters, accurate dB readouts, colours, long names, exact solo-implied muting, and fine fader moves through LOM.
- Falls back to MCU-only data when the script is absent.

### Phase 3: Pro Tools and Behringer WING DAW mode (about 3–4 weeks)

- **Pro Tools:**
  - HUI codec (stereo meters, ping keep-alive, 4-char names) on the proxy
  - PTSL client (gRPC) for names and colours, polled on 24.6
  - a warning if EUCON is active, because it disables HUI meters ([Neyrinck](https://neyrinck.com/help/channel-meters-not-working-for-pro-tools/))
- **WING:**
  - port profile (`WING 1–3`, Compact/Rack naming), MCU+2XT
  - 12/8/4 layout template with gaps
  - resilience to USB-drop on clock or snapshot changes
  - a HUI variant for Pro Tools

### Phase 4 and later (optional, prioritise from user feedback)

- WING console meters through the native protocol.
- Spy-driver "no reconfiguration" mode, if Spike C passed; ships as a separate installer.
- Metal renderer: cylinder, analogue VU and glow styles.
- FL Studio script source.
- Logic, Cubase and REAPER profiles.
- Touch input.
- Sparkle updates.
- Public distribution (licensing, own SysEx ID, branding).

---

## 7. Risks and unknowns

| # | Risk / unknown | Impact | Mitigation | Status |
|---|---|---|---|---|
| 1 | SSL 360 misbehaves behind a proxy (handshake, version reply, profile assumptions) | Blocks the core design | Spike A before building anything else | UNVERIFIED |
| 2 | The bridge becomes a single point of failure for the UF8 | UF8 goes dead if the app quits or crashes | Login item, router keeps running when hidden, crash-safe restart, documented revert | Known |
| 3 | Live gates MCU meters on a "pro" version reply (if SSL 360 answers that way, meters need meter mode on and Vol/Pan assignment) | No meters in MVP | Capture in Spike A; the bridge can rewrite the version reply only if necessary (last resort) | UNVERIFIED |
| 4 | MCU meters are coarse (13 steps, about 10 Hz, mono) and hosts send only rising values | Stepped or frozen-looking meters | Own decay and interpolation; Phase 2 LOM | Confirmed |
| 5 | Unassigned MackieControlXT slots make the UF8 bank by 32 | Confusing banking | Spike B; remove the slots | UNVERIFIED |
| 6 | Live control-surface slots are full | No room for the Remote Script | Free an unused XT slot | Confirmed (log) |
| 7 | LOM meter listener rate, 0–1→dB mapping and GUI load ("significant load" per Ableton) | Phase 2 quality | Spike D; rate-limit; calibrate the curve | UNVERIFIED |
| 8 | Bank alignment by name is ambiguous (duplicate or truncated names) | Wrong tracks shown | Fader, state and selection fingerprint tie-breakers; show "unaligned" rather than guess | Design |
| 9 | The bridge can't detect the UF8's layer or Plug-in Mixer mode | Bridge shows Layer 1 while the UF8 shows something else | Source-port heuristic; manual indicator | UNVERIFIED |
| 10 | MCU only sees 8 strips, so it can't know about a solo on a track outside the bank | Mix-focus dimming wrong in MVP | LOM `muted_via_solo` (P2); possibly the global "rude solo" LED (UNVERIFIED in Live) | Known |
| 11 | SSL 360 upgrade (installed 2.0.6, current 2.1.x) changes behaviour | Regression | Run spikes on the version the user will keep | UNVERIFIED |
| 12 | Spy driver: not tested on app-owned virtual destinations, not sandboxable, MIDIServer stability | Optional mode may be impossible | Treat as Phase 4, gated on Spike C | UNVERIFIED |
| 13 | Pro Tools: 4 HUI slots (SoundFlow may use one), EUCON disables HUI meters, PT 24.6 has no PTSL events | Reduced Pro Tools support | Polling; warnings; AAX meter plugin only if demanded | Partly confirmed |
| 14 | WING: DAW meters on the WING itself, 12/8/4 mapping, model (Compact/Rack = 8 faders) | Layout and scope | Ask the user; flexible strip groups | UNVERIFIED |
| 15 | Display: last available display slot on the M1 Max; DisplayLink needs Screen Recording; cheap EDID (serial 0, wrong mm) | Can't connect, or a flaky identity | HDMI or DP Alt-mode panel; multi-field fingerprint; calibrate by eye, not by EDID mm | Confirmed |
| 16 | UF8 strip pitch (about 38.5 mm) is derived, not published | Misalignment | Two-point calibration on the real unit | UNVERIFIED |
| 17 | Hotkeys in the sandbox (Shift-only fails on 26.4.1; Sequoia had Option-only issues) | Hotkey doesn't register | Default includes ⌘/⌃; MIDI-learn alternative | Confirmed |
| 18 | MCU wire-format details differ by host (0xD level used by REAPER and Ardour; REAPER's 0xE/0xF comments conflict) | Parser edge cases | Accept 0x0–0xF; per-host dB tables | Partly confirmed |
| 19 | A commercial release would compete with or resemble DAWWAY | Legal and branding | Own name and UI; don't reuse the 0x7D ID commercially | Decision |

---

## 8. Decisions the user must make (with recommended defaults)

1. **Main DAW for the bridge.** Default: **Ableton Live 12**, with Pro Tools in Phase 3. Live is the only DAW currently wired to the UF8 on this Mac.
2. **Integration mode.** Should Live talk to the UF8 *through* the bridge (proxy: one-time port change, and the bridge must be running), or should we try a background driver that needs no reconfiguration? Default: **proxy**. The driver is tested in Phase 0 and offered later only if it works.
3. **What "24 tracks" means.** Are you planning to buy more UF8s (one bank window each, all aligned), or do you want 8 aligned plus 16 extra context meters with a single UF8? Default: support **both**, starting with 8 aligned per UF8 (P1) and adding the 16 context strips from Live (P2). No extra Mackie extenders, because they would change your UF8's BANK step.
4. **"Hold Shift for fine movements".** Does this mean fine fader and level moves from the bridge, fine positioning of the meter windows, or both? Default: **both**. Window nudging comes in Phase 0; Shift-fine faders in Phase 1b.
5. **Interactive or view-only.** Should clicking a strip on the bridge solo, mute or select it in the DAW (and bank), like DAWWAY? Default: **interactive** in the MVP (solo, mute, select, bank); faders in 1b.
6. **Meter fidelity.** Are coarse MCU meters acceptable for the first working version, with high-resolution stereo meters, colours and full names arriving in Phase 2 through a small Live script? Default: **yes**.
7. **Display to buy.** Default: **14" 3840×1100 bar panel** (DFR1125-class: 344 mm active, 369.5 mm outline) on HDMI or USB-C DisplayPort, **not DisplayLink**. Alternative: 12.6" 1920×515 for a near 1:1 strip match. Check that the Amazon listing gives an active width ≥ 300 mm. Also, is it a touchscreen, and do you want touch?
8. **Behringer WING scope.** Which model is it (full-size, Compact or Rack), and do you use it as a DAW controller, as a console/interface, or both? Default: **DAW-controller mode** through the same proxy in Phase 3; console meters deferred.
9. **UF1 and UC1.** Should the bridge mark the strip the UF1 fader is on? Default: **yes, as a small marker**. UC1: coexist only, no features.
10. **SSL 360 version.** Default: **update to the current 2.1.x before Phase 0's spikes**, so we build against the version you will keep.
11. **Hide/show trigger.** Default: **⌃⌥⌘M + menu bar**, plus optional MIDI-learn so a spare controller button can toggle it.
12. **Visual style for v1.** Default: **segmented LED with peak hold, clip and numeric peak readout**. Cylinder and analogue styles in Phase 4.
13. **Personal tool or product for sale.** Default: **personal**, built as a notarized, sandboxed Developer ID app so selling stays possible. If you plan to sell, decide before Phase 4: naming, licensing and a commercial SysEx ID.