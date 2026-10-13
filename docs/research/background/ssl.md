# SSL UF8 / UF1 / UC1 on macOS via SSL 360°: DAW integration, meter data, bank sync and physical fit

## 0. Quick answer: can a third-party app follow what the UF8 shows?
Yes, but not through any SSL API. I found no public SSL 360° API, SDK or OSC interface, and SSL's own v2.1 release names only HUI and MCU ([SSL 360 v2.1](https://solidstatelogic.com/media/ssl-360-v2.1-update)). On macOS the "SSL V-MIDI" ports are ordinary CoreMIDI virtual endpoints, so there are three workable routes:

1. **MIDI proxy (what DAWWAY does).** The DAW connects to your app's virtual ports, and the app forwards traffic both ways to the SSL V-MIDI ports. This gives an exact mirror of the UF8.
2. **Passive "spy" on SSL V-MIDI Port N Destination** through a CoreMIDI driver's `MIDIDriverEnableMonitoring`. This needs no change to the user's setup.
3. **DAW-native grouping of extra virtual Mackie extenders.** These bank in lock-step with the UF8, but they show the *adjacent* banks (strips 9–24), not the UF8's own 8 strips. The one verified exception is REAPER, where an MCU-extender instance with offset 0 mirrors the UF8.

The MCU/HUI meter data is coarse (13 levels) in every case. Details and sources follow.

---

## 1. Which DAW uses which protocol (SSL 360°)
Source: SSL's FAQ "[Which DAWs work with UF8 & UF1?](https://support.solidstatelogic.com/hc/en-gb/articles/4408132094865-Which-DAWs-work-with-UF8-UF1)" (updated 12 May 2025).

**How SSL says the UF8 talks to DAWs.** There are three routes:
- HUI and Mackie Control (MCU) protocols.
- "VST3 extensions to communicate with certain DAWs (when set to 'Plug-in Mixer' and using 360°-enabled plug-ins)".
- MIDI CC.

**DAWs with dedicated profiles:** Pro Tools, Logic Pro, Cubase/Nuendo, Live, Studio One, LUNA, Pyramix, Mixbus, REAPER, Bitwig Studio, Digital Performer, FL Studio, Samplitude/Sequoia, plus a MIDI CC profile.

**Other DAWs:**
- Premiere Pro works using the Logic or Studio One profile.
- "Cakewalk is not supported."
- "Any DAW that supports MCU or HUI should have some basic functionality."

**Protocol and setup per DAW.** Source: [UF8 User Guide Rev 3.0, Oct 2022](https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide.pdf), pp.22–92.

| DAW | Protocol | How it is set up |
|---|---|---|
| Pro Tools | HUI | Plus SSL extras (CHANNEL/PLUGIN modes). Each UF8 is a HUI controller on V-MIDI Port N. |
| Logic | MCU | The first UF8 is "Mackie Control". Further units are "Mackie Control Extender" with Fader Bank Offset 8/16/24. Set Channel Strip View Mode to "Arrange". |
| Cubase/Nuendo | MCU | Legacy "Mackie Control" devices, set to "Cubase" mode, not "Compatibility". There is a known quirk: two units mirror the same bank until you swap their ports. |
| Live | MCU | MackieControl, then MackieControl XT for units 2–4. |
| Studio One | MCU | Mackie Control plus Mackie Control Extender, dragged into "Group 1" in Placement. |
| LUNA | MCU | Tick the EXTENDER column for extra units. |
| Pyramix | MCU-type | OASIS driver with the "SSL UF8 MackieCtrl" controller. |
| REAPER | REAPER's built-in MCU | See [SSL: UF8 and UF1 REAPER MCU](https://support.solidstatelogic.com/hc/en-gb/articles/14089299646749-UF8-and-UF1-REAPER-MCU). SSL lists CSI, ReLearn, Klinke and DrivenByMoss as unsupported third-party options. |
| Plug-in Mixer layer | "Natively via our own proprietary protocol" | Uses neither HUI nor MCU. |

**UNVERIFIED:** the exact protocol of the Mixbus, Bitwig, Digital Performer, FL Studio and Samplitude profiles. They are most likely MCU.

**Newer SSL 360° (v2.0 Oct 2025, v2.1 Aug 2026)**
- For Pro Tools, SSL 360° v2.1.12+ uses Avid's **PTSL** service to show 8-character track names and Pro Tools track colours on the UF8 and UF1. This needs Pro Tools 2025 or 2026 ([SSL support](https://support.solidstatelogic.com/hc/en-gb/articles/38295880789789-Which-versions-of-Pro-Tools-and-SSL-360-are-required-to-access-the-enhanced-UC1-UF8-UF1-DAW-integration-features)).
- **Implication:** some of what the UF8 displays is produced by SSL 360° itself (PTSL names and colours, soft-key labels, Plug-in Mixer data), not by the DAW's HUI/MCU stream. A MIDI tap will not see it. That the PTSL names never pass through the V-MIDI port is my inference, not tested.
- v2.1 adds Logic track colours, synchronised selection and solo/mute for the **Plug-in Mixer layer**, the UC1 and the "Hybrid" mode ([SSL media](https://solidstatelogic.com/media/ssl-360-v2.1-update)).

**This Mac:** SSL 360 is installed, version 2.0.6.67265, so it is behind the current 2.1.x.

---

## 2. SSL V-MIDI ports, layers, multiple UF8s and the UF1
**Port map** (UF8 Guide p.22; Control Setup p.18):

| Layer | 1st UF8 | 2nd UF8 | 3rd UF8 | 4th UF8 |
|---|---|---|---|---|
| Layer 1 (DAW 1) | Port 1 | Port 2 | Port 3 | Port 4 |
| Layer 2 (DAW 2) | Port 5 | Port 6 | Port 7 | Port 8 |
| Layer 3 (DAW 3) | Port 9 | Port 10 | Port 11 | Port 12 |

- Endpoint names are "SSL V-MIDI Port N Source" and "SSL V-MIDI Port N Destination".
- **Checked on this Mac with a CoreMIDI enumeration script:** all 24 endpoints exist as virtual endpoints. They have no MIDIEntity or driver and are owned by the process `/Applications/SSL 360.app/Contents/Resources/SSL360Core`. The script was a throwaway in a temporary scratch folder.
- **What this means for a third-party app:**
  - It can openly connect to every "…Source" endpoint and read all UF8→DAW traffic (fader moves and touches, button presses).
  - It cannot read DAW→UF8 traffic (meters, names, LEDs) sent to a "…Destination" with normal CoreMIDI calls. That needs either the proxy or the driver spy (section 4).
- SSL360Core is a .NET process. It was observed listening on `127.0.0.1` TCP 49638/49639 and two localhost UDP ports. These are undocumented and probably serve the GUI and 360-enabled plug-ins. They are not a public API, and using them is not recommended.

**Layers**
- The UF8 can drive up to 3 DAWs, switched with the LAYER keys.
- One layer can be set to the Plug-in Mixer instead of a DAW.
- One layer can be named Transport Master.
- **Open question:** I found no way for a third party to learn which layer the hardware is currently on. One possible signal is which Source port the UF8 sends touch or fader events from, but this is UNVERIFIED.

**Multiple UF8s**
- "Connect up to 4 UF8s to create a 32-channel control surface." Units can be chained through the USB-A THRU port.
- The order of units is set by dragging on the SSL 360° Home page.
- BANK moves "in multiples of 8 … 8 for one UF8, 16 for 2 UF8s" (Guide pp.5, 8, 26, 39).

**UF1** ([UF1 User Guide Rev 1.0, May 2023](https://www.ambertech.com.au/Documents/SSL/SSL%20UF1%20User%20Guide_Rev1.0.pdf))
- Hardware: 1 motorised fader, a 4.3" TFT plus a small TFT.
- Uses the same layer scheme: Layer 1 = Port 1, Layer 2 = Port 5, Layer 3 = Port 9.
- In Logic it is set up as a "Mackie Control".
- BANK moves by 8; "the 1st channel of the 8 appear[s] on … the Main Fader".
- A MASTER key switches its fader to the master fader in MCU DAWs.
- By default the UF1 and UF8 are synchronised (both sit on Layer 1 / Port 1).
- SSL documents how to make them independent in Logic: put the UF1 on Layer 1/Port 1 and the UF8 on Layer 2/Port 5, then drag the second Mackie Control *below* the first. That creates a separate Logic control-surface group ([SSL support](https://support.solidstatelogic.com/hc/en-gb/articles/11252527531037-How-to-make-UF1-and-UF8-act-as-independent-control-surfaces-in-Logic-Pro)).
- Exactly how SSL 360° merges the UF1 and UF8 when both are on Port 1 is UNVERIFIED.

**UC1**
- Controls only 360°-enabled plug-ins (and 360 Link-mapped third-party plug-ins) through the Plug-in Mixer, using a proprietary protocol. It plays no part in MCU banking.
- In the UF8's Plug-in Mixer layer there is an option "Fader banking follows UC1/Plug-in Mixer selection" (Guide p.102).

**Using the UF8 with other controllers**
- "Pro Tools supports a maximum of four HUI controllers… MCU may allow for up to six controllers" ([SSL: Using UF8](https://support.solidstatelogic.com/hc/en-gb/articles/4410035394321-Using-UF8)).
- So a bridge that adds its own HUI devices uses up some of Pro Tools' 4 HUI slots.

---

## 3. Meter data shown by the UF8
**What the UF8 shows**
- Each LCD shows "DAW Track Metering – 12-segment track metering + clip" in every DAW profile (Guide pp.24, 37, 61, …).
- Track names: Pro Tools 4 characters (8 via PTSL on v2.1.12+); Logic and Live 6 characters.
- The Plug-in Mixer layer shows its own input/output and dynamics meters from 360°-enabled plug-ins (proprietary, p.103).

**MCU meter messages (DAW→surface)**
- Message: `D0 yx`, where y = strip 0–7 and x = level.
- Level values: 0x0–0xC (REAPER can send 0xD), with `E` = clip on and `F` = clip off.
- There is **one meter per strip** (mono).
- Meter enable sysex: `F0 00 00 66 14 20 0s 0m F7` (`15` instead of `14` for an extender).
- The surface is expected to make the meter fall back on its own; REAPER's code says "they claim 1.8s for falloff".
- Sources: [REAPER SDK csurf_mcu.cpp](https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp) and [Ardour meter.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc).

**How each DAW maps dB to the 13 levels**

| DAW | Mapping |
|---|---|
| REAPER | Linear over −70…0 dB in 13 steps (about 5.4 dB per step); averages L and R peak. |
| Ardour | A piecewise curve from −70 to +6 dB. |
| Live | `int(output_meter_level*12)`; uses the input meter when the track is armed ([decompiled MackieControl/ChannelStrip.py](https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/blob/main/MackieControl/ChannelStrip.py)). |
| Logic | UNVERIFIED |

**Update rate:** depends on the DAW and is UNVERIFIED. REAPER sends from its run loop. Live sends on its display timer, believed to be about 100 ms.

**HUI meter messages (Pro Tools)**
- Poly aftertouch on MIDI channel 1: `A0 0c sv`, where c = strip, s = side (0 = L, 1 = R), v = 0x0–0xC.
- So HUI meters are **stereo**.
- One decoder's table: 0xC ≥ 0 dBFS (clip), 0xB ≥ −2, 0xA ≥ −4, 0x9 ≥ −6, 0x8 ≥ −8, 0x7 ≥ −10, 0x6 ≥ −14, 0x5 ≥ −20, 0x4 ≥ −30, 0x3 ≥ −40, 0x2 ≥ −50, 0x1 ≥ −60 ([orchetect swift-midi-controlsurfaces](https://github.com/orchetect/swift-midi-controlsurfaces/blob/main/Sources/SwiftMIDIControlSurfaces/HUI/HUISurfaceModel/Storage/HUISurfaceModelState%20StereoLevelMeter.swift), an MIT-licensed Swift HUI library).
- Pro Tools disables HUI metering when EUCON is active ([Neyrinck](https://neyrinck.com/help/channel-meters-not-working-for-pro-tools/)).

**Other useful MCU state in the same stream** ([REAPER csurf_mcu.cpp header](https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)):
- LEDs: `90 00-07` rec, `90 08-0F` solo, `90 10-17` mute, `90 18-1F` select (7F = on, 01 = blink).
- Fader position: `Ex` 14-bit pitch bend.
- LCD text: sysex `F0 00 00 66 14 12 <offset> <ascii> F7`, 2×56 characters, 7 per strip.
- Fader touch from the surface: `90 68-6F`.
- This is enough for solo/mute/select "mix focus", names and fader readouts.
- **There is no "bank offset" message in MCU.** The bank can only be inferred from names. REAPER does write the bank number to the 2-digit assignment display (CC 0x4A/0x4B), but other DAWs do not.

**Bottom line on resolution:** about 13 coarse steps per strip, mono for MCU and stereo for HUI. Large, smooth meters would need ballistics and interpolation in the app, or a separate high-resolution source (a per-track plug-in or a DAW API). That is outside SSL's scope.

---

## 4. Staying in sync with the UF8's current bank: options

### A) MIDI proxy (DAWWAY's design)
- DAWWAY's site describes its signal flow as "DAW → Dawway → Control Surface → Display" and its setup as "Connect DAWWAY ports in your DAW". It offers "up to 24 tracks (+2 extenders)" ([dawway.co.uk](https://dawway.co.uk/)).
- DAWWAY is Windows-only. Its tested DAWs do not include Logic or Pro Tools, though the UF8 and UF1 are on its list of surfaces it expects to work.
- **On macOS:**
  1. The app creates virtual Source/Destination pairs.
  2. The user points the DAW's Mackie/HUI device at them instead of SSL V-MIDI Port N.
  3. The app forwards every byte, including sysex, to "SSL V-MIDI Port N Destination" and relays "Port N Source" back to the DAW.
- **Pros:** an exact mirror of what the UF8 receives; works for every MCU and HUI DAW; works for several UF8s.
- **Cons:**
  - The UF8 depends on the app running.
  - It changes SSL's documented setup.
  - The app must correctly forward the handshake and device-inquiry sysex.
  - SSL will not support it.
  - It does not see content generated by SSL 360° itself (PTSL names and colours, Plug-in Mixer).
  - It cannot tell which layer the hardware is on.

### B) Passive spy on the Destination
- Apple's MIDIDriver.h, read from the local macOS SDK, says `MIDIDriverEnableMonitoring` makes MIDIServer "pass it every outgoing MIDI packet, to all destinations in the system (not just those controlled by itself)". Packets may arrive out of order. See [Apple MIDIDriverInterface](https://developer.apple.com/documentation/coremidi/mididriverinterface).
- MIDI Monitor uses exactly this: its spy covers normal output ports and "applications which act as destinations" ([snoize docs](https://www.snoize.com/MIDIMonitor/docs)). Reference code is SnoizeMIDISpy in [krevis/MIDIApps](https://github.com/krevis/MIDIApps), BSD-3-Clause.
- **Pros:** no change to the user's DAW or SSL setup; the app is not in the UF8's path.
- **Cons:**
  - It requires installing a CFPlugIn MIDI driver in `~/Library/Audio/MIDI Drivers`, which rules out the Mac App Store.
  - This is a legacy driver model, so future macOS versions are a risk.
  - Events must be reordered by timestamp.
  - It has the same blind spots as option A.
- Combine this with an ordinary connection to "SSL V-MIDI Port N Source" to see UF8→DAW traffic.

### C) DAW-native linked extenders (official DAW features)
These bank in lock-step with the UF8 but show *adjacent* strips.

| DAW | How extenders link | Can it mirror the UF8's own strips? |
|---|---|---|
| Logic | Devices in one control-surface group bank together. "BANK LEFT and BANK RIGHT … shift … by the total number of channels in the control surface group (e.g. Mackie Control + two XT → 24)" ([Logic Control Surfaces Support Guide PDF](https://help.apple.com/pdf/logicpro-css/en_US/logic-pro-control-surfaces-support-guide.pdf)). A separate group banks independently. | UNVERIFIED. The guide documents a per-device "Fader Bank Offset" (SSL uses 8/16/24). A virtual extender at offset 0 inside the UF8's group might mirror strips 1–8; this needs testing. |
| Studio One | Control Surface Group (Placement). | No (adjacent strips). |
| Live | XTs listed after the MackieControl become "right extensions" that bank together (decompiled script). | No (adjacent strips). |
| Pro Tools | HUI controllers 1–4 chain together. | No (adjacent strips). |
| Cubase | Multiple Mackie Control devices chain. SSL notes they can accidentally mirror. | Not reliably. |
| REAPER | All MCU/MCUEX instances share one static `m_allmcus_bank_offset`, and each has its own configurable offset ([csurf_mcu.cpp](https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)). | **Yes.** An extra MCUEX at offset 0 on the bridge's virtual port mirrors the UF8 exactly, without a proxy. |

- **Side effect:** adding extenders to the UF8's group or bank makes the UF8's BANK step equal to the total width (for example 24).
- **Suggested hybrid for 24 tracks:**
  - Use A or B for strips 1–8.
  - Use 2 virtual extenders grouped after the UF8 for strips 9–24.
  - In REAPER, use offset-0, 8 and 16 instances.

### D) SSL-side mechanisms
- There is no documented SSL 360° API or OSC interface for third parties.
- "360 Link" maps third-party plug-ins for UC1 and the Plug-in Mixer ([SSL 360 Link](https://solidstatelogic.com/products/ssl-360-link)). It is not a data API.
- The Plug-in Mixer layer uses SSL's proprietary protocol. When the UF8 is on that layer, nothing is visible over MIDI.

---

## 5. Physical dimensions and display fit
**UF8**
- 431 × 266 × 62.7 mm (W × D × H); 2.9 kg; 8 × 100 mm faders; 6U when rack-mounted (Guide p.7).
- **Strip pitch, derived by me:** I measured SSL's own front-panel drawing (Guide p.12, embedded at 2576 px). Its outline aspect is 2544 × 1569 px, which matches 431 × 266 mm to within 0.1%. That gives 0.1694 mm per px.
  - Pitch is **≈38.5 mm**, from 7 strip dividers at 99.3, 137.8, 176.4, 214.8, 253.4, 291.9 and 330.5 mm from the left edge, and LCD centres 227.4 px apart.
  - Strip 1 centre is about 80.7 mm from the left edge; strip 8 centre about 350.4 mm (80.6 mm from the right edge).
  - The 8-strip zone runs about 61–369 mm, roughly **308 mm wide**, centred on the chassis. Centre-to-centre from strip 1 to strip 8 is about 270 mm.
  - Each LCD outline is about 29.8 × 37.3 mm (about 1.9" diagonal). This is approximate because the drawing outline may include bezel.
  - Please confirm all of these with a ruler.
- **Two UF8s side by side:** the gap from strip 8 to strip 9 is about 161 mm between centres, not 38.5 mm. The bridge therefore needs separately positioned "bank windows", as DAWWAY has.

**UF1:** 205 × 265.9 × 62.5 mm; 1.8 kg (UF1 Guide p.6).

**Bar displays**

| Display | Active area | Fit with the UF8 |
|---|---|---|
| **12.6" 1920×515** | 309.31 × 82.97 mm (seller data, e.g. [eBay listing](https://www.ebay.de/itm/405438276638)); outline about 370 mm | ≈ the UF8's 8-strip zone (308 mm), about 240 px per strip. **Closest 1:1 match.** |
| 14" 3840×1100 (sold as 1920×550 too) | 344.2 × 98.6 mm ([DFRobot DFR1125](https://wiki.dfrobot.com/dfr1125/)) | Covers 8 strips with about 18 mm spare each side; about 430 px per strip at 4K. |
| 12.3" 1920×720 | 292.03 × 109.51 mm ([Winstar WF123BSWAYLNN0](https://unisystem.com/product/displays-lcd-tft/wf123bswaylnn0-winstar-12-3-1920x720-lcd-tft-display)) | Narrower than the 308 mm zone, but wider than the 270 mm centre-to-centre span, so 8 meters can still sit exactly above the strip centres. |
| 8.8" 1920×480 | 218.88 × 54.72 mm ([DFRobot FIT0941](https://wiki.dfrobot.com/_SKU_FIT0941_8.8_480%C3%971920_DSI_Bar_Touch_display_for_Raspberry_Pi)) | Too narrow; covers only about 5.7 strips. |
| "14" 1920×480" | — | I could not find this as a standard panel (UNVERIFIED). |
| 15.6"/16" bar | — | I found no confirmed active-area data. |

- **For 16 or 24 strips:** use one bar display per UF8. A single display would need about 720 mm or more of active width for 16 strips (≈29–37" stretched panels), and would still have to handle the gap between units.
- **Real-world examples:** I found no forum or Reddit examples of bar displays mounted above a UF8 specifically. DAWWAY's photos show similar setups with an iCON Platform M+/X+, an SSL Nucleus 2 and a Tascam US-2400.

## Open questions
- Which DAW will the user run with the UF8? This decides between REAPER's offset-0 MCUEX mirror (no proxy needed), a MIDI proxy (any DAW), or the driver spy approach.
- In Logic, can a virtual Mackie Control Extender with Fader Bank Offset 0 in the UF8's control-surface group mirror strips 1-8 rather than extend them? Does it change the UF8's BANK step? This needs a hands-on test.
- Does SSL 360 behave correctly when the DAW reaches the V-MIDI ports through a third-party proxy (handshake and device-inquiry sysex, Logic auto-detection, Cubase port-order quirk)? This is untested.
- How does SSL 360 combine a UF1 and a UF8 that share Layer 1/Port 1 (which strip the UF1 fader follows)? And can a third party detect which layer (1/2/3 or Plug-in Mixer) the UF8 is currently showing?
- How does Logic Pro map dB to MCU meter levels, how often does it send meter updates, and does it send meters only while the LCD meter mode is enabled?
- Is a CoreMIDI CFPlugIn monitoring driver (the SnoizeMIDISpy approach) still reliable on current macOS on Apple Silicon, and is it acceptable for distribution (notarisation, no App Store)?
- Does the user want larger, high-resolution meters than MCU/HUI's 13 levels can give? If so, which DAW-specific source (per-track plug-in, Live Remote Script, REAPER extension/OSC, Cubase MIDI Remote meters) is acceptable?
- Will the user run 1, 2 or 3 UF8s (8/16/24 strips), with or without a UF1 placed between them? This decides one bar display per unit versus a single long display, and the layout of the bank windows.
- The exact UF8 LCD size and active area, and the precise strip pitch, should be measured on the user's own unit with a ruler to confirm the ~38.5 mm figure derived from the drawing.

## Fact-check
- **CONFIRMED**: SSL 360 maps virtual MIDI ports by layer and unit: Layer 1 = SSL V-MIDI Ports 1-4 (UF8 #1-#4), Layer 2 = Ports 5-8, Layer 3 = Ports 9-12. A UF1 uses Port 1/5/9.
  - Mostly confirmed, but parts are inferred. SSL support articles state 'DAW Layer 1 = Port 1, DAW Layer 2 = Port 5, DAW Layer 3 = Port 9' (UF8 and UF1 DAW Compatibility articles 4410043451537 and 11251770264989). The Logic independence article puts the UF1 on Port 1 / Layer 1 and the UF8 on Port 5 / Layer 2. On this Mac, the SSL 360 log shows 'DawControlManager | SetPortDawType set 1 to Ableton Live Master' and 'set 2/3/4 to Ableton Live Extender'. That confirms Ports 1-4 = Layer 1, with Port 1 as master and Ports 2-4 as extender slots for UF8 #2-#4. Ports 6-8 and 10-12 are inferred by analogy and UNVERIFIED. The UF8 User Guide PDF is over 10 MB and could not be fetched, so its port table was not read directly. A UF1 shares the layer's first port with UF8 #1, which is why the two are synchronised by default. (https://support.solidstatelogic.com/hc/en-gb/articles/4410043451537-UF8-DAW-Compatibility)
- **CONFIRMED**: Pro Tools talks to the UF8/UF1 over HUI. Logic, Cubase/Nuendo, Live, Studio One, LUNA and Pyramix use MCU. The Plug-in Mixer layer uses SSL's proprietary protocol. SSL 360 also has dedicated profiles for Mixbus, REAPER, Bitwig, Digital Performer, FL Studio and Samplitude/Sequoia. Cakewalk is not supported.
  - The SSL article lists the profiles and says Cakewalk is not supported, but it does not give a protocol for each DAW. The per-DAW protocol comes from the SSL360Core 2.0.6 binary on this Mac, which contains the layer-option enum names ProToolsHui, LogicProMcu, CubaseMcu, AbletonLiveMcu, StudioOneMcu, LunaMcu, PyramixMcu, ReaperMcu and MixbusMcu. So REAPER and Mixbus also use MCU. Bitwig, Digital Performer, FL Studio and Samplitude appear only as '<DAW>MidiCodeDictionaryAdditions', so their protocol is UNVERIFIED (probably MCU). The Plug-in Mixer layer is not MIDI. SSL calls it 'VST3 extensions' with 360-enabled plug-ins, and the SSL 360 logs show plug-ins connecting over 'RemoteConnection'. The HTML article returns 403 to fetchers; the Zendesk API endpoint /api/v2/help_center/en-gb/articles/4408132094865.json works. (https://support.solidstatelogic.com/hc/en-gb/articles/4408132094865-Which-DAWs-work-with-UF8-UF1)
- **CONFIRMED**: On this Mac (SSL 360 2.0.6), SSL V-MIDI Ports 1-12 Source/Destination are CoreMIDI virtual endpoints owned by the SSL360Core process, with no driver. Any app can read the Sources (UF8->DAW), but DAW->UF8 traffic sent to the Destinations can only be seen by proxying or by a monitoring driver.
  - Verified locally. The installed version is 2.0.6.67265. A CoreMIDI enumeration found 12 'SSL V-MIDI Port N Source' and 12 'Destination' endpoints with no entity (so virtual) and no kMIDIPropertyDriverOwner. There is no SSL plug-in in /Library/Audio/MIDI Drivers. The running SSL360Core (PID 979) has libCoreMIDIWrapper.1.dylib loaded, which calls MIDISourceCreateWithProtocol / MIDIEventList (the UMP API). The SSL log says 'VirtualMidiPortManager | Created 12 Virtual MIDI Ports.' The endpoints report MIDI 1.0 protocol (kMIDIPropertyProtocolID = 1). In the public API, the read callback of a virtual destination belongs only to its creator. So proxying or a MIDIDriverEnableMonitoring driver are the only ways to see DAW->surface traffic. (https://developer.apple.com/documentation/coremidi/mididriverinterface)
- **UNCERTAIN**: The UF8 LCDs show 12-segment track metering plus clip, fed by the DAW's HUI/MCU meter data.
  - The 'fed by HUI/MCU' part is supported. The SSL UF8 FAQ (article 4404925512605) says metering and clip indicators can get stuck when banking with no audio, and calls this 'a bug inherited from the MCU and HUI protocols'. The '12-segment' count is UNVERIFIED: the UF8 User Guide PDF is over 10 MB and could not be fetched, and neither the SSL product page nor any support article states a segment count. Note that the hosts send 13 levels (0x0-0xC) or 14 (0x0-0xD), so the visible segment count may not equal the protocol resolution. On the Plug-in Mixer layer, the displays also show dynamics metering from 360-enabled plug-ins, which is not MIDI. (https://support.solidstatelogic.com/hc/en-gb/articles/4404925512605-UF8-FAQs)
- **CONFIRMED**: MCU meters are channel-pressure messages D0 yx: y = strip 0-7, x = level 0x0-0xC (some hosts send 0xD), 0xE = clip on, 0xF = clip off. There is one mono meter per strip, and the surface is expected to decay the meter itself (REAPER notes a claimed ~1.8 s falloff).
  - REAPER's csurf_mcu.cpp documents 'D0 yx : update VU meter, y=track, x=0..d=volume, e=clip on, f=clip off' and sends 0x0-0xD, mapped linearly over -70..0 dB from the mean of the L and R peaks. Its comment reads 'they claim 1.8s for falloff but we'll underestimate' and it uses 1.4 s. It sends a new value only when the peak rises above its own decayed estimate, so a receiver MUST implement its own decay or the meters will hang. Ardour's meter.cc also uses up to 13 segments plus 0xE/0xF overload. Ableton Live's MackieControl script (decompiled) sends int(output_meter_level*12), so 0x0-0xC, on a 100 ms timer, and sends no 0xE clip. The on-device decay behaviour is not described in any official, public MCU spec; that part rests on REAPER's comment only. Hosts also enable meters per strip with SysEx F0 00 00 66 14 20 <ch> <mode> F7. (https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)
- **CONFIRMED**: HUI meters are stereo poly-aftertouch messages A0 0c sv (s = side L/R, v = 0x0-0xC). The scale runs from 0xC >= 0 dBFS (clip) down to 0x1 >= -60 dBFS.
  - Confirmed in orchetect/swift-midi-controlsurfaces. kLevelMetersStatus = 0xA0, and encodeHUILevelMeter sends notePressure(note: channel 0-7, value: side<<4 | level 0x0-0xC). The documented table runs from 0xC >= 0 dBFS (red clip) down to 0x1 >= -60 dBFS, with 0x0 meaning no LEDs. Caveat: Avid has never published the HUI spec. This is a reverse-engineered, MIT-licensed implementation, so the dB thresholds are community-derived, not an official spec. (https://github.com/orchetect/swift-midi-controlsurfaces/blob/main/Sources/SwiftMIDIControlSurfaces/HUI/HUI%20Encode%20Utilities.swift)
- **CONFIRMED**: DAWWAY (Windows) works as a MIDI pass-through: the DAW connects to DAWWAY's ports and DAWWAY forwards to the control surface (DAW -> Dawway -> Control Surface -> Display). It offers up to 24 tracks plus 2 extenders. This design can be reproduced on macOS by proxying the SSL V-MIDI ports.
  - The page says 'Connect DAWWAY ports in your DAW', requires virtual MIDI ports to be set up first, and shows the chain PC/DAW -> Dawway -> Control Surface -> Display. 'Pass-through' is therefore a strong inference, but the page never uses that word or names MCU or HUI. 'Lite supports up to 24 tracks plus 2 extenders' is confirmed. The page lists SSL UF1, UF8 and Behringer WING as compatible, and no macOS version is mentioned. A macOS proxy is technically feasible: the bridge publishes its own virtual source/destination pairs, the DAW is pointed at them, and the bridge forwards to and from 'SSL V-MIDI Port N'. Caveats: the user must reconfigure the DAW's surface ports, the bridge becomes a single point of failure for the surface, and Pro Tools PTSL features in SSL 360 run outside MIDI and are unaffected. (https://dawway.co.uk/)
- **CONFIRMED**: CoreMIDI's MIDIDriverEnableMonitoring lets a driver receive every outgoing MIDI packet to all destinations in the system. MIDI Monitor's BSD-licensed SnoizeMIDISpy driver uses it to spy on destinations created by apps, so passively tapping 'SSL V-MIDI Port N Destination' is feasible.
  - The macOS 26.5 SDK header MIDIDriver.h says the driver receives 'every outgoing MIDI packet, to all destinations in the system', and the function is not deprecated. The header also warns that the Monitor function 'cannot rely on the MIDI events arriving in order'. krevis/MIDIApps is BSD-3-Clause, and SpyingMIDIDriver.cpp calls MIDIDriverEnableMonitoring and broadcasts packets keyed by the destination's uniqueID. Issue #118 shows spying on a virtual port created by another app working. Caveats: you must install a CFPlugin into ~/Library/Audio/MIDI Drivers (or /Library/...) that MIDIServer loads, as a universal arm64/x86_64 build. There are known issues: duplicated events (#111), a driver that did not load on a macOS 13.3 beta (#110), and timestamps passed through raw (#118). Tapping SSL V-MIDI destinations specifically was not tested on this Mac (UNVERIFIED), and App Store/sandbox compatibility is UNVERIFIED. (https://github.com/krevis/MIDIApps/blob/main/Frameworks/SnoizeMIDISpy/Driver/SpyingMIDIDriver.cpp)
- **CONFIRMED**: In Logic, devices in one control-surface group bank together, and BANK shifts by the total number of channels in the group (MCU + 2 XT = 24). A separate group banks independently. So a virtual extender grouped with the UF8 follows its banking but shows adjacent strips.
  - The Logic Pro Control Surfaces Support Guide (2025) says: 'If you are using a control surface group, the BANK LEFT and BANK RIGHT buttons shift the active channel strips by the total number of channels in the control surface group ... 24 channels.' Independent behaviour of a separate group is confirmed by SSL article 11252527531037. Important side effect: grouping a virtual extender with the UF8 makes the UF8's own BANK step 16 instead of 8, which changes the user's workflow. A grouped extender also cannot mirror the UF8's 8 strips; it always shows the next or previous 8. Mirroring the UF8 in Logic therefore needs a proxy or passive tap of the UF8's own port. Whether Logic requires an MCU device handshake for a virtual XT is UNVERIFIED. (https://help.apple.com/pdf/logicpro-css/en_US/logic-pro-control-surfaces-support-guide.pdf)
- **CONFIRMED**: In REAPER's built-in MCU support, all MCU/MCUEX instances share one global bank offset and each has its own configurable offset. An extra MCUEX instance at offset 0 on the bridge's virtual port would therefore mirror the UF8's 8 strips exactly.
  - Source: a static m_allmcus_bank_offset, and GetBankOffset() returns m_offset + 1 + m_allmcus_bank_offset unless CONFIG_FLAG_NOBANKOFFSET is set. OnBankChannel computes maxfaderpos from m_offset+8 across instances, so a second instance at offset 0 does not change the bank step. Caveats: this applies only if the UF8 uses REAPER's built-in 'Mackie Control Universal' surface. CSI or other surface extensions behave differently, and SSL 360's REAPER profile setup was not verified. Track-selection auto-banking also uses the shared offset. REAPER sends meter updates only on rising peaks, so the bridge must decay meters itself. (https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)
- **CONFIRMED**: SSL 360 v2.1.12+ gets 8-character Pro Tools track names and track colours through Avid's PTSL service, not HUI. Some UF8 display content therefore comes from SSL 360 itself and is not in the MIDI stream.
  - The SSL article says 'v2.1.12 and above: Displays show 8-character track names instead of 4, and Pro Tools track colours' and that these 'require SSL 360 to be connected to Pro Tools' PTSL service'. It was tested with Pro Tools 2025/2026; Pro Tools before 2024 will not work. Note that this Mac runs SSL 360 2.0.6, which has PTSL code (PtslManager and related strings are in the binary) but not the UF8 8-character name or colour feature. In 2.0.6, PTSL drives only the UC1/Plug-in Mixer track order and colour. (https://support.solidstatelogic.com/hc/en-gb/articles/38295880789789-Which-versions-of-Pro-Tools-and-SSL-360-are-required-to-access-the-enhanced-UC1-UF8-UF1-DAW-integration-features)
- **CONFIRMED**: By default the UF1 and UF8 are synchronised in Logic. They can be made independent by putting them on different layers/ports (1 and 5) and in separate Logic control-surface groups.
  - SSL article: by default the units are 'synchronised to control Logic Pro'. The steps are: UF1 Layer 1 / SSL V-MIDI Port 1 as the first Mackie Control, UF8 Layer 2 / Port 5 as the second Mackie Control, then drag the second device directly below the first in Logic's Control Surface Setup to create a separate group. (https://support.solidstatelogic.com/hc/en-gb/articles/11252527531037-How-to-make-UF1-and-UF8-act-as-independent-control-surfaces-in-Logic-Pro)
- **UNCERTAIN**: The UF8 measures 431 x 266 x 62.7 mm and weighs 2.9 kg. The UF1 measures 205 x 265.9 x 62.5 mm and weighs 1.8 kg.
  - UF8 confirmed on the SSL product page: '431 x 266 x 62.7 mm (Width x Depth X Height)', 2.9 kg unboxed (5.0 kg boxed). UF1 dimensions confirmed on the SSL UF1 product page: 205 mm wide, 265.9 mm (labelled 'Height' but front-to-back) and 62.5 mm (labelled 'Depth' but the actual height). The UF1 weight of 1.8 kg is UNVERIFIED: the product page does not list it and the UF1 user guide PDF is over 10 MB and could not be fetched. (https://www.solidstatelogic.com/products/uf8)
- **UNCERTAIN**: The UF8 channel-strip pitch is about 38.5 mm. Strip 1 is centred about 80.7 mm from the left edge, and the 8-strip zone is about 308 mm wide and centred. This is derived from SSL's to-scale front-panel drawing (aspect matches 431 x 266 mm within 0.1%), not from a published spec.
  - UNVERIFIED. The UF8 User Guide PDF (over 10 MB) could not be retrieved to check the drawing, and SSL publishes no strip-pitch spec. The numbers are self-consistent: 8 x 38.5 = 308 mm, (431 - 308) / 2 = 61.5 mm margins, and 61.5 + 19.25 = 80.75 mm. They still depend on the zone being centred, which is not confirmed. Measure the physical unit with calipers, or let the user calibrate in the app, before relying on these figures. (https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide.pdf)
- **UNCERTAIN**: A 12.6-inch 1920x515 bar panel (active area 309.31 x 82.97 mm) almost exactly matches one UF8's 8-strip zone. A 14-inch 3840x1100/1920x550 panel (344.2 x 98.6 mm) covers it with margin. A 12.3-inch 1920x720 panel (292 x 109.5 mm) is enough to centre 8 meters over the strips. An 8.8-inch 1920x480 panel (218.9 mm) is too narrow.
  - Only the 14-inch figure is confirmed from a primary source. DFRobot DFR1125 is 3840x1100 with an active area of 344.2 x 98.6 mm, an outline of 369.5 mm wide, Type-C/mini-HDMI input and 300 cd/m². The other active areas are UNVERIFIED but consistent with diagonal geometry: 12.6-inch 1920:515 gives about 309.1 x 82.9 mm, 12.3-inch 1920:720 gives about 292.5 x 109.7 mm, and 8.8-inch 1920:480 gives about 216.8-218.9 mm. All the 'matches the 8-strip zone' conclusions depend on the unverified 308 mm strip zone (claim 14). A 292 mm panel is about 16 mm short of a 308 mm zone, so the outer meters would sit up to about 8 mm inside the outer strip centres. For physical placement, check the bezel and outline width as well, not only the active area. (https://wiki.dfrobot.com/dfr1125/)

### Missed points
- The user's DAW is almost certainly Ableton Live 12. Evidence: Live 11 and 12 Suite and Pro Tools are installed. The latest Live 12.4.5 Preferences.cfg references MackieControl and MackieControlXT with SSL V-MIDI ports. The SSL 360 logs show Layer 1 = 'AbletonLiveMcu' for both the UF8 and the UF1, with Layers 2 and 3 unset, and 'SetPortDawType set 1 to Ableton Live Master', '2/3/4 to Ableton Live Extender'. Design for the Ableton Live MCU path first.
- Ableton's MackieControl script (decompiled, gluon/AbletonLive12_MIDIRemoteScripts) sends meters as D0 with int(output_meter_level*12), so only 13 levels (0x0-0xC). It sends them from update_display, which runs on a 100 ms timer (_Framework Defaults.TIMER_DELAY = 0.1), so about 10 Hz. The meters are mono, use the input meter when the track is armed, and no 0xE clip messages were seen. Meter sending also appears to be gated on is_pro_version, which needs a firmware-version reply above 50 to F0 00 00 66 14 13 00 F7 (decompiled code, so treat as UNVERIFIED). A large meter bridge fed only from MCU will look visibly stepped. For high-resolution stereo meters in Live, read the LOM output_meter_left/right (used by other Live scripts) from a custom Remote Script or a Max for Live device, and send them to the app over OSC/UDP.
- In Ableton Live, MackieControlXT instances attach to the main MackieControl as left or right extensions, and BANK moves by the total stacked strip count. As in Logic, a virtual XT added for the bridge would show adjacent strips and would change the UF8's bank step. Mirroring the UF8's own 8 strips needs a proxy or a passive tap of Port 1.
- The UF8, UF1 and UC1 are not class-compliant MIDI devices. They enumerate as vendor-specific 'SSL Control I/F' USB devices (vendor ID 12777 = 0x31E9, product IDs 33, 35 and 37, plus 'HID Controller' hubs). SSL360Core drives them through bundled ssld2xx.dylib and libFtdiUnixHelper (FTDI D2XX-style). The bridge cannot talk to the hardware directly; everything has to go through SSL 360's V-MIDI ports, and SSL 360 must be running.
- SSL 360 on this Mac is 2.0.6.67265, a .NET 8 app (CLR 8.0.15). SSL now documents 2.1.12 features (PTSL 8-character names and colours). Upgrading changes what appears on the UF8 displays but not the MCU meter stream.
- SSL's UF8 FAQ says meter and clip indicators can stick when banking with no audio, a bug 'inherited from the MCU and HUI protocols'. The bridge should clear or decay meters on bank or track changes and on a timeout. REAPER sends only rising meter values, so client-side decay is mandatory.
- The user drives SSL Meter Pro plug-ins (v1.2.8) from the UF1 through SSL 360's plug-in network link (log: 'RemoteConnection | Plugin[n]: Connected with plugin type EPT_MeterPro'). That metering travels over SSL's proprietary link, not MIDI, so the bridge cannot see it.
- The Behringer WING appears on this Mac as a class-compliant USB MIDI device ('WING' via com.apple.AppleMIDIUSBDriver, offline at check time). Unlike the SSL units, it could be addressed directly over CoreMIDI. Its DAW-remote protocol details (MCU or HUI emulation) were not verified here.
- MCU hosts enable per-strip metering with SysEx F0 00 00 66 14 20 <ch> <mode> F7. Ardour uses mode 0x07 and REAPER uses 0x03; Live sends a mode from bit flags. A passive tap does not need to handle this. An emulated surface or XT would need to answer host handshakes and version queries (Live's firmware query; Logic's handshake is UNVERIFIED).
- The DAWWAY page lists SSL UF1, UF8 and Behringer WING as compatible surfaces and shows an 'Instant Mix Focus' feature, which is a useful reference for the user's mix-focus requirement. Its DAW list is inconsistent (Cakewalk/Sonar appear in one section only), and it has no macOS build.
- Research limits: the web-search budget for this run was used up partway through. The UF8 and UF1 user guide PDFs are over 10 MB and could not be fetched, so the meter segment count, the per-unit port table for Ports 6-8 and 10-12, the strip pitch from the panel drawing and the UF1 weight are still UNVERIFIED against SSL's manuals. The SSL support HTML pages return 403, but the Zendesk API (support.solidstatelogic.com/api/v2/help_center/en-gb/articles/<id>.json) works for follow-up checks.
