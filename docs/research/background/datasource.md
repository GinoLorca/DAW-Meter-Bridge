# How a Mac meter bridge can get per-track meters and track data from DAWs, with an SSL UF8 in use

## 0. Summary for the build decision

- **No single source covers every DAW.** The approach that works everywhere is to **passively read what the DAW already sends to SSL 360°**, because that traffic is exactly what the UF8 shows: its current bank, names, mute/solo/select/rec states and coarse meters. On top of that, add a **DAW-specific source for high-resolution meters and colours**:
  - Ableton: a Remote Script.
  - Pro Tools: PTSL plus an optional AAX plugin.
  - Reaper: OSC or its extension API.
  - Cubase: a MIDI Remote script.
  - Logic: Mackie Control (MCU) only.
- **MCU/HUI meters are coarse.** MCU gives 13 levels per strip and is mono. HUI gives 12 segments, left and right. Ableton's own MCU script sends them only about 10 times per second. That is fine as a fallback but too coarse for a "much larger" meter bridge.
- **What is installed on this Mac** (read-only inspection):
  - Installed: Ableton Live 11 Suite, Ableton Live 12 Suite (12.4.5), Pro Tools, SSL 360 (2.0.6.67265) and SoundFlow. Logic Pro, Cubase and Reaper are not installed.
  - Live 12's log shows control surface slot 1 = `MackieControl`, input "SSL V-MIDI Port 1 Source", output "SSL V-MIDI Port 1 Destination". Slots 4–6 = `MackieControlXT`, with no ports assigned. Slot 3 = a custom `AbletonMCP` remote script.
  - SSL 360 publishes 12 app-owned virtual CoreMIDI endpoint pairs, "SSL V-MIDI Port 1…12 Source/Destination". Its CoreMIDI wrapper imports `MIDISourceCreateWithProtocol` and `MIDIDestinationCreateWithProtocol`.
  - This strongly suggests the user's main DAW is **Ableton Live (Suite, so Max for Live is available)**, with Pro Tools second. This still needs confirming with the user.

## 1. Emulating Mackie Control Universal (MCU) and extenders over CoreMIDI virtual ports

**Wire format.** Byte-level reference: [TouchMCU protocol doc](https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md), checked against [Ardour mackie/meter.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc), Ardour's [surface.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/surface.cc) and Reaper's open-source [csurf_mcu.cpp](https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp).

- **SysEx header:** `F0 00 00 66 dd …`. The device ID `dd` is:
  - `0x14` Mackie Control
  - `0x15` MCU XT
  - `0x10` Logic Control
  - `0x11` Logic Control XT
  - `0x05` HUI
- **Meters:** channel pressure on MIDI channel 1, `D0 sv`.
  - `s` (high nibble) = strip 0–7. `v` (low nibble) = level.
  - Levels: `0x0` = below −60 dB, `0x1`–`0x8` = green (≥−60 up to ≥−8 dB), `0x9`–`0xB` = yellow (≥−6/−4/−2 dB), `0xC` = 0 dB/clip.
  - `0xE` sets overload, `0xF` clears it. `0xD` is treated as ">0 dB / 100%" by some hosts. Reaper uses `0xD` as full scale.
  - The surface lets the level decay by itself. TouchMCU says about 300 ms per segment; a Reaper comment says the vendor claims 1.8 s full fall. So hosts resend levels rather than streaming a waveform.
  - The dB-to-segment curve depends on the host:
    - Ardour uses a piecewise dB curve mapped to 13 segments.
    - Reaper maps −70…0 dB linearly onto `0x0`–`0xD` and emulates decay in software.
    - Live sends `int(output_meter_level*12)`.
  - **Effective resolution is about 3.7 bits, mono, one value per strip.**
- **Meter mode SysEx:**
  - `F0 00 00 66 14 20 ss mm F7` is per-strip mode. `mm` bits: bit0 = signal LED, bit1 = peak hold, bit2 = LCD level meter. Ardour sends `0x07`/`0x00`; Reaper sends `0x03`.
  - `F0 00 00 66 14 21 gg F7` is the global LCD meter orientation (`00` horizontal, `01` vertical). A [Steinberg forum](https://forums.steinberg.net/t/mackie-c4-pro-and-cubase/146910/107) report shows Cubase sending `…21 01`.
  - Logic cycles LCD meter modes with Shift+Name/Value. The SIGNAL LEDs keep working in every mode ([Apple guide](https://support.apple.com/guide/logicpro-css/ctls72224fdb/mac)).
- **Scribble strip (LCD):** `F0 00 00 66 14 12 pp <ASCII…> F7`.
  - `pp` = 0x00–0x6F. The top row is 0x00–0x37, the bottom row 0x38–0x6F. That is 2×56 characters, or **7 characters per strip**.
  - Track names sit in the top row (truncated or abbreviated by the host).
- **LEDs:** note-on, velocity `7F` = on, `01` = blink, `00` = off.
  - Rec arm `0x00–0x07`, Solo `0x08–0x0F`, Mute `0x10–0x17`, Select `0x18–0x1F`.
  - V-Pot pushes `0x20–0x27`. Fader touch `0x68–0x6F` (master `0x70`). Bank left/right `0x2E`/`0x2F`, channel left/right `0x30`/`0x31`.
  - Faders use pitch bend on channels 0–7 (channel 8 = master), 14-bit.
  - Two-digit assignment display: CC `0x4A`/`0x4B`. Reaper writes its bank offset there.
- **Handshake:**
  - The host sends a device query `F0 00 00 66 14 00 F7`. An MCU answers `01` + 7-byte serial + 4-byte challenge, and the host treats it as online.
  - Logic Control IDs (`0x10`/`0x11`) do a challenge/response (`02` → `03` or `04`); the algorithm is in TouchMCU and Ardour.
  - The firmware version request `…13 00` is answered by `…14 'V' 'x' '.' 'x' 'x'`.
  - **Live-specific gotcha:** Live's `MackieControl` script sets `is_pro_version = major_version > 50`, which means the ASCII digit after 'V' must be ≥ '3'. Its meter code depends on that flag. An emulator that does not answer the version request may get **no meters from Live**. This comes from decompiled code ([gluon/AbletonLive12_MIDIRemoteScripts MackieControl.py](https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/blob/main/MackieControl/MackieControl.py)); the decompiled branch structure is garbled, so the exact condition is approximate.
- **Update rate:**
  - **Live:** sends MCU meters from `update_display`, which runs on `TIMER_DELAY = 0.1` s, so **10 Hz**. Its source value is `output_meter_level`, a hold peak with a 1 s hold ([ChannelStrip.py](https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/blob/main/MackieControl/ChannelStrip.py), [_Framework/Defaults.py](https://github.com/gluon/AbletonLive12_MIDIRemoteScripts/blob/main/_Framework/Defaults.py)).
  - **Logic, Pro Tools, Cubase:** UNVERIFIED. Measure with MIDI Monitor's "Spy on output to destinations" on "SSL V-MIDI Port 1 Destination".
  - Virtual CoreMIDI ports have no 31.25 kbaud limit.
- **24 channels** = 3 units (MCU + 2 XT), each on its own virtual port pair (sources and destinations). DAWWAY's "up to 24 tracks (+2 extenders)" and its MCU/XT compatibility lists ([dawway.co.uk](https://dawway.co.uk/)) suggest it uses this model (inferred, UNVERIFIED). The Behringer Wing also uses three MCU ports ("WING 1/2/3") for 24 channels ([WING DAW doc](https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf)).
- **Metadata available:** names (7 characters), mute/solo/select/rec, fader position, V-Pot rings, timecode. **No track colour** in standard MCU. There is also no explicit bank index; Reaper's assignment display is an exception.
- **Setup friction:** low to medium. The user adds 1–3 "Mackie Control/XT" devices and picks the app's ports, and the app must be running before the DAW opens.
- **Engineering effort:** low. Prior art includes Ardour, Reaper's csurf_mcu and TouchMCU.

**How banking groups work in each DAW.** This decides whether an emulated unit can follow the UF8.

- **Logic:** icons placed in one horizontal row form one group, and left-to-right order sets strip order. Separate rows are independent groups, each with its own "Fader Bank" offset ([Apple 9.1.6 setup guide](https://help.apple.com/logicpro/mac/9.1.6/en/logicpro/controlsurfacessupport/chapter_1_section_5.html)). SSL's own article creates independent UF1/UF8 groups by stacking icons vertically ([SSL support, via search](https://support.solidstatelogic.com/hc/en-gb/articles/11252527531037-How-to-make-UF1-and-UF8-act-as-independent-control-surfaces-in-Logic-Pro)). So an emulated XT in the UF8's group shows the **next** 8 tracks, not the same 8.
- **Ableton Live:** the `MackieControl` script attaches `MackieControlXT` instances as left or right extensions by script order. They are stacked contiguously ("stack_offset += NUM_CHANNEL_STRIPS") and bank together. An XT therefore never mirrors the UF8's strips.
- **Reaper:** all MCU instances share one static `m_allmcus_bank_offset`, and each has its own `m_offset`. `CONFIG_FLAG_NOBANKOFFSET` turns sharing off. **An emulated MCU with surface offset 0 exactly mirrors the UF8 bank**, and offsets 8 and 16 give the neighbouring banks. This is high confidence, from source.
- **Pro Tools (HUI):** up to 4 HUI controllers × 8 = 32 channels (forum and Neyrinck sources). It is UNVERIFIED that they bank as one contiguous surface.

## 2. HUI emulation

Meter format: poly aftertouch `A0 0c sv`.
- `c` = strip 0–7. `s` (high nibble) = side: 0 = left, 1 = right. `v` = 0x0–0xC.
- So it is **stereo, 12 segments**, with roughly the same thresholds as MCU: ≥0, −2, −4, −6, −8, −10, −14, −20, −30, −40, −50, −60 dBFS.
- Sources: [orchetect/swift-midi-controlsurfaces HUIConstants.swift / StereoLevelMeter](https://github.com/orchetect/swift-midi-controlsurfaces) (MIT, Swift, macOS; useful as a dependency) and DrivenByMoss `HUIControlSurface.updateVuMeters` (sends `channel` and `0x10+value`).

Other HUI details:
- **Ping:** the host sends `90 00 00` and the surface must reply `90 00 7F`.
- **Names:** only **4 characters**, via `F0 00 00 66 05 00 10 <cell> <4 chars> F7`.
- **Switches:** zone/port pairs via CC `0x0C`/`0x2C` toward the surface and `0x0F`/`0x2F` toward the host.
- HUI meters reportedly stop working in Pro Tools when EUCON is enabled ([Neyrinck](https://neyrinck.com/help/channel-meters-not-working-for-pro-tools/)), and Avid has treated HUI as legacy since about PT 8.0.5.
- The UF8 uses HUI in Pro Tools. SSL 360 v2.1.12+ adds 8-character names and track colours by **also connecting to Pro Tools' PTSL** ([SSL support, via search](https://support.solidstatelogic.com/hc/en-gb/articles/38295880789789-Which-versions-of-Pro-Tools-and-SSL-360-are-required-to-access-the-enhanced-UC1-UF8-UF1-DAW-integration-features); [SoS news](https://www.soundonsound.com/news/ssl-360deg-gets-major-update)). SSL does the same layering this report recommends.

## 3. Metering plugin (AU/VST3/AAX/CLAP) streaming float levels over IPC

**Meter quality.** True float peak and RMS per audio block (for example 256 samples at 48 kHz ≈ 188 updates per second), any ballistics, stereo or multichannel.

**IPC options:**
- Localhost UDP/OSC: simplest, typically under 1 ms.
- POSIX shared-memory ring buffer: lowest overhead.
- XPC/Mach.

Sandboxed hosts (GarageBand, AUv3 extensions) need sandbox-safe IPC such as an app-group container or XPC. Whether Logic hosts AUv2 out of process or sandboxed in current versions is UNVERIFIED.

**Track metadata available to the plugin, by format:**
- **VST3 `IInfoListener::setChannelContextInfos`** ([Steinberg](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical+Documentation/Change+History/3.6.5/IInfoListener.html)):
  - Keys: `kChannelNameKey`, `kChannelColorKey`, `kChannelIndexKey`, `kChannelIndexNamespaceKey`/`…OrderKey`, `kChannelUIDKey`, and `kChannelPluginLocationKey` (pre-fader, post-fader or panner).
  - Live has supported it since 10.1.2, with name, index and colour ([Live 10 release notes](https://www.ableton.com/en/release-notes/live-10/)).
  - Bitwig, Cubase and Reaper are reported to work. FL Studio does not call it (forum sources).
- **PreSonus Plug-in Extensions `IContextInfoProvider`** ([ipslcontextinfo.h in Ardour](https://github.com/Ardour/ardour/blob/master/libs/vst3/pslextensions/ipslcontextinfo.h)):
  - Keys: `name`, `index`, `color`, `selected`, `focused`, `volume` (float), `pan`, `mute`, `solo`. Several are read/write.
  - Supported in Studio One, Live 10.1.9+ (name and index confirmed; mute/solo UNVERIFIED in Live), Reaper 5.5+ and Ardour.
  - **This is the only plugin route that exposes mute and solo.**
- **AU:** `kAudioUnitProperty_ContextName` / `AUAudioUnit.contextName` gives the **name only**. Updates on rename are unreliable in some hosts (Logic MIDI FX, Live 10/11, Reaper) ([Apple forum](https://developer.apple.com/forums/thread/744380)).
- **AAX:** `AAX_eNotificationEvent_TrackNameChanged` (Pro Tools 11.2+) gives the name only. `TrackUIDChanged` and `TrackPositionChanged` are marked "not currently sent" (AAX_Enums.h in JUCE). Shipping AAX also requires an Avid developer agreement and PACE signing.
- **CLAP `track-info`:** name, colour, channel count, and is-return/bus/master flags. Not available in Logic or Pro Tools.
- **JUCE** `AudioProcessor::updateTrackProperties` passes `name` and `colourARGB` only.

**Mute and solo.** Without the PreSonus extensions the plugin cannot know them, so read them from the MCU/HUI LEDs or a DAW API.

**Pre-fader problem.** Insert plugins usually sit pre-fader (Logic, Pro Tools, Live devices, Reaper's default). The bridge would show **pre-fader** levels and keep showing signal on muted tracks, unlike the DAW's post-fader meters. Options:
- Put the plugin in a post-fader slot where possible (`kChannelPluginLocationKey` reports this).
- Apply a correction: pre-fader dB plus fader gain, using the fader from PreSonus `volume` or MCU pitch bend (the curve is host-specific, UNVERIFIED).

**Setup friction:** high. One plugin instance per track (24 inserts), saved in every session, plus mapping each instance to its strip. **Engineering effort:** medium (JUCE or CLAP wrapper), plus AAX signing.

## 4. DAW-specific APIs

- **Ableton Live:**
  - The Live Object Model `Track` exposes `output_meter_left`/`_right`: "smoothed momentary peak", 0–1, get/observe, tracks with audio output only. It also exposes `output_meter_level` (hold peak, 1 s), `name`, `color` (0x00rrggbb), `color_index`, `mute`, `solo`, `arm`, `muted_via_solo` and `is_visible` ([Cycling '74 LOM Track](https://docs.cycling74.com/apiref/lom/track/)). Ableton warns that meter observers "add a significant load to Live GUI resource usage".
  - **[AbletonOSC](https://github.com/ideoforms/AbletonOSC)** (MIT, about 826 stars): `output_meter_level/left/right` are in `properties_r`, so `/live/track/start_listen/output_meter_left <idx>` works. It also covers name, colour, mute, solo, arm and `/live/view/start_listen/selected_track`. UDP ports: 11000 in, 11001 out. Its incoming tick is 100 ms; listener push rate is UNVERIFIED. The 0–1 meter scale is non-linear (UNVERIFIED mapping), so calibrate it.
  - **Remote Scripts:** Python 3 Remote Scripts can open UDP sockets; AbletonOSC and the user's existing `AbletonMCP` do. Max for Live (`live.observer`) is an alternative now that Suite is installed.
  - Remote scripts get `connect_script_instances(instanciated_scripts)`, which MackieControl itself uses to find its XTs. A custom bridge script could therefore find the UF8's `MackieControl` instance and read its private bank offset (`__bank_cha_offset`). This would be fragile and is UNVERIFIED.
  - The LOM `ControlSurface` object exposes no bank offset ([LOM ControlSurface](https://docs.cycling74.com/apiref/lom/controlsurface/)).
- **Logic Pro:**
  - The public route is MCU/HUI only.
  - Logic 10.7+ dropped third-party Control Surface plug-ins (OSCulator notice; medium confidence).
  - Logic's OSC surface support (TouchOSC/Lemur layouts, and SSL's new "SSL 360 OSC Device", which needs SSL 360 v2.1.12 and Logic 11/12) is undocumented and partner-only. Its meter or colour addresses are UNVERIFIED.
  - Scripter is MIDI-only.
  - So for Logic: meters from MCU (coarse) or a plugin (AU gives name only). **Colours are not obtainable** through public routes.
- **Pro Tools:**
  - HUI (4-character names, 12-segment stereo meters).
  - **PTSL** (gRPC; [py-ptsl protobuf stubs](https://github.com/iluvcapra/py-ptsl)) offers `GetTrackList` with `Track{name, id, index, color, track_attributes{is_muted, is_soloed, is_selected, is_record_enabled, is_hidden, is_inactive…}}`, plus `SubscribeToEvents` with `EId_TrackSoloStateChanged`, `EId_TrackMuteStateChanged` and `EId_TrackRecordEnabledStateChanged`.
  - **PTSL has no meter commands.** `GetTrackControlInfo` covers only Volume, Pan, LFE, Mute and PluginParameter.
  - EUCON's SDK is for software to be *controlled by* Avid surfaces, and partner/NDA terms apply ([Avid](https://developer.avid.com/eucon/)). It is not a practical route for a third-party surface.
  - High-resolution meters would need an AAX plugin.
- **Cubase/Nuendo MIDI Remote API** ([steinbergmedia/midiremote_api_doc d.ts](https://github.com/steinbergmedia/midiremote_api_doc)):
  - `MR_MixerChannelValues` has `mVUMeter`, `mVUMeterMax`, `mVUMeterClip`, `mVUMeterPeak`, `getVUChannelMeterByChannelIndex()`, plus `mMute`, `mSolo`, `mSelected`, `mRecordEnable`, `mOnTitleChange` and `mOnColorChange`.
  - **It can read meters** as normalized floats. [bjoluc/cubase-mcu-midiremote](https://github.com/bjoluc/cubase-mcu-midiremote) binds `channel.mValue.mVUMeter` with a double-log curve to approximate the MixConsole meters.
  - Scripts can only output through MIDI ports, so the app exposes a virtual port and the script packs float levels into SysEx or 14-bit values.
  - Update rate is UNVERIFIED.
- **Reaper:**
  - OSC pattern file (`Default.ReaperOSC`) includes `TRACK_VU n/track/@/vu`, `TRACK_VU_L/R`, `MASTER_VU`, `TRACK_NAME`, `TRACK_MUTE/SOLO/REC_ARM/SELECT`, `DEVICE_TRACK_COUNT` and `DEVICE_TRACK_BANK_FOLLOWS DEVICE|MIXER`. There is no track colour in the default file.
  - Meters are normalized; a forum source says −72…+6 dB maps to 0–1 (UNVERIFIED).
  - ReaScript and the C++ extension API (`Track_GetPeakInfo`, `GetTrackColor`, `IReaperControlSurface` callbacks) give everything at full resolution.
  - The shared MCU bank offset is noted in section 1.
- **Studio One:** MCU/HUI, plus unofficial JavaScript surface scripting (UNVERIFIED). Its VST3 PreSonus extensions give name, colour, index, mute, solo and volume to a plugin.

## 5. Observing the UF8's own traffic (key to bank alignment)

SSL 360 creates its V-MIDI ports as **app-owned virtual endpoints** (seen on this Mac).

- **Surface → DAW:** any CoreMIDI client can connect to the "SSL V-MIDI Port N Source" virtual sources and see UF8 → DAW messages (bank and channel buttons, select, fader touches) with no setup.
- **DAW → surface (passive spy driver):** the reverse direction (names, LEDs, meters, i.e. what the UF8 is actually showing) needs a CoreMIDI driver that calls `MIDIDriverEnableMonitoring`. Apple's `MIDIDriver.h` says this delivers "every outgoing MIDI packet, to all destinations in the system (not just those controlled by itself)", possibly out of order. MIDI Monitor's SnoizeMIDISpy driver is working prior art ([krevis/MIDIApps](https://github.com/krevis/MIDIApps); MIDI Monitor 1.5.4 lists support through macOS Tahoe).
  - Pros: zero DAW reconfiguration, and it works for MCU and HUI in every DAW.
  - Cons: installing a signed CFPlugin into `/Library/Audio/MIDI Drivers`, which runs inside MIDIServer.
- **Proxy (man in the middle):** the DAW talks to the app's virtual ports and the app forwards to SSL V-MIDI.
  - Pros: no driver.
  - Cons: the UF8 goes dead if the app quits. Needs manual port reassignment. SSL 360's auto-configuration may fight it (UNVERIFIED).
- **Bank mirroring:** the app's own emulated MCU group repeats the UF8's bank and channel presses it hears on the V-MIDI Source, and corrects drift by comparing names. No driver is needed, but it is fragile when the DAW auto-banks on selection.

## 6. Recommended hybrid strategy

1. **Alignment layer (all DAWs):** decode the DAW → SSL V-MIDI traffic (spy driver preferred, proxy as fallback) with MCU and HUI parsers. This gives the 8 strips currently on the UF8: names, mute/solo/select/rec, faders and coarse meters.
2. **Rich layer, per DAW:**
   - Live: a bridge Remote Script (or AbletonOSC/M4L) streaming smoothed left/right meters, name, colour, mute/solo/arm/selected, `muted_via_solo` and the visible track list over UDP.
   - Reaper: OSC or an extension.
   - Cubase: a MIDI Remote script sending `mVUMeter` floats over a virtual MIDI port.
   - Pro Tools: PTSL (names, colours, states, events) plus an optional AAX meter plugin. Without it, use HUI meters.
   - Logic: MCU only (plus an optional AU metering plugin).
3. **Bank-follow algorithm:** match the UF8's 8 truncated LCD/HUI names as a sliding window against the DAW's ordered visible track list. Score by prefix and abbreviation similarity, anchor on the selected-track LED versus the API's selected track, and re-solve whenever the LCD is rewritten. The result is a bank offset. The bridge then shows the aligned 8 and can fill 24 slots (offset −8…+15 or 0…+23) from the API's full track list.
   - Where no API exists (Logic, or Pro Tools without a plugin), add 2 emulated XT/HUI units to the right in the UF8's group so the DAW feeds the next 16 tracks' coarse meters.
   - In Reaper, just add MCU instances at offsets 0, 8 and 16.
4. **Distribution:** ship outside the Mac App Store (Developer ID plus notarization), because the driver, Remote Script and plugin installs conflict with the sandbox.
5. **Behringer Wing:** its DAW mode is MCU/HUI over USB ("WING 1–3"), so the same spy and parse layer covers it.

## Open questions
- Which DAW does the user mainly mix in? Local evidence points to Ableton Live 12 Suite, with Pro Tools second; Logic is not installed. This decides which rich-data adapter gets built first.
- With one UF8 (8 strips), what should the 24-track bridge show: the UF8's 8 tracks plus the next 16, the 8 centred with 8 on each side, or 24 only after buying more UF8s? Should the UF1's single fader or selected track be represented?
- Is the user willing to install a signed CoreMIDI spy driver (needs admin rights; the cleanest way to read exactly what the UF8 shows), or would they rather re-route DAW ports through the app as a proxy?
- UNVERIFIED: the actual MCU and HUI meter update rates and dB curves sent by Logic, Pro Tools and Cubase to SSL 360. Measure with MIDI Monitor spying on 'SSL V-MIDI Port 1 Destination'.
- UNVERIFIED: whether Pro Tools banks multiple HUI controllers as one contiguous surface, and whether PTSL allows another client to connect at the same time as SSL 360 and SoundFlow.
- UNVERIFIED: how often Live's output_meter_left/right listeners fire, how the 0–1 value maps to dBFS, and how much GUI/CPU load observing 24 tracks adds.
- UNVERIFIED: whether a custom Live Remote Script can reliably read the UF8 MackieControl instance's bank offset through connect_script_instances, and whether Live passes PreSonus-extension mute/solo to VST3 plugins.
- UNVERIFIED: whether SSL 360 does anything beyond plain MCU/HUI on the V-MIDI ports (extra SysEx, handshakes) that would break a transparent proxy, and whether newer SSL 360 versions (2.1.12+) change the port model. The installed version is 2.0.6.
- Should the bridge's meters be pre-fader (plugin inserts) or post-fader to match the DAW? If post-fader, can a fader-gain correction be calibrated for each DAW?
- For the Behringer Wing, which MCU/HUI mode and how many DAW ports will the user run, and does the Wing's own native protocol (OSC/TCP) matter beyond DAW mode?

## Fact-check
- **REFUTED**: MCU meters are channel pressure D0 with strip in the high nibble and level 0x0–0xC (0xE/0xF set/clear overload). That is about 13 mono steps per strip, the surface decays them itself, and the dB curve depends on the host.
  - Mostly right, but the level range is wrong. The encoding is D0 (strip<<4 | level), mono, with a host-dependent dB mapping. TouchMCU says 'The decay is automatic at a rate of about 300 ms per division'. However, the level nibble goes up to 0xD, not 0xC. TouchMCU lists 0xsD as '100 % (> 0 dB)'. Reaper's csurf_mcu.cpp maps -70..0 dB linearly onto 0..13 and sends 0xD at or above 0 dB. Ardour's surface.cc uses '(deflection/115)*13', which also reaches 0xD. Live's MackieControl tops out at int(1.0*12) = 0xC. 0xE/0xF are set/clear overload per TouchMCU. Reaper's source comment instead says 'F=clip, E=top' and never sends either, so the bridge's decoder must accept 0x0–0xF. Reaper also averages L and R into one value, skips sending while below its held peak, and decays the meter itself, so the bridge needs its own ballistics. Whether the UF8 / SSL 360 decays meters itself is UNVERIFIED. Sources: https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md and https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp (https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)
- **CONFIRMED**: MCU scribble strip SysEx F0 00 00 66 14 12 pp … F7 addresses a 2x56-character LCD (7 characters per strip). Meter mode is F0 00 00 66 14 20 strip bits F7 (bit0 signal LED, bit1 peak hold, bit2 LCD meter), and 0x21 sets global orientation. Device IDs are 0x14 MCU, 0x15 XT, 0x10/0x11 Logic Control (challenge handshake).
  - Confirmed. (https://github.com/NicoG60/TouchMCU/blob/main/doc/mackie_control_protocol.md)
- **REFUTED**: Live's built-in MackieControl script sends MCU meters as int(output_meter_level*12), a 1-second hold peak, from update_display at TIMER_DELAY 0.1 s (about 10 Hz). Meters depend on is_pro_version, which is set only if the surface answers the firmware version request with major version above '2'.
  - The gating logic is reversed. The clean Live 9/10.1 decompile of ChannelStrip.on_update_display_timer reads: 'if not self.main_script().is_pro_version or self.__meters_enabled and assignment_mode() == CSM_VOLPAN'. So meters are always sent when is_pro_version is False, which is the default when the surface never answers the 0x13 version request. Only a 'Pro' surface needs meter mode toggled on (Name/Value button) and Vol/Pan assignment mode. is_pro_version = version_bytes[1] > 50 (ASCII '2'), parsed from a 12-byte F0 00 00 66 14 14 … reply. The Live 12 decompile in gluon/AbletonLive12_MIDIRemoteScripts is garbled by uncompyle6 and reads the opposite way, so do not rely on it. Meter value is int(level*12) | strip<<4, sent with status 0xD0. When the track is armed it sends input_meter_level instead of output_meter_level. It is sent on change or whenever the value is non-zero. Live also sends meter-mode SysEx F0 00 00 66 14/15 20 strip mode F7 (bit0 always, |2 when meters enabled). MackieControl does not reference TIMER_DELAY: it runs from Live's update_display callback. TIMER_DELAY = 0.1 lives in _Framework/Defaults.py, so about 10 Hz is right. The '1-second' hold is UNVERIFIED: the LOM only says 'Hold peak value'. What SSL 360 answers to the version request is UNVERIFIED. (https://github.com/gluon/AbletonLive10.1_MIDIRemoteScripts/blob/master/MackieControl/ChannelStrip.py)
- **CONFIRMED**: HUI meters are poly aftertouch A0 with strip as the note byte and side<<4|level (0–0xC). That is stereo, 12 segments. HUI names are only 4 characters, and the host pings with 90 00 00 expecting the reply 90 00 7F.
  - Confirmed. (https://github.com/orchetect/swift-midi-controlsurfaces/blob/main/Sources/SwiftMIDIControlSurfaces/HUI/HUIConstants.swift)
- **CONFIRMED**: In Reaper, all MCU surface instances share one global bank offset (m_allmcus_bank_offset) plus a per-instance offset. An emulated MCU at offset 0 mirrors the UF8's bank exactly, and offsets 8/16 give the neighbouring banks.
  - Confirmed. (https://github.com/justinfrankel/reaper-sdk/blob/main/reaper-plugins/reaper_csurf/csurf_mcu.cpp)
- **CONFIRMED**: In Logic and Live, emulated extenders in the UF8's control-surface group are stacked contiguously and show the NEXT 8 tracks, not the UF8's tracks. Separate Logic groups bank independently. Mirroring the UF8 needs passive observation or bank mirroring.
  - Confirmed. (https://help.apple.com/pdf/logicpromac-css/en_US/logic-pro-mac-control-surfaces-support-guide.pdf)
- **CONFIRMED**: SSL 360 creates its 12 'SSL V-MIDI Port N Source/Destination' ports as app-owned virtual CoreMIDI endpoints (MIDISourceCreateWithProtocol/MIDIDestinationCreateWithProtocol). On this Mac, Live 12.4.5 uses MackieControl on SSL V-MIDI Port 1, with three MackieControlXT slots unassigned.
  - Confirmed. (local: /Applications/SSL 360.app/Contents/Resources/libCoreMIDIWrapper.1.dylib (nm -u shows _MIDISourceCreateWithProtocol/_MIDIDestinationCreateWithProtocol); live CoreMIDI enumeration shows 12 Source + 12 Destination endpoints with no entity (virtual) and protocol 1 (MIDI 1.0); ~/Library/Preferences/Ableton/Live 12.4.5/Log.txt lines 13298-13304)
- **UNCERTAIN**: A CoreMIDI driver calling MIDIDriverEnableMonitoring receives every outgoing MIDI packet to all destinations in the system. This lets the bridge passively read what the DAW sends to the UF8 (names, LEDs, meters, current bank) without reconfiguring the DAW. MIDI Monitor's spy driver is working prior art.
  - The API part is confirmed. The macOS 26.5 SDK MIDIDriver.h says the driver's Monitor function 'is called with the outgoing MIDI packets for all destinations in the system', and warns that it 'cannot rely on the MIDI events arriving in order'. Version-3 drivers (macOS 12+) also get MonitorEvents with MIDIEventList. The MIDIApps README says the spy driver can see 'MIDI sent to any destination in the system by any app'. MIDI Monitor 1.5.4 lists support through Tahoe, and spying was broken on macOS 11.0–11.1. Three caveats are UNVERIFIED or wrong: (a) no source explicitly confirms that packets sent to another app's virtual destinations (SSL 360's) reach Monitor. Test it with MIDI Monitor's spy on this Mac before building on it. (b) 'Current bank' is not transmitted as a number by Live or Logic over MCU. Only Reaper writes bank offset+1 to the 2-digit assignment display (CC 0x4A/0x4B), so track identity must otherwise be inferred from the 7-character scribble names. (c) It needs a CFPlugin driver installed in /Library/Audio/MIDI Drivers or ~/Library/Audio/MIDI Drivers and loaded into MIDIServer. That rules out a sandboxed or App Store-only distribution. (https://github.com/krevis/MIDIApps)
- **UNCERTAIN**: The Ableton Live Object Model exposes Track.output_meter_left/right (smoothed momentary peak, 0–1, observable), output_meter_level (1 s hold), name, color, mute, solo, arm and muted_via_solo. AbletonOSC (MIT) exposes start_listen on all three meter properties over UDP 11000/11001.
  - Almost everything is confirmed. The LOM lists output_meter_left/right as 'Smoothed momentary peak … 0.0 to 1.0' (get/observe). output_meter_level is 'Hold peak value of output meters', and the hold time is not documented, so '1 s' is UNVERIFIED. name, color/color_index, mute, solo, arm and muted_via_solo are all observable. AbletonOSC (MIT) track.py puts output_meter_level/left/right in properties_r, and every properties_r/rw item gets /live/track/start_listen/<prop>. constants.py sets OSC_LISTEN_PORT=11000 and OSC_RESPONSE_PORT=11001. AbletonOSC does not expose muted_via_solo, so a custom Remote Script or Max for Live device is needed for that. Sources: https://docs.cycling74.com/apiref/lom/track/ and https://github.com/ideoforms/AbletonOSC/blob/master/abletonosc/track.py (https://docs.cycling74.com/apiref/lom/track/)
- **CONFIRMED**: Cubase's MIDI Remote API can read meters: MR_MixerChannelValues includes mVUMeter, mVUMeterMax, mVUMeterClip, mVUMeterPeak and getVUChannelMeterByChannelIndex, plus mute, solo, selected, record, title and colour callbacks. Scripts can only output through MIDI ports.
  - Confirmed. (https://github.com/steinbergmedia/midiremote_api_doc/blob/main/generated-ide-assets/v1/midiremote_api_v1.d.ts)
- **REFUTED**: Pro Tools PTSL exposes the track list with name, index, colour and attributes (muted, soloed, selected, rec-enabled, hidden), plus solo/mute/rec-arm change events via SubscribeToEvents. It has no meter commands. SSL 360 v2.1.12+ itself uses PTSL alongside HUI for UF8 names and colours.
  - Track/TrackAttributes fields (name, index, color, is_muted, is_soloed, is_selected, is_record_enabled, is_hidden, is_inactive) and the absence of meter commands are confirmed in py-ptsl's generated stubs. Event support is version-gated. SubscribeToEvents is absent in the 2024.6 stubs. It appears in the 2025.6 stubs with session events only. EId_TrackSoloStateChanged, EId_TrackMuteStateChanged and EId_TrackRecordEnabledStateChanged appear only in the 2025.10 stubs. The Pro Tools installed on this Mac is 24.6.0 (2024.6), so it has no event subscription and the bridge would have to poll GetTrackList. On SSL 360: the installed SSL 360 is 2.0.6.67265, and its SSL360Gui binary already contains 'PTSL' strings. So SSL 360 uses PTSL already in 2.0.6, and the 'v2.1.12+' threshold is doubtful or UNVERIFIED (SSL release notes could not be fetched). What SSL uses PTSL for (names and colours) is UNVERIFIED. (https://github.com/iluvcapra/py-ptsl/blob/master/ptsl/PTSL_pb2.pyi)
- **CONFIRMED**: VST3 IInfoListener gives a plugin its track name, colour, index and plugin location (pre- or post-fader). Live has supported it since 10.1.2. AU contextName and AAX TrackNameChanged give the name only.
  - Confirmed. (https://www.ableton.com/en/release-notes/live-10/)
- **UNCERTAIN**: The PreSonus VST3 Plug-in Extensions (IContextInfoProvider) expose name, index, color, selected, focused, volume, pan, mute and solo to plugins. They are supported in Studio One, Live 10.1.9+ and Reaper 5.5+. This is the only plugin route that gives mute/solo and fader level, which a post-fader correction needs.
  - The interface contents are confirmed: ipslcontextinfo.h defines kName, kIndex, kColor, kSelected, kFocused, kVisibility and, per instance (requires IContextInfoHandler2), kVolume, kMaxVolume, kPan, kMute, kSolo and kSendLevel. Host support for Live 10.1.9+ and Reaper 5.5+ is UNVERIFIED. The Ableton release-notes search found no mention of PreSonus extensions in 10.1.9, and the web-search budget ran out before Reaper's changelog could be checked. Whether Live supplies the per-instance volume/mute/solo keys is UNVERIFIED. 'Only plugin route' is plausible but not proven. In Live, devices always sit before the mixer volume, so any plugin meter is pre-fader. The LOM's output_meter_* values are post-fader and need no correction. (https://github.com/Ardour/ardour/blob/master/libs/vst3/pslextensions/ipslcontextinfo.h)
- **REFUTED**: Logic Pro offers no public scripting or meter API beyond MCU/HUI. Third-party Control Surface plug-ins stopped working in Logic 10.7, and the OSC surface integration SSL uses (SSL 360 OSC Device) is undocumented.
  - Apple's current Control Surfaces Support Guide (© 2025) contradicts the '10.7' part. It states: 'A number of devices such as Nektar Panorama, Native Instruments Komplete Kontrol, and other units, provide a manufacturer-supplied plug-in.' So third-party control-surface plug-ins still exist. The same guide says 'Logic Pro provides Lua scripting support … for dozens of keyboard (and desktop) controllers'. Whether that Lua layer is public or exposes meters is UNVERIFIED. No public meter API beyond MCU/HUI was found, which is consistent with the claim. The SSL support article (HTTP 403) could not be fetched, so the 'undocumented SSL 360 OSC Device' part is UNVERIFIED. Logic Pro is not installed on this Mac. Installed apps are Ableton Live 11/12, Pro Tools 24.6, FL Studio 2025 and WING-Edit. (https://help.apple.com/pdf/logicpromac-css/en_US/logic-pro-mac-control-surfaces-support-guide.pdf)

### Missed points
- Installed DAWs on this Mac (from /Applications): Ableton Live 12 Suite 12.4.6 (the newest prefs/log folder is 12.4.5, so 12.4.6 has not been launched yet) and Live 11 Suite, Pro Tools 24.6.0, FL Studio 2025 (25.1.6), WING-Edit 3.3.0 and SoundFlow. Logic Pro, Cubase and Reaper are NOT installed, so Live, then Pro Tools and FL Studio, are the realistic first targets.
- FL Studio is a real meter route the report skipped. SSL 360 has a DawType_McuFLStudio profile. FL's MIDI scripting API has mixer.getTrackPeaks(index, mode) with PEAK_L/PEAK_R/PEAK_LR (0..1, above 1 = clipping), plus getTrackName, getTrackColor, isTrackMuted, isTrackSolo and isTrackSelected (https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/midi_scripting.htm). Call rates for OnIdle/OnRefresh are not documented.
- Live bank step equals the total strip count across MackieControl plus all attached XTs. ChannelStripController moves by len(self.__channel_strips), and XTs in slots after the main script become right extensions while XTs in earlier slots become left extensions (they take the preceding tracks). On this Mac, the three MackieControlXT slots (4–6) have Input/Output None. The AbletonMCP script with Input None still initializes per the log, so those XTs are likely instantiated too. That would make the UF8 bank in 32-track steps. This is UNVERIFIED: test pressing Bank on the UF8. Those slots could instead carry bridge-emulated XTs that cover tracks 9–24 next to the UF8's 1–8.
- Reaper side effect: the bank move size is max(m_offset+8) over all MCU instances (csurf_mcu.cpp lines ~1427-1430 and ~527-546). Adding emulated MCUs at offsets 8 and 16 would make the UF8's bank buttons jump 24 tracks. SSL 360's own text tells Reaper users to choose 'Mackie Control Universal', so the shared-offset behaviour does apply to the UF8.
- Live's MackieControl sends input_meter_level instead of output_meter_level when a track is armed. Live sends meter-mode SysEx 0x20 per strip itself. What SSL 360 returns to the 0x13 firmware-version request (which decides is_pro_version and hence meter gating) is UNVERIFIED and should be captured with a spy.
- The UF8, UF1 and UC1 hardware are not CoreMIDI devices. SSL 360 drives them through its own USB helpers (libFtdiUnixHelper, ssld2xx in the app bundle). The only tap points are the DAW↔SSL 360 virtual ports, or the DAW's own API. The SSL V-MIDI endpoints exist only while SSL360Core is running.
- Because the SSL V-MIDI Destinations are virtual endpoints owned by SSL 360, a normal app cannot open them to read DAW→UF8 traffic. That leaves (1) a MIDIServer spy driver (prior art: MIDI Monitor's SnoizeMIDISpy, which is not installed here), (2) re-routing the DAW through a bridge-owned port and forwarding to SSL 360 (a man-in-the-middle setup that does reconfigure the DAW), or (3) reading the DAW API directly (LOM / Remote Script / PTSL / FL scripting).
- The user already runs a custom 'AbletonMCP' Live Remote Script with 'Passive LOM listeners' (Live log). That proves the Remote Script / LOM route works on this machine. Live's control-surface slots are already full in the log (MackieControl, SL_MkIII, AbletonMCP, 3× MackieControlXT, Launchkey_Mini_MK3), so a bridge Remote Script would need to replace one, for example an unused XT slot.
- In Live, devices (VST3/AU/M4L) always sit before the mixer's volume fader, so plugin-based meters are pre-fader. The LOM output_meter_left/right values are already post-fader, which makes LOM (Remote Script, M4L or AbletonOSC) the better Live data source.
- Pro Tools 24.6 (installed) predates PTSL event subscriptions. SubscribeToEvents appears with PTSL 2025.6, and track solo/mute/rec events appear with 2025.10. On 24.6 the bridge must poll GetTrackList. PTSL never provides meters, so Pro Tools meters must come from HUI (12-segment, stereo, 0x0–0xC) observed on SSL 360's port.
- Other virtual MIDI endpoints on this Mac may confuse port auto-detection: SoundFlow HUI Output/Input, SoundFlow Ableton Input/Output, Akai Network - DAW Control, and IAC 'StreamDeck2DawTrack'/'DawTrack2StreamDeck'. SoundFlow's HUI ports suggest SoundFlow may also be acting as a HUI device in Pro Tools.
- SSL 360's binary lists its DAW profiles: Hui, McuAbletonLive, McuBitwig, McuCubase, McuFLStudio, McuLogicPro, McuLuna, McuMixbus, McuPyramix, McuReaper, McuSamplitude, McuStudioOne, DigitalPerformer and MidiCc. These define which protocol the bridge must decode per DAW. Installed SSL 360 is 2.0.6.67265 (bundle dated Oct 2025) and may need updating.
- Logic Pro 12.x release notes (current 12.4) include 'HUI compatible control surfaces now show level meter activity on channel 8' (12.0) and 'Control surfaces can now be used to control Mixer channels that are not assigned to a track' (12.2). Version-specific MCU/HUI meter behaviour still changes (https://support.apple.com/en-us/HT203718).
- Behringer Wing: WING-Edit 3.3.0 is installed. Wing DAW-remote (MCU/HUI over USB) and native OSC meter protocol details were NOT verified because the web-search budget ran out. Treat all Wing protocol claims as UNVERIFIED.
- Verification limits: the web-search budget ran out mid-task. These remain UNVERIFIED: the SSL 360 v2.1.12 PTSL threshold, PreSonus-extension host support in Live and Reaper, the 'Logic 10.7' claim, SSL's Logic OSC article (HTTP 403) and the Wing protocol.
