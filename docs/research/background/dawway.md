# DAWWAY research and macOS alternatives

## 1. What DAWWAY is

- **Product.** DAWWAY Lite is a Windows desktop app that works as a second-screen meter bridge for control surfaces. You place "Fader Bank windows" on a display at eye level, directly above each 8-channel section of the surface ([dawway.co.uk](https://dawway.co.uk/)).
- **Launch and history.** The site says it launched on the last day of NAMM 2026 and calls it the developer's fourth iteration.
- **Author.** The author is a retired programmer and musician. The site's "Authors YouTube" link goes to the channel @ianwalker2258 (Ian Walker) ([channel](https://www.youtube.com/@ianwalker2258)). Support is a Forumotion forum ([dawway.forumotion.com](https://dawway.forumotion.com/)). The first admin posts are dated 13 Jan 2026.
- **Videos.**
  - "DAWWAY Lite Install", 6 Feb 2026 ([video](https://www.youtube.com/watch?v=UJhL4EqNPds)).
  - "DAWWAY Lite Control Surface Meter Bridge", 9 Feb 2026 ([video](https://www.youtube.com/watch?v=1i27ROlm4lw)).
  - "DAWWAY Lite Update | Solo Dimming, Peak Alerts & MCU Metering", 12 Feb 2026, demonstrated on an **SSL UF8** ([video](https://www.youtube.com/watch?v=QI_99Q6Yizg)).
- **No outside coverage.** Searches of Gearspace, Reddit, KVR and VI-Control found no third-party reviews or user threads. All evidence below comes from the developer's own site, forum and videos.

### Editions and pricing
- **DAWWAY Lite is free.** The Lemon Squeezy store lists one product at $0.00, described as metering for a control surface plus up to 2 extenders ([dawway.lemonsqueezy.com](https://dawway.lemonsqueezy.com/)).
- **Free registration unlocks 24 tracks**, meaning one surface plus 2 extenders ([dawway.co.uk](https://dawway.co.uk/)).
- **DAWWAY Pro is planned, not released.** The site says "later this year" and its comparison table says "3 months". Pro adds:
  - track text and labels
  - analogue meters
  - theming
  - DAW-specific features: long track names, marker buttons ("Buttonised Markers") and automated track numbering

  Some Pro content is commented out in the page's HTML, so the Pro scope and status are UNVERIFIED.

### Distribution and platform
- **Windows only.**
  - The page HTML says the download goes to a ClickOnce page, and the download page links to `https://dawway.co.uk/DAWWAY_V2.application`. ClickOnce is a Windows/.NET deployment method ([download page](https://dawway.co.uk/DAWWAY-lite.html)).
  - The site screenshots show Windows 11 window chrome.
  - Setup depends on Windows MIDI Services 2 or loopMIDI-type virtual port drivers.
- **No Mac version yet.**
  - The forum has Logic and Pro Tools sections. The only Logic post (13 Jan 2026) says Logic support needs multi-platform development and that RTP-MIDI (network MIDI) might work in the short term ([t37](https://dawway.forumotion.com/t37-dawway-lite-release-countdown)).
  - The only Pro Tools post (2 Feb 2026) says "Initial testing" ([t44](https://dawway.forumotion.com/t44-release-countdown)).
  - This matches the gap the user described: there is no macOS equivalent.
- **System requirements are not published.** Windows 10/11 with .NET is an inference; I did not inspect the ClickOnce manifest.
- **The download page asks for your DAW, surface and extender count** and sends them to a Google Form. Choices include Logic, Ardour, PreSonus FaderPort 8/16 and Frontier AlphaTrack, which are not on the home page lists.

## 2. How DAWWAY gets meter levels and track info

DAWWAY is **not a plugin**. It is a Mackie Control (MCU) MIDI proxy that sits between the DAW and the physical surface:

- **Signal chain.** The site's diagram shows DAW → DAWWAY → Control Surface → Display. The forum introduction says DAWWAY "sits in between the two from a midi perspective" and needs a fixed set of MIDI ports ([t17](https://dawway.forumotion.com/t17-introduction-to-dawway)).
- **Port model.**
  - Each 8-channel unit gets one virtual port pair. Names are `WAY_IN_1`/`WAY_OUT_1` for the main surface and `WAY_IN_2`/`WAY_OUT_2` for extender 1, continuing in sequence.
  - On Windows, the ports are created with loopMIDI, Bome Virtual MIDI or LoopBe. Windows MIDI Services 2 creation is "coming soon" ([t43](https://dawway.forumotion.com/t43-creating-virtual-midi-ports-for-dawway)).
- **What the DAW is told.** You configure the DAW as standard Mackie Control devices on those ports:
  - Cubase: "Mackie Control" plus "Mackie Control 2" on WAY_IN_2/WAY_OUT_2 ([t21](https://dawway.forumotion.com/t21-setting-up-dawway-to-work-with-cubase-nuendo)).
  - Cakewalk: "Mackie Control - 1" plus "Mackie Control XT -1". Meters must be switched on under Utilities → Mackie Control because they are off by default ([t42](https://dawway.forumotion.com/t42-setting-up-dawway-to-work-with-cakewalk-sonar)).
  - Ableton: "Mackie Control" plus "Mackie Control XT" ([t19](https://dawway.forumotion.com/t19-setting-up-dawway-to-work-with-ableton)).
  - FL Studio: "Mackie Control" plus "Mackie Control 2" ([t23](https://dawway.forumotion.com/t23-setting-up-dawway-to-work-with-fl-studio)).
- **Inference: DAWWAY passes traffic through and reads it.** It then opens the real surface's MIDI ports and forwards traffic both ways. Along the way it reads the MCU messages it needs:
  - meter levels: Channel Pressure `D0 sv`
  - solo, mute, select and record LEDs
  - LCD scribble-strip SysEx

  The video description confirms the meter source: it works across MCU-compatible DAWs and surfaces using standard Mackie protocols ([video](https://www.youtube.com/watch?v=QI_99Q6Yizg)).
- **It also injects control messages.** The Feb 2026 update added fine-resolution fader moves from the on-screen UI, and the banking buttons send commands to the DAW. So DAWWAY writes MCU commands (faders/pitch-bend, bank) into the DAW-bound stream, not just reads.
- **Custom SysEx extensions for richer data.** These need DAW-side scripts. The only documented example is an FL Studio script.
  - Common header: `F0 7D 44 57 <cmd> …` (0x7D is the non-commercial manufacturer ID; 44 57 is "DW").
  - `01` Full track name: slot (0–7), absolute index (0–127), then 7-bit ASCII up to `F7` ([t40](https://dawway.forumotion.com/t40-long-file-names)).
  - `02` Marker list: count, then entries with a 14-bit ID, 28-bit position in ticks, and a length-prefixed name ([t40](https://dawway.forumotion.com/t40-long-file-names)).
  - `10` Single track colour, 11 bytes, proposed ([forum section f2](https://dawway.forumotion.com/f2-system-exclusive-new-functionality-specifications-and-demos)).
  - `11` Bank Colour Burst: `F0 7D 44 57 11 <surface 00-03> R0 G0 B0 … R7 G7 B7 F7`, 31 bytes. RGB values are 7-bit, scaled ×2 by DAWWAY ([t46](https://dawway.forumotion.com/t46-dawway-sysex-extension-command-0x11-bank-color-burst)).
  - `12` and `13` are reserved.
  - Messages from DAWWAY to the DAW: CC#100 jumps to marker N; CC#101 requests a marker-list resend ([t41](https://dawway.forumotion.com/t41-marker-go-to-buttons-in-dawway-ui)).
  - The developer recommends a separate loopback port for this companion channel so it never reaches the hardware.

## 3. Banking

- **What the UI shows.** A site screenshot (SSL Nucleus 2, 16 tracks) shows a small "DAWWAY Lite" main window with Meters, Settings and Help menus and a "Banking Controls" box. It has "Full Bank Down" and "Full Bank Up" buttons, with a note that each click banks by 16 tracks.
- **Interpretation.** A "full bank" equals the total number of strips across surface plus extenders (16 = Nucleus 2's two 8-strip sections).
- **Mechanism: UNVERIFIED.** It is most likely repeated MCU Bank Left/Right notes (`0x2E`/`0x2F`), or a DAW-specific bank size. No documentation found.
- **Meters follow the DAW's bank.** In MCU, the DAW only sends meters for strips currently mapped to a device.

## 4. Feature list (Lite, as of Feb 2026)

From the site and the Feb 2026 video description ([dawway.co.uk](https://dawway.co.uk/), [video](https://www.youtube.com/watch?v=QI_99Q6Yizg)):

- **Layout**
  - Fader Bank windows sized to the surface and extenders.
  - Works on one display, an ultrawide or several monitors, with touchscreen support.
  - The layout persists between launches.
- **Meter sizes and styles**
  - Sizes range from compact overview to large "mix focus" meters.
  - Styles include "Standard" segmented LED and "Cylinder".
  - "Bespoke meter settings" let you adjust behaviour and look.
- **Mix Focus**
  - Highlights the soloed track and dims the rest.
  - Global dimming is adjustable; solo/cut dimming runs 10–90% and the setting persists.
  - Selected-track indicators.
- **Peak alerts**
  - Flashes when a track exceeds its previous maximum.
  - Optional "fireworks" effect; flash duration is adjustable.
- **Meter animation:** ceiling spin, flow shading, spread speed and pulse speed.
- **Micro fader adjustments:** fine-resolution fader control from the UI.
- **Support forum** opens from inside the app.
- **Track count:** 8 per unit. The free registration allows up to 24 tracks (surface + 2 extenders). The setup form offers up to 5 extenders, but the licence covers 2.
- **Not in Lite:** track names or labels. Each strip's label shows the "DAWWAY" placeholder in the screenshots.

### Observed visuals and ballistics (from site screenshots, inference)
- **Segmented LED bars** are green, turning yellow/orange and then red near the top. Some styles show twin columns per track, but with identical heights, so they look decorative rather than true L/R.
- **A floating peak-hold line** sits above each meter with a numeric dB readout, for example -1.7 dB or -13.0 dB. Readouts turn orange or red near 0 dB.
- **The peak values look quantized.** In the 24-track Tascam US-2400 / Mixbus shot, the same values repeat (-6.0, -7.3, -8.9, -10.9 dB). That fits a mapping from MCU's coarse 13-step meter levels to a fixed dB table. This is an inference, not confirmed.
- **Caption mismatch.** The site's captions call screenshot-2 "iCON Platform M/X" and screenshot-3 "SSL Nucleus 2". The images on disk match those captions, although the HTML reuses one file name for two captions.

## 5. Supported DAWs and surfaces
- **DAWs listed as tested:** Ableton Live, Bitwig, Cubase/Nuendo, Luna, FL Studio, Mixcraft, Reaper, Reason, Studio One. A separate site list adds Cakewalk/Sonar and MOTU Digital Performer, and the screenshots show Mixbus.
- **DAWs that are Mac-relevant but not supported:** Logic (forum only, needs multi-platform work) and Pro Tools (initial testing; would need HUI).
- **Surfaces (about 40 listed, MCU-class):** includes **SSL UF1, UF8, Nucleus and Nucleus 2** and **Behringer Wing**, plus X-Touch, iCON, Mackie MCU/XT, Avid Artist, Tascam US-2400 and others. The site says roughly 400 DAW/surface combinations exist and not all are tested. **SSL UC1 is not listed.**

## 6. Protocol facts that matter for a Mac build

- **MCU meters (community-documented spec).**
  - The message is `D0 sv`: the high nibble is the strip (0–7), the low nibble the level.
  - Levels `0x0`–`0xC` map roughly: 0 = <-60 dB, 1 = -60, 2 = -50, 3 = -40, 4 = -30, 5 = -20, 6 = -14, 7 = -10, 8 = -8, 9 = -6, A = -4, B = -2, C = 0 dB.
  - `D` = >0 dB, `E` = set overload, `F` = clear overload.
  - The surface applies its own decay of about 300 ms per segment.
  - The dB mapping depends on the host DAW.
  - Source: [TouchMCU protocol doc](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md).
  - **Consequence:** an MCU-sourced meter bridge only gets about 13 discrete levels per track, in mono, and must draw its own ballistics and peak hold.
- **Other MCU messages** (same source):
  - Rec / Solo / Mute / Select LEDs are notes `0x00–07`, `0x08–0F`, `0x10–17` and `0x18–1F`. Velocity 0 = off, 1 = blink, 0x7F = on.
  - Bank Left/Right are notes `0x2E`/`0x2F`; Channel Left/Right are `0x30`/`0x31`.
  - Faders use 14-bit pitch-bend on MIDI channels 0–8.
  - LCD text is SysEx `F0 00 00 66 14|15 12 pp …` (`14` = main unit, `15` = XT).
  - Meter mode SysEx: command `20` sets channel meter mode; `21` sets global LCD meter mode.
- **SSL UF8 / SSL 360°** (from the UF8 user guide, Rev 1.5, Jan 2021, [PDF](https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide_Rev1.5.pdf)):
  - The UF8 talks to the DAW through SSL 360°'s driver, which appears as virtual ports "SSL V-MIDI Port 1…12". Layer 1 uses ports 1–4 for UF8 units 1–4, Layer 2 uses 5–8, Layer 3 uses 9–12.
  - Protocol is MCU for Logic, Cubase, Nuendo, Studio One and Live, and HUI for Pro Tools.
  - The UF8's own LCDs show "12-segment track metering + clip".
  - The FINE/SHIFT key gives fine control in most DAWs.
  - **Implication:** a Mac DAWWAY-style proxy would sit between the DAW and the SSL V-MIDI ports.
- **SSL 360° v2.1 (Aug 2026)** added deeper Logic and Pro Tools integration (track colours, 8-character names), Plug-in Mixer scaling, and Meter Pro instances following the DAW's track selection. It did not add an external meter-bridge view ([Mix](https://www.mixonline.com/the-wire/ssl-enhances-the-industry-standard-u-series-controller-ecosystem-with-ssl-360-v2-1-update)).
- **Behringer Wing** offers MCU or HUI emulation over USB or DIN. Behringer's Cubase setup adds 3 Mackie Control devices, giving 24 channels. On macOS the DAW ports show as WING ports, and the docs map Mackie Control 1/2/3 to WING Port 3/2/1 ([WING DAW Documentation](https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf)). The search summary did not confirm whether Wing receives MCU meters.
- **macOS advantage.** A Mac app can create its own virtual MIDI sources and destinations with CoreMIDI (`MIDISourceCreateWithProtocol` / `MIDIDestinationCreateWithProtocol`). No loopMIDI-style third-party driver is needed ([Apple](https://developer.apple.com/documentation/coremidi/mididestinationcreatewithprotocol(_:_:_:_:_:))). macOS also has the IAC Driver and built-in Network MIDI (RTP-MIDI).

## 7. Existing macOS alternatives and how each gets its data

| Product | Type / platform | Data source | Notes |
|---|---|---|---|
| **Evergreen Audio Meter Bridge (free) / Meter Bridge Pro** | macOS 11+ app; iPad version too | Plugin instances (Mini Meter, Massive Meter, Massive Meter Pro; AAX/VST3/AU) found via Bonjour and streamed over TCP/IP, plus direct CoreAudio input | The closest Mac "external meter bridge". Free version: 8 meters. Pro: up to 384 channels, $299 perpetual, iLok. Custom layouts, separate meter windows for dedicated displays. Meter types include Sample Peak, RMS, K-12/14/20, VU, PPM and Dorrough (Pro). Peak hold is configurable; refresh 15/30/60 fps. Not tied to any control surface, with no solo/mute mix-focus beyond Massive Meter Pro's track-override for Record/Mute/Solo state ([product](https://evergreen.audio/products/meter-bridge-pro), [docs](https://evergreen.audio/pages/documentation), [free](https://evergreen.audio/products/meter-bridge)) |
| **Kaizen PRISM** | Plugins on macOS 12+; Monitor app on Mac (macOS 14+, Apple Silicon only) and iPad | "Connect" plugins stream up to 12 named, colour-coded stems plus the master over the network | Has a MULTI-METER BRIDGE module; up to 4 screens can follow one machine; €249 one-off. Info comes from Production Expert partner content ([Production Expert](https://www.production-expert.com/production-expert-1/kaizen-prism-first-look-a-multi-tool-for-metering-off-your-daw)) |
| **Ardour / Harrison Mixbus Meterbridge** | Built into the DAW (Mac, Windows, Linux) | Native DAW meters | Separate window with all track meters; selectable meter types (Peak +6 dBFS, K-meters); optional mute, solo, rec and monitor buttons ([Ardour manual](https://manual.ardour.org/meterbridge/)) |
| **SSL 360° Plug-in Mixer / Meter Pro** | SSL software, macOS and Windows | SSL 360-enabled plugin instances (Channel Strip 2, 4K B/E, Bus Comp, Meter Pro) report to SSL 360° | Shows an overview of SSL plugin instances with I/O metering. Only covers tracks that host SSL plugins; not a general per-track meter bridge ([SSL support](https://support.solidstatelogic.com/hc/en-gb/articles/16921756365597-360-Link-360-Bus-Compressor-Feature-Summary)) |
| **iZotope Visual Mixer + Relay** | Plugin ecosystem | Inter-plugin communication from Relay, Neutron or Nectar instances on tracks | Mainly a control and placement view; meter data goes to Insight 2 and Neutron. Relay is no longer sold standalone ([iZotope](https://www.izotope.com/en/products/visual-mixer.html)) |
| **TouchMCU (TouchOSC mk2 layout)** | iPad/tablet; computer side via TouchOSC Bridge | Emulates an MCU device on the TouchOSC Bridge virtual MIDI ports | GPL-3.0. Closest open-source analogue to "MCU emulator as a display"; replaces the deprecated OscMackieControl (Mac/Windows, MIT, Qt5) ([TouchMCU](https://github.com/NicoG60/TouchMCU), [OscMackieControl](https://github.com/NicoG60/OscMackieControl)) |
| **mcpdisp** | Linux / JACK only | Accepts MCU display messages on a JACK MIDI port and draws scribble strips, LEDs and meters | Proves the "render MCU feedback on screen" idea; not available on Mac ([Ubuntu appstream](https://appstream.ubuntu.com/noble/universe/metainfo/mcpdisp.html)) |
| **AbletonOSC** (data source, not a product) | Ableton Live remote script | OSC calls such as `/live/track/get/output_meter_level`, `_left`, `_right`; supports `start_listen` | Higher-resolution meters (0–1 float) than MCU's 13 steps. A route a Mac app could use for Ableton ([README](https://github.com/ideoforms/AbletonOSC)) |
| **Reaper OSC** | Built into Reaper | `/track/@/vu` OSC feedback | Existing TouchOSC templates show per-track VU meters (UNVERIFIED in detail) |
| **Logic Remote, Avid Control, Studio One Remote, V-Control Pro** | iPad remote apps | DAW-specific network protocols (V-Control Pro uses DAW plugins) | Show mixer meters on an iPad, not on a bar display aligned with the hardware ([V-Control](https://neyrinck.com/?p=57707)) |
| **The DAW's own second window** | Native | Native | Ableton's View → Second Window can show the mixer on another monitor, but it cannot be sized per strip to match the hardware ([Ableton help](https://help.ableton.com/hc/en-us/articles/209071749-Dual-Monitor-Support)) |
| **reFuse Simple Meter** | Per-track plugin (AU/VST3/AAX) | Draws inside each plugin window | A do-it-yourself meter bridge built from floating plugin windows ([reFuse](https://www.refusesoftware.com/simplemeter)) |

**Conclusion.** No Mac product combines all three things DAWWAY does: a passive or active MCU proxy, a layout that matches a specific control surface's strips, and mix-focus driven by the surface's solo/mute/select state. Evergreen Meter Bridge Pro and Kaizen PRISM are the nearest Mac metering apps, but both rely on plugin instances and know nothing about the control surface.

## 8. Design implications for the user's Mac app
- **Copy DAWWAY's architecture natively.** Have the app publish CoreMIDI virtual MCU ports to the DAW, forward traffic to and from the SSL V-MIDI ports (UF8) or WING ports, and parse meters, LEDs and LCD text along the way.
- **Accept MCU's limits:** meters are mono, have about 13 levels, and with a single UF8 only the 8 banked strips get meters.
- **24 tracks with one UF8** needs the app to register as 2 extra virtual MCU extenders in the DAW (UNVERIFIED that DAWWAY does this), or a higher-resolution DAW-specific feed: AbletonOSC, ReaScript/OSC, Logic's MCU/Scripter, or a meter plugin as Evergreen does.
- **Pro Tools** would require handling HUI, which has a different meter encoding (UNVERIFIED).

## Open questions
- Which DAW does the user run on the Mac? It decides the data path: an MCU proxy (Logic, Live, Cubase, Studio One), HUI (Pro Tools), or a DAW-specific higher-resolution feed (AbletonOSC, Reaper OSC/ReaScript, meter plugins).
- Can DAWWAY show meters for more tracks than there are physical faders, for example 24 meters with a single UF8, by registering 'phantom' MCU extenders that are not forwarded to hardware? The docs only describe one port pair per physical unit.
- How does DAWWAY's 'Full Bank' (16-track) button work? Repeated MCU Bank Right (0x2F) presses, Channel Left/Right, or DAW-specific bank sizes? And how does it stay in sync when banking from the hardware?
- Where do DAWWAY's numeric peak-hold dB readouts come from, given MCU's roughly 13-step meter resolution? The screenshots suggest a quantized dB table; is there any interpolation, and is it peak or a ballistics model?
- How does DAWWAY coexist with SSL 360°'s V-MIDI ports and UF8 layers, and do the UF8's own LCD meters, scribble strips and colour features still work through the proxy?
- Does Mix Focus read solo state from MCU solo LED notes (0x08–0x0F) only, and how does it handle DAW-specific solo semantics such as solo-safe or exclusive solo?
- Exact system requirements and .NET runtime for DAWWAY. The ClickOnce manifest was not downloaded or inspected.
- When will DAWWAY Pro ship (the site says both '3 months' and 'later this year'), and will a macOS build or RTP-MIDI bridge for Logic follow?
- How does the Behringer Wing handle MCU meter messages from the DAW, and are they available to a proxy?
- What is the HUI meter message format, needed if the user mixes in Pro Tools through the UF8's HUI mode? (Not verified here.)
- Would the user accept MCU-resolution meters (about 13 steps, mono), or do they need higher-resolution stereo meters? Higher resolution implies a plugin- or OSC-based data source, like Evergreen or AbletonOSC.

## Fact-check
- **CONFIRMED**: DAWWAY Lite is a standalone Windows meter-bridge app, not a plugin. It sits between the DAW and the control surface as a MIDI intermediary (DAW → DAWWAY → Control Surface).
  - Supported by three sources. The intro post says DAWWAY 'sits in between the two from a midi perspective'. The homepage diagram reads 'PC: DAW → Dawway → Control Surface → Display'. The download is a ClickOnce deployment manifest (https://dawway.co.uk/DAWWAY_V2.application): assemblyIdentity DAWWAY_V2.application, version 1.0.0.58, processorArchitecture msil, compatibleFrameworks .NET Framework 4.5 Full, publisher Ian Walker. That makes it a standalone .NET Framework (WinForms-style) desktop app, not a plugin. (https://dawway.forumotion.com/t17-introduction-to-dawway)
- **CONFIRMED**: DAWs are set up to talk to DAWWAY as standard Mackie Control (MCU) devices over virtual port pairs named WAY_IN_n/WAY_OUT_n, one pair per 8-channel surface or extender (for example 'Mackie Control 2' on WAY_IN_2/WAY_OUT_2 in Cubase and FL Studio, and 'Mackie Control XT' in Ableton and Cakewalk).
  - The core is confirmed: one WAY_IN_n/WAY_OUT_n pair per 8-channel unit. The DAW input is WAY_IN_n and the DAW output is WAY_OUT_n. The Cubase screenshot shows Mackie Control on WAY_IN_1/WAY_OUT_1, plus Mackie Control 2 and Mackie Control 3. Three details need correcting. (1) The FL Studio thread reuses the Cubase wording, but its screenshot (https://i.servimg.com/u/f17/20/64/08/87/fl_stu10.jpg) shows FL's 'Mackie Control Universal' and 'Mackie Control Universal Extender' scripts on WAY_OUT_1..3 and WAY_IN_1..3, not 'Mackie Control 2'. (2) The Ableton thread text says 'Mackie Control XT', but its screenshot (https://i.servimg.com/u/f17/20/64/08/87/ableto11.png) shows the vendor script 'Icon V and P Series' on ports shown as 'WAY IN 1/2/3' and 'WAY OUT 1/2/3'. So DAWWAY passes through whatever MCU-dialect script matches the physical surface; generic MCU is not strictly required. (3) Cakewalk uses 'Mackie Control - 1' and 'Mackie Control XT -1' (https://dawway.forumotion.com/t42-setting-up-dawway-to-work-with-cakewalk-sonar). (https://dawway.forumotion.com/t21-setting-up-dawway-to-work-with-cubase-nuendo)
- **CONFIRMED**: DAWWAY's meter data comes from standard Mackie (MCU) protocol messages. The Feb 2026 update video was demonstrated on an SSL UF8 and says it applies to any MCU-compatible surface and PC-based DAW.
  - The video 'DAWWAY Lite Update | Solo Dimming, Peak Alerts & MCU Metering' (Ian Walker) was published 2026-02-12. Its description says the demo is on an SSL UF8 and that 'everything shown applies to any Mackie MCU-compatible control surface and PC-based DAW'. It also says it uses 'standard Mackie protocols, with extended functionality available via SysEx'. Caveat: DAWWAY's own spec post says MCU meters are 'Host-dependent. Some DAWs do not emit meters by default' (https://dawway.forumotion.com/t40-long-file-names). I found no evidence of HUI support, which Pro Tools needs. (https://www.youtube.com/watch?v=QI_99Q6Yizg)
- **CONFIRMED**: DAWWAY is Windows-only: it is distributed via ClickOnce (DAWWAY_V2.application) and relies on Windows MIDI Services 2 or loopMIDI/Bome/LoopBe virtual ports. The Logic forum post says Logic support needs multi-platform development, with RTP-MIDI as a possible short-term route.
  - The facts are right, but the cited URL (t37) only supports the Logic sentence. Its full text is '13:01:2026 Requires Multi-platform development though use of RTP-Midi may be a possibility in the short term - requires more analysis.' The other facts come from elsewhere. ClickOnce: https://dawway.co.uk/DAWWAY-lite.html sets DOWNLOAD_APPLICATION_URL = 'https://dawway.co.uk/DAWWAY_V2.application', and that manifest targets .NET Framework 4.5. Virtual port options (WMS2, loopMIDI, Bome Virtual MIDI Ports, LoopBe/LoopBe30): https://dawway.forumotion.com/t43-creating-virtual-midi-ports-for-dawway. Automatic WMS2 port creation is still 'Coming Soon'. Note that the install-configuration page lists 'Logic' and 'Ardour' as selectable DAWs, but no Logic or Pro Tools setup guide exists. (https://dawway.forumotion.com/t37-dawway-lite-release-countdown)
- **CONFIRMED**: DAWWAY Lite is free ($0 on Lemon Squeezy). Free registration unlocks up to 24 tracks (surface + 2 extenders). A Pro edition adding track names, analogue meters, theming and DAW-specific features is announced but not released.
  - The Lemon Squeezy store (https://dawway.lemonsqueezy.com/) lists 'DAWWAY Lite $0.00', described as metering 'for a control surface and up to 2 extenders'. The homepage says 'Get up to 24 tracks (+2 extenders) completely free'. Its Lite vs Pro table gives Pro as track text/labels, analogue meters, theming and 'DAW Dependent new Functionality' (long track names, buttonised markers, automated track numbering), with availability '3 Months' and 'later this year'. The page fetched on 2026-10-11 still shows Pro as unreleased, though the page may be stale. The unregistered limit is implied to be one 8-channel surface but is not stated explicitly. (https://dawway.co.uk/)
- **CONFIRMED**: Lite features include: layouts sized to the surface and extenders; multi-monitor, ultrawide and touchscreen support; a persistent layout; multiple meter sizes; Standard and Cylinder styles; Mix Focus solo highlight with adjustable 10–90% dimming of other tracks; selected-track indicators; peak alerts on a new track maximum; meter animation controls; and fine-resolution 'micro fader' adjustments.
  - The features come from two sources. The homepage covers layouts, monitors, touch, persistence, sizes, and the Standard and Cylinder styles (from image captions). The video description covers the rest. It words the dimming as 'Solo / Cut dimming control – Adjustable mute dimming from 10% to 90%, with persistent settings', so dimming applies to solo and cut (mute) states. Peak alerts are 'visual peak flashing when a track exceeds its previous maximum level', with an optional 'fireworks' effect and adjustable flash duration. Animation controls are ceiling spin, flow shading, spread speed and pulse speed. 'Micro fader adjustments' are 'Fine-resolution fader control for precise mix tweaks during playback', which implies DAWWAY sends fader data to the DAW and is not view-only. How micro-fader is triggered (modifier key, touch, drag) is UNVERIFIED. (https://www.youtube.com/watch?v=QI_99Q6Yizg)
- **CONFIRMED**: The Lite UI has 'Full Bank Down/Up' buttons, each banking by 16 tracks (the full width of a 16-strip setup). How it sends the bank commands to the DAW is undocumented (UNVERIFIED; likely MCU Bank Left/Right notes 0x2E/0x2F).
  - Screenshot-3 (Bitwig with SSL Nucleus 2, 16 tracks) shows a 'DAWWAY Lite' window with a 'Banking Controls' group. It reads 'Jump directly to different regions of your DAW project. Each click will bank by 16 tracks.' and has 'Full Bank Down' and 'Full Bank Up' buttons. The bold '16' is probably computed from the configured unit count (UNVERIFIED). The wire mechanism is still UNVERIFIED. MCU Bank Left/Right are notes 0x2E/0x2F (https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md), but one press normally banks by 8 per host implementation. A 16-track jump may therefore need repeated presses or a DAW-specific behaviour. (https://dawway.co.uk/screenshot-3.png)
- **CONFIRMED**: DAWWAY defines private SysEx extensions with header F0 7D 44 57 (cmd 01 full track name, 02 marker list, 10/11 track and bank colours) plus CC#100/101 for marker navigation. These are sent by DAW-side scripts; the documented example is an FL Studio script.
  - The header and commands check out. In F0 7D 44 57 <cmd>, 7D is the non-commercial ID and 44 57 is ASCII 'DW'. 0x01 is Tooltip/Full Name: slot, absIndex, then ASCII name (t40). 0x02 is Marker List Update: COUNT, then entries of ID_HI, ID_LO, 4x7-bit position, NAME_LEN, name (t40). CC#100 is Goto Marker and CC#101 is a full-state refresh (t41). The FL Studio bundle is the documented reference, and FL's MIDI settings show a 'DAWWAY_V2' controller script. Caveats: the t46 namespace table marks 0x10 (Single Track Color, 11 bytes) and 0x11 (Bank Color Burst, 31 bytes) as 'Proposed', and 0x12/0x13 as 'Reserved'. The surface index is limited to 00–03, so the protocol caps at 4 units. The spec advises carrying these private messages on 'a dedicated loopback port pair (DAW script -> companion UI)' separate from the MCU stream. RGB is 7-bit, scaled x2. (https://dawway.forumotion.com/t40-long-file-names)
- **CONFIRMED**: MCU meters are Channel Pressure messages D0 sv (strip in the high nibble, level 0x0–0xC ≈ <-60 dB to 0 dB, plus 0xE/0xF overload set/clear), with about 300 ms per segment decay on the surface side. The dB mapping depends on the host, so an MCU-sourced meter bridge gets only about 13 mono steps per track.
  - Confirmed with one nuance: the TouchMCU table also lists 0xD = '100 % (> 0 dB)'. The level values are 0x0–0xD (14 states including off), plus 0xE (set overload) and 0xF (clear overload). The doc says 'The decay is automatic at a rate of about 300 ms per division' and 'The signal level mapping is host implementation dependant'. The host enables LCD meters with Mackie SysEx 0x20 (channel meter mode) and 0x21 (global LCD meter mode), so a proxy must pass these through. MCU meters are mono per strip. DAWWAY's screenshots draw two equal-height columns per track and repeat quantized peak readouts (-1.7, -2.9, -7.0 dB), which fits mono, coarse MCU data. Note that TouchMCU is a community reverse-engineering doc, not an official Mackie spec. (https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)
- **CONFIRMED**: The SSL UF8 talks to the DAW through SSL 360°'s driver, which appears as 'SSL V-MIDI Port 1–12' (Layer 1 = ports 1–4 for UF8 units 1–4, and so on). It uses MCU for Logic, Cubase, Nuendo, Studio One and Live, HUI for Pro Tools, and its LCDs show 12-segment track metering plus clip.
  - Confirmed by the UF8 User Guide Rev 1.5 (January 2021). Layer 1 uses ports 1–4, Layer 2 ports 5–8 and Layer 3 ports 9–12. The guide gives 'DAW Track Metering - 12-segment track metering + clip', and Logic uses Mackie Control plus Mackie Control Extender, each incrementing the port. Caveat: the guide is outdated on DAW support. The current UF8 page (https://www.solidstatelogic.com/products/uf8) lists dedicated SSL 360° profiles for Pro Tools, Logic Pro, Cubase/Nuendo, Ableton Live, Studio One, LUNA, Pyramix, Mixbus, REAPER, Bitwig, FL Studio, Samplitude/Sequoia and Digital Performer, and mentions SSL 360 V2.1. Which protocol each newer profile uses was not verified. (https://www.solidstatelogic.com/assets/uploads/downloads/UF8/SSL%20UF8%20User%20Guide_Rev1.5.pdf)
- **CONFIRMED**: Behringer Wing offers MCU or HUI DAW emulation over USB/DIN. Behringer's Cubase setup uses 3 Mackie Control devices (24 channels) on WING ports.
  - Confirmed through search-index excerpts of the official 'WING DAW-CONTROL V 1.0' PDF. Direct fetches of the mediavalet URL returned HTTP 500, so I could not re-read it in full. The excerpts say DAW mode emulates MCU or HUI over USB or DIN. USB is required for MCU plus 2 extenders, while DIN is limited to Control plus a single MCU. Ports: MIDI DAW 1 (macOS: WING 1) is the main unit, DAW 2 (WING 2) is Extender 1, DAW 3 (WING 3) is Extender 2, and MIDI Control (WING 4) is general MIDI. Cubase uses three Mackie Control devices assigned in reverse order (Mackie Control 1 → WING port 3 ... Mackie Control 3 → WING port 1). Changing the WING's clock rate or USB channel count briefly drops USB MIDI. (https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf)
- **CONFIRMED**: Evergreen Audio Meter Bridge Pro is the closest existing Mac external meter bridge. It is a macOS 11+ app that collects meters from its own plugin instances via Bonjour + TCP/IP (and from CoreAudio inputs): up to 384 channels, custom layouts and windows, $299 with iLok. It has no control-surface awareness.
  - The core facts are confirmed. The docs say 'Apple's Bonjour system for discovering plugins and TCP/IP for communication'. The product page gives macOS 11+, a PACE iLok USB requirement, and $299 perpetual with a free trial; Shopify variant data agrees. The app has Meter Windows and a Meter Editor. Three nuances. (1) The 384 figure is the CoreAudio input channel cap ('supports up to 384 channels of CoreAudio input'). No cap on plugin meters is stated, and the free Meter Bridge does 8 CoreAudio channels. (2) It needs a Mini Meter, Massive Meter or Massive Meter Pro plugin inserted per track (AAX, VST3 or AU per the v26 docs). (3) It does read a Mackie HUI input, but only as a timecode source for its Counter. It does not follow banks, solo, mute or select. (https://evergreen.audio/pages/documentation)
- **REFUTED**: Other Mac options are partial. Ardour/Mixbus have a built-in Meterbridge window. Kaizen PRISM streams up to 12 stems from Connect plugins to a multi-meter bridge view. SSL 360°'s Plug-in Mixer only covers SSL plugin instances. TouchMCU emulates an MCU on an iPad via TouchOSC Bridge.
  - Only the SSL part is wrong. Ardour: confirmed. Its Meterbridge is 'a compact view of all meters in a session', with per-track name, peak reset, rec-arm, mute/solo/monitor buttons and selectable meter types. TouchMCU: confirmed. The README says it generates a TouchOSC layout and uses TouchOSC Bridge's virtual MIDI pair as a 'Mackie Control Universal' device, so it is a separate MCU unit, not a mirror of a hardware surface's bank. Kaizen PRISM: 'up to twelve stems' plus a Master instance and a Multi-Meter Bridge come only from Production Expert's first look (https://www.production-expert.com/production-expert-1/kaizen-prism-first-look-a-multi-tool-for-metering-off-your-daw). The primary manual was not retrieved, so this is UNVERIFIED. SSL: wrong or outdated. SSL 360° Link, a free shell plug-in, hosts third-party VST3 plug-ins, and those mapped instances appear in the SSL 360° Plug-in Mixer, which UF8 and UF1 can control. The SSL Meter plug-in is also 360-enabled. Whether the Plug-in Mixer shows per-track level meters was not verified. (https://manual.ardour.org/meterbridge/)
- **CONFIRMED**: On macOS an app can create its own virtual MIDI ports with CoreMIDI (MIDISourceCreateWithProtocol / MIDIDestinationCreateWithProtocol), so a Mac version of DAWWAY's proxy needs no loopMIDI-style third-party driver.
  - Apple's docs say each 'Creates a virtual source/destination in a client', available on macOS 11.0+. The destination's receive block runs 'on a separate high-priority thread owned by Core MIDI', and Apple advises reassigning the same unique ID on each launch so other clients keep persistent references. Caveats: virtual endpoints exist only while the app is running. The legacy MIDISourceCreate and MIDIReceived pages now show a deprecation marker, so use the MIDIEventList/UMP APIs. macOS also has a built-in IAC Driver for user-created virtual buses as a fallback. (https://developer.apple.com/documentation/coremidi/mididestinationcreatewithprotocol(_:_:_:_:_:))
- **CONFIRMED**: AbletonOSC exposes per-track output meters (/live/track/get/output_meter_level, _left, _right) with start_listen subscriptions. This gives a higher-resolution source than MCU for Ableton users.
  - The README lists /live/track/get/output_meter_level, output_meter_left and output_meter_right. It says 'Changes for any Track property can be listened for by calling /live/track/start_listen/<property> <track_index>'. It also exposes mute, solo, arm, color and /live/view/start_listen/selected_track. Caveats: it is a third-party Remote Script (ideoforms), not an Ableton product. It needs Live 11 or later, uses UDP ports 11000 and 11001, and takes one Control Surface slot alongside the UF8's MCU slots. Values are Live's normalized meter level, not dBFS. The real update rate under listening was not verified. (https://github.com/ideoforms/AbletonOSC)
- **UNCERTAIN**: No independent user reports or reviews of DAWWAY were found on Gearspace, Reddit, KVR or VI-Control. All evidence comes from the developer's site, forum and YouTube channel.
  - I could not re-run an independent search because this session's web-search budget ran out, so the absence is UNVERIFIED. The developer's own forum does have at least one non-developer user: a Yamaha 01X owner in the Cubase thread reporting that DAWWAY did not see the mLAN MIDI ports. The homepage testimonials are unattributed. Admin's forum profile shows a join date of 2026-01-08 and about 35 posts. (https://dawway.forumotion.com/t21-setting-up-dawway-to-work-with-cubase-nuendo)

### Missed points
- DAWWAY is a transparent MIDI pass-through, not an MCU emulator. The DAW-side script can be a vendor MCU dialect: the Ableton guide screenshot uses the 'Icon V and P Series' script on WAY IN/OUT ports. A Mac clone must forward every byte unchanged in both directions, only sniffing meters, LEDs and LCD text. That includes the MCU/Logic Control host-connection SysEx handshake (device query, serial and challenge/response: 0x00–0x03 in the TouchMCU doc), which Logic uses.
- DAWWAY is bidirectional, not view-only. 'Micro fader adjustments' (fine-resolution fader control from the app) and the 'Full Bank Up/Down' buttons both inject messages toward the DAW. MCU faders are 14-bit Pitch Bend on MIDI channels 0–8, and touch notes run 0x68–0x70. Injecting fader moves while the motorized UF8 fader is also live needs touch arbitration, and DAWWAY's approach to this is UNVERIFIED. This bears directly on the user's 'hold Shift for fine moves' requirement.
- Pro Tools with the UF8 uses HUI, not MCU. HUI meters use status 0xA0 (poly aftertouch, hijacked) with data 'strip, sv': high nibble 0 = left or 1 = right, low nibble level 0x0–0xC, 12 segments, stereo. HUI also needs ping/keepalive handling. DAWWAY shows no evidence of HUI support (no Pro Tools or Logic setup guides). A Swift, MIT-licensed HUI host/surface implementation with meter decoding exists: orchetect/swift-midi-controlsurfaces (formerly MIDIKit, split in April 2026), at https://github.com/orchetect/swift-midi-controlsurfaces.
- Mute, solo, select and rec states come over MCU as Note On LED feedback: REC 0x00–0x07, SOLO 0x08–0x0F, MUTE 0x10–0x17, SELECT 0x18–0x1F. 7-character track names come in LCD SysEx F0 00 00 66 14 12 offset text. These are the inputs for the user's 'mix focus' (solo, mute, select highlight) feature (https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md).
- For the UF8, a Mac proxy would sit between the DAW and SSL 360's 'SSL V-MIDI Port n' endpoints. The DAW is pointed at the app's virtual ports, and the app connects to SSL V-MIDI Port 1..4 Source/Destination for Layer 1. SSL 360's layer must still be set to the right DAW profile. SSL now ships dedicated UF8 profiles for 13 DAWs, including REAPER, Bitwig, FL Studio, LUNA, Mixbus and Digital Performer, which is more than the 2021 guide lists.
- UF1 and UC1 do not need meter alignment the way UF8 does. UF1 adds transport, jog and an MCU master fader ('MCU DAWs only'), and shows SSL Meter plug-in visuals on its 4.3-inch display. UC1 controls SSL Channel Strip/Bus Compressor and 360° Link-hosted third-party VST3 plug-ins through SSL 360. So the UF8's 8 strips per unit (up to 4 units, 32 faders) are what the bridge must line up with (https://www.solidstatelogic.com/products/uf1).
- The UF8 already has related native features: a FINE mode key for V-Pot parameters, dimming of non-selected tracks on the LCDs in Plug-in mode, and an F1 command that clears clip indicators. These are useful references for the Shift-fine and mix-focus design (UF8 User Guide Rev 1.5).
- Behringer WING on macOS exposes its DAW ports as 'WING 1', 'WING 2', 'WING 3' (main plus 2 extenders) and 'WING 4' (control). USB is required for 24-channel MCU. Changing the WING's USB audio configuration or clock briefly drops USB MIDI, so the proxy must handle endpoints disappearing and reappearing (CoreMIDI notifications). Cubase maps WING ports in reverse order.
- CoreMIDI virtual endpoints exist only while the app runs. If the DAW starts first, it may not see them. Set kMIDIPropertyUniqueID to the same value each launch so Logic, Cubase and others remember the assignment. The legacy MIDISourceCreate and MIDIReceived APIs now show deprecation markers in Apple's docs; use the MIDIEventList/UMP 'WithProtocol' APIs (macOS 11+).
- DAWWAY's SysEx extension caps surface index at 00–03, so 4 units or 32 tracks, while Lite registration caps at a surface plus 2 extenders (24 tracks). DAWWAY recommends carrying private messages on a separate loopback port pair so physical MCU devices never see them. A Mac version could reuse this F0 7D 44 57 protocol for long names, colours and markers.
- DAWWAY Lite is a .NET Framework 4.5 ClickOnce app (manifest version 1.0.0.58, msil), and its UI is WinForms-style per the screenshot. No code can be ported to macOS, and the developer himself says Logic and Mac support 'Requires Multi-platform development' (forum post dated 13 Jan 2026).
- The MCU meter resolution limit is visible in DAWWAY's own screenshots. Peak readouts repeat a small set of values (-1.7, -2.9, -4.2, -5.0, -7.0, -10.3, -13.0 dB), and each track's two columns are always the same height, which fits mono 0x0–0xD MCU data drawn in a stereo-looking style. Higher-resolution or true stereo metering needs a DAW-side source such as AbletonOSC, a ReaScript/OSC bridge, or a per-track plug-in like Evergreen's.
