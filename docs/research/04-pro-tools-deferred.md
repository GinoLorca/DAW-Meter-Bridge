
# Pro Tools (macOS): research for a HUI/UF8-aligned meter bridge

**Short answer:** No single official Pro Tools interface gives a third party all four things: accurate meters, mix state, control, and bank-follow. The workable design for a solo developer combines three pieces:
1. **A HUI MIDI proxy (man-in-the-middle)** placed between Pro Tools and the SSL V-MIDI port(s), or the Wing's USB ports. This gives bank-follow, LED states, fader positions and coarse meters, and lets the app control Pro Tools.
2. **PTSL (the Pro Tools Scripting SDK, free).** This gives full track names, colours, track order, selection, mute/solo events, and mute/solo/select setters.
3. **Optional: an AAX Native metering plug-in.** This is the only way to get accurate dB meters. It needs PACE signing and Avid approval, and its meters are **pre-fader**.

---

## 1. PTSL (Pro Tools Scripting Library / Scripting SDK)

**Origin, cost and access**
- PTSL arrived with **Pro Tools 2022.12**. Avid calls it a "new free Pro Tools Scripting SDK" and says it "works with any tier of Pro Tools", from Artist, Studio and Ultimate down to Intro. Sign-up is at developer.avid.com/scripting. Source: [Avid resource center](https://www.avid.com/resource-center/pro-tools-scripting-sdk).
- The download sits behind a click-through license ([developer.avid.com/scripting](https://developer.avid.com/scripting/)). I did not see the license text, so its terms for redistributing a commercial client are **UNVERIFIED**.

**Connection and transport**
- PTSL is gRPC on **localhost:31416**. The service is generic: `SendGrpcRequest` (unary) and `SendGrpcStreamingRequest` (server-streaming), each carrying a JSON request body. Sources: [py-ptsl `PTSL_pb2_grpc.py` / `engine.py`](https://github.com/iluvcapra/py-ptsl) and the C++ sample in the Avid SDK.
- Since 2023.3, clients connect with `RegisterConnection` (company name + application name) and need no developer certificate. Certificates were dropped entirely by 2023.12.
- Since 2025.06, version numbering is the year triplet (for example 2025.10.0), and the SDK ships one `.proto` file per release.
- Source for the last two points: Avid's PTSL SDK release notes, read from a third-party GitHub copy of SDK 2025.10 ([release_notes.doxygen](https://github.com/danielrdehaan/Scripts/blob/main/Pro-Tools/PTSL_SDK_CPP.2025.10.0.1232349/Documentation/release_notes.doxygen), [PTSL.proto](https://github.com/danielrdehaan/Scripts/blob/main/Pro-Tools/PTSL_SDK_CPP.2025.10.0.1232349/Source/PTSL.proto)).
  - Avid marks these files confidential, so take the authoritative copy from Avid's own portal.
  - I cross-checked the command names against the protobuf stubs generated for [py-ptsl `PTSL_pb2.pyi`](https://github.com/iluvcapra/py-ptsl/blob/master/ptsl/PTSL_pb2.pyi), which is at PTSL 2025.10.0.
- From Swift, generate a client from `PTSL.proto` with grpc-swift.

**Reading track state**
- `CId_GetTrackList` returns, for each track: `name`, `type`, `id`, `index`, `color`, `parent_folder_*`, and a `track_attributes` block. The attributes include `is_selected`, `is_muted`, `is_soloed`, `is_record_enabled`, `is_hidden`, `is_inactive`, `is_input_monitoring_on` and `is_frozen`.
- Results are paginated (`PaginationRequest` was added in 2023.9).

**Setting state**

| Command | Since |
|---|---|
| `SelectTracksByName` (with `SelectionMode`) | 2023.9 |
| `SetTrackMuteState`, `SetTrackSoloState`, `SetTrackSoloSafeState` (all by track name) | 2023.12 |
| `SetTrackRecordEnableState`, plus Hidden/Inactive/Online/Open/Frozen/InputMonitor/SmartDsp setters | by 2023.12–2024.3; py-ptsl first shows them in its PTSL-3 build |
| `SetTrackColor`, `DeleteTracks`, `GetColorPalette` | 2025.10 |

**Volume and fader values**
- 2025.10 added `GetTrackControlInfo`, `GetTrackControlBreakpoints` and `SetTrackControlBreakpoints`. They cover volume, pan, LFE, mute and plug-in controls.
- The proto describes `GetTrackControlBreakpoints` as **"Defined but not yet implemented."** In other words, PTSL **cannot read a fader value**.
- `SetTrackControlBreakpoints` can write a static value (one breakpoint at time 0) or a run of automation breakpoints. **It replaces all existing values for that control**, so it erases automation. That makes it unsuitable for dragging a fader live.
- A third-party project, the [Presto CHANGELOG](https://github.com/LoyanLi/Presto/blob/main/CHANGELOG.md), reports that the **2026.04 SDK removed the track-control-breakpoint commands**. Only that one source says so: **UNVERIFIED**.

**Meters**
- **No PTSL command exposes meter levels.** "Meter" in the proto refers only to time-signature (meter) tracks.

**Events**
- 2025.06 added an *experimental* event system: `SubscribeToEvents`, `UnsubscribeFromEvents`, and `PollEvents`.
  - `PollEvents` is a long-poll that streams events.
  - Only one `PollEvents` call can be open per PTSL session.
  - Event calls run at higher priority than other commands.
- Events available in 2025.06: SessionOpened, SessionCreated, SessionClosed.
- Events added in 2025.10: TrackMuteStateChanged, TrackSoloStateChanged, TrackRecordEnabledStateChanged, TrackInputMonitorStateChanged, MenuItemSelected, BatchJobStatusChanged.
- There are **no events for selection, track add/remove/reorder/rename, colour or volume.** Those still need `GetTrackList` polling. I found no documented rate limit, and the performance cost of polling is **UNVERIFIED**.

**Other notes**
- 2025.06 also added `CId_EnableAPI`, which "Enables a private API set" using a client key. It looks partner-only, and what it unlocks is **UNVERIFIED**.
- PTSL has no notion of which bank a control surface is showing.

## 2. HUI as Pro Tools uses it

**Protocol reference:** theageman's reverse-engineered spec, [HUI.pdf](https://htlab.net/computer/protocol/mackie-control/HUI.pdf). All messages are on MIDI channel 1. The sysex header is `F0 00 00 66 05 00`.

**Meters**
- Format: `A0 0y sv`. That is a polyphonic aftertouch message; y = strip 0–7, s = side (0 = left, 1 = right), v = 0x0–0xC.
- The 13 levels map to these thresholds:

| v | Signal | Colour |
|---|---|---|
| 0 | below −60 dB | off |
| 1 | ≥ −60 dB | green |
| 2 | ≥ −50 dB | green |
| 3 | ≥ −40 dB | green |
| 4 | ≥ −30 dB | green |
| 5 | ≥ −20 dB | green |
| 6 | ≥ −14 dB | green |
| 7 | ≥ −10 dB | green |
| 8 | ≥ −8 dB | green |
| 9 | ≥ −6 dB | yellow |
| A | ≥ −4 dB | yellow |
| B | ≥ −2 dB | yellow |
| C | ≥ 0 dB | red (clip) |

- This matches the UF8's "12-segment track metering + clip". **It is too coarse for accurate dB or peak-hold readouts.**
- Pro Tools HUI sends stereo *track* meters only, with no output metering ([Neyrinck](https://docs.neyrinck.com/v-control-pro/feature-chart/dcommand-protools/)).
- **HUI metering is unavailable while EUCON is enabled** ([SSL Live DAW Control](https://livehelp.solidstatelogic.com/Help/DAWControl.html)).
- **UNVERIFIED:** whether the meter values follow Options > Pre-Fader Metering, and how mono tracks are sent.

**Track names (4-character scribble strips)**
- `<hdr> 10 yy c1 c2 c3 c4 F7`, where yy = 0–7 is the strip and 8 is the SELECT-ASSIGN display.
- Pro Tools sends abbreviated 4-character labels (SSL Live confirms this). The abbreviation algorithm is **UNVERIFIED**.

**LEDs and switches**
- Host → surface: zone select `B0 0C zz`, then `B0 2C 4p` (on) or `B0 2C 0p` (off).
- Surface → host: `B0 0F zz`, then `B0 2F 4p` / `B0 2F 0p`.
- Strip zones 00–07 use these ports: 0 fader touch, 1 select, 2 mute, 3 solo, 4 auto, 5 v-sel, 6 insert, 7 rec/rdy.
- Bank and channel buttons are zone 0A, ports 0–3.

**Faders**
- Position: `B0 0z hi` then `B0 2z lo`, giving a nominal 14-bit value (0–16383). Real HUI hardware is said to be about 9-bit.
- Touch: `B0 0F 0z, B0 2F 40`. Release: `B0 0F 0z, B0 2F 00`.
- **UNVERIFIED:** the Pro Tools fader-position-to-dB curve and the effective resolution Pro Tools accepts. Plan to calibrate.

**Ping / keepalive**
- The host sends `90 00 00` about once a second. The surface must reply `90 00 7F`.
- A HUI goes offline after about 2 seconds without a ping (theageman). The Max cookbook ([UCI Max cookbook](https://music.arts.uci.edu/dobrian/maxcookbook/midi-protools)) describes the same ping-and-reply from Pro Tools for its MotorMix emulation.
- Any device the app emulates itself must answer pings.

**How many HUI devices Pro Tools allows**
- The [Pro Tools 2025.10 Reference Guide](https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_2025.10.pdf) (MIDI Controllers, p.189) says Pro Tools takes "up to four different MIDI controllers", and that the row number sets the controllers' order.
- The only general-purpose controller type it lists is **HUI**. The full list is Command|8 (Windows only), HUI, Surround Panner and NI Komplete Kontrol; there is no Mackie Control type.
- SSL: "A maximum of four ports per DAW is possible in Pro Tools via HUI (up to 32 DAW control faders)", and "the lowest port will always be DAW channels 1-8".

**Can a second set of HUI devices follow the UF8's bank?**
- **No, not natively.** The HUI rows form one contiguous surface: row #2 shows channels 9–16, and so on. I found no mirror mode in Avid's documentation; that conclusion is inferred from the Reference Guide and SSL's description.
- **Workaround 1, the proxy:** the app creates its own CoreMIDI ports (or uses two IAC buses). Pro Tools' HUI #n sends and receives through the app, and the app relays everything byte-for-byte to and from "SSL V-MIDI Port n".
  - The app then sees exactly what the UF8 shows: names, LEDs, fader positions and meters.
  - It can also inject HUI presses (mute/solo/select) and fader touch → move → release sequences.
  - Injected messages must be complete zone/port pairs and must never land between the UF8's own zone-select and port messages.
  - The app's ports must exist before Pro Tools launches. Neyrinck likewise says V-Control Pro must be launched "FIRST".
- **Workaround 2, a passive spy driver:** a CoreMIDI spy driver, as in [MIDI Monitor](https://www.snoize.com/midimonitor/), can read the destination traffic. It is read-only and requires installing a driver.

**Pro Tools banking preferences:** "Edit/Mix Window Follows Bank Selection" and "Always Fill Channel Strips When Banking" both exist (Reference Guide p.157). Neither is readable through PTSL.

## 3. EUCON, UF8 / UF1 / UC1, and the Behringer Wing

**EUCON is not an option**
- The EUCON Application SDK is for "software developers who would like their software to be controlled by Avid hardware or control apps" ([developer.avid.com/eucon](https://developer.avid.com/eucon/)).
- According to [Resurface](https://resurface.audio/avid-and-future-control-surfaces/), "EUCON has never been open to 3rd party hardware developers."
- A meter bridge is the surface (client) side, so EUCON is effectively unavailable.

**SSL UF8**
- The [UF8 User Guide, Rev 5, Oct 2023](https://eu1.download.solidstatelogic.com/UF8/SSL%20UF8%20User%20Guide_Rev5.pdf) says: "The HUI … protocol is the way in which Pro Tools communicates with UF8."
- Each UF8 is set up in Pro Tools as its own HUI controller on its own SSL V-MIDI port:
  - Layer 1 uses ports 1–4 for units 1–4.
  - Layer 2 uses ports 5–8.
  - Layer 3 uses ports 9–12.
- So N UF8s use N HUI slots, with a maximum of 4.
- The UF8 display shows 4-character names, fader dB, and 12-segment meters plus clip.

**SSL UF1**
- The [UF1 guide](https://www.ambertech.com.au/Documents/SSL/SSL%20UF1%20User%20Guide_Rev1.0.pdf) says the UF1 is also configured as a HUI controller, on V-MIDI Port 1, 5 or 9 depending on its layer.
- **UNVERIFIED:** how many slots UF8 + UF1 take together in Pro Tools. Forum reports describe the UF1 as a second HUI on another layer, which makes it control the next 8 tracks.

**SSL UC1**
- The UC1 controls 360°-enabled plug-ins through SSL's own protocol. SSL 360 v2.0.6+ follows Pro Tools track order and colour and syncs selection, and needs Pro Tools 2024.6+.
- **SSL 360 V2.1 (Aug 2026)** shows **8-character names and Pro Tools track colours on the UF8 and UF1**.
- So SSL itself adds a Pro Tools data channel on top of HUI. That this channel is PTSL is **UNVERIFIED**, but likely. This is a direct precedent for the HUI + PTSL hybrid. Sources: [SSL V2.1 press](https://ssl.hummingbirdmedia.com/ssl-enhances-the-industry-standard-u-series-controller-ecosystem-with-ssl-360-v21-update), [SSL 360 v2.0](https://sonicstate.com/amped/2025/10/29/solid-state-logic-releases-ssl-360-v20-software/).

**Behringer Wing**
- Under SETUP → DAW you choose the connection (DIN5 or USB MIDI) and the emulation (MCU or HUI). The CONFIGURATION setting decides how many controllers the Wing emulates ([WING manual, fw 3.1](https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf)).
- Behringer's DAW Control Guide reportedly says to use HUI for Pro Tools, set up in rows #1–#3 on WING ports 1–3 with 8 channels each, for 24 faders. I could not open the guide's PDF; this came from search excerpts, so medium confidence.
- That setup takes 3 of the 4 HUI slots. The same proxy design works on those ports.
- For comparison, DAWWAY on Windows does not list Pro Tools, and its setup asks you to connect "DAWWAY ports" in the DAW ([dawway.co.uk](https://dawway.co.uk/)).

## 4. Per-track AAX metering plug-in

**SDK access**
- You download it from developer.avid.com after creating an Avid account and accepting a click-through license ([developer.avid.com/aax](https://developer.avid.com/aax/)).
- Since AAX SDK 2.8.0 (mid-2024), the header says the SDK is "subject to commercial or open-source licensing" and can be used under **GPLv3**.
- JUCE bundles the SDK ([AAX_Enums.h in JUCE](https://github.com/juce-framework/JUCE/blob/master/modules/juce_audio_plugin_client/AAX/SDK/Interfaces/AAX_Enums.h); [JUCE forum](https://forum.juce.com/t/aax-open-source-release/44017)).

**Shipping**
- Retail Pro Tools only loads AAX plug-ins that are **PACE-signed** (Eden tools / wraptool). That needs an **iLok USB key**; PACE cloud signing is a paid enterprise product.
- You request the tools through Avid. The address is audiosdk@avid.com, and developers report a "PACE Eden Signing Tools Request" step plus an agreement.
- One guide says you "must be authorized by Avid to release AAX plugins" ([Dplug AAX guide](https://github.com/AuburnSounds/Dplug/wiki/Dplug-AAX-Guide), [Moonbase round-up](https://moonbase.sh/articles/code-signing-audio-plugins-in-2025-a-round-up/)).
- Developers report the signing tools as free once you are approved. Current cost and timeline are **UNVERIFIED**.
- For prototyping, the Pro Tools Developer build loads unsigned plug-ins.
- You also need Apple Developer ID signing and notarisation ($99/yr).

**JUCE licensing:** JUCE is dual-licensed under AGPLv3 or the JUCE licence. The free Starter tier covers revenue up to $20k; Indie is $40/month or $800 perpetual ([juce.com/get-juce](https://juce.com/get-juce/)).

**What the plug-in can learn about its track**
- `AAX_eNotificationEvent_TrackNameChanged` delivers the track name (Pro Tools 11.2 and later).
- `TrackUIDChanged` and `TrackPositionChanged` are marked "not currently sent".
- **There is no track-colour notification.**
- JUCE's AAX wrapper passes the name only, via `AudioProcessor::updateTrackProperties` ([JUCE AAX wrapper](https://github.com/juce-framework/JUCE/blob/master/modules/juce_audio_plugin_client/juce_audio_plugin_client_AAX.cpp)).
- To get colour and index, match the name against PTSL `GetTrackList`. Whether Pro Tools enforces unique track names is **UNVERIFIED**.

**Post-fader is not possible on tracks**
- The Reference Guide says: "Inserts on audio, Auxiliary Input, and Instrument tracks are pre-fader. Inserts on Master Faders are post-fader."
- So a metering insert on 24 tracks reads **pre-fader and pre-mute** levels. The app can either:
  - (a) present them as pre-fader meters, or
  - (b) estimate post-fader levels from the HUI fader position, using a calibrated curve, plus mute state.

**Is a plug-in on every track acceptable practice?**
- Yes, it is a common pattern. SSL's own Plug-in Mixer depends on 360°-enabled plug-ins on each track.
- CPU cost is negligible.
- It uses one of the 10 insert slots per track; put it last.
- It adds a session dependency: anyone opening the session needs the plug-in installed.

## 5. Recommended path for a solo developer

**Phase 1 (no Avid approvals needed)**
- **HUI proxy** on each surface port (UF8's V-MIDI port(s), or WING ports 1–3). This gives:
  - exact bank-follow,
  - select/mute/solo/rec LEDs,
  - fader positions,
  - 13-step meters,
  - control by injecting HUI presses and touch/move/release fader sequences. Shift-fine is limited by the HUI resolution Pro Tools accepts.
- **Plus PTSL** (Pro Tools 2025.10+ recommended) for:
  - full names, colours, order and hidden state,
  - selection (by polling),
  - mute/solo/rec events,
  - mute/solo/select setters, which also work for tracks outside the bank.
- **Mapping the bank to tracks:** match the 8 four-character names against a contiguous window of *visible* tracks from `GetTrackList`.
- **Gotchas:**
  - Disable EUCON, or the HUI meters go blank.
  - Launch the app before Pro Tools, or use IAC buses.
  - Never break a zone/port pair when injecting.

**Phase 2 (accurate meters)**
- Build a JUCE AAX Native meter plug-in that sends peak/RMS over shared memory or UDP to the app, and keys itself by track name.
- Requires PACE signing and Avid authorisation; prototype on Pro Tools Developer.
- Meters are pre-fader unless the app compensates using the fader position.

**Trade-offs**
- HUI only: zero install footprint, perfectly in step with the UF8, but meters are coarse.
- The plug-in: accurate meters, but approval overhead, pre-fader only, one insert slot per track, and a session dependency.
- PTSL alone cannot do meters, fader reads or bank-follow.
- Rejected alternatives:
  - Post-fader sends to a loopback device (such as BlackHole) via an aggregate device: invasive routing.
  - Reading Pro Tools' meters from the UI or screen.


## Open questions
- Does SSL 360 keep working normally (CHANNEL/PLUGIN modes, V2.1 8-character names and colours) when a transparent MIDI proxy sits between Pro Tools and the SSL V-MIDI ports? This needs a hands-on test.
- How many Pro Tools HUI slots do a UF8 and a UF1 take together under current SSL 360 2.x: does the UF1 share the UF8's HUI or need its own slot on another layer?
- What curve does Pro Tools use to map 14-bit HUI fader positions to dB, what effective resolution does it accept for fine (Shift) moves, and does it need a touch message before it accepts injected fader moves?
- Does the HUI meter feed follow Options > Pre-Fader Metering, and what does Pro Tools send for mono tracks (both sides or left only)?
- What does the PTSL 2026.x SDK actually contain? Were the track-control-breakpoint commands removed, and were selection, volume or track-list events added? What does the private EnableAPI set unlock?
- What PTSL polling rate is safe (for example GetTrackList at 5-10 Hz with 24+ tracks) without hurting Pro Tools UI or audio performance, and can several PTSL clients (SSL 360, SoundFlow, this app) run at once without trouble?
- Does Pro Tools enforce unique track names? Name-based matching between AAX instances, PTSL and HUI depends on it. How does Pro Tools abbreviate names to 4 characters for HUI?
- What are the current PACE/Avid terms, costs and approval timeline for an independent developer shipping a signed AAX utility plug-in?
- Does the Behringer WING in HUI mode work with Pro Tools as three chained HUI devices (#1-#3), and does it display HUI meters?


## Verification
- [UNCERTAIN] Pro Tools 2022.12 introduced the free Pro Tools Scripting SDK (PTSL). Avid says it works with every tier, including Pro Tools Intro, and sign-up is at developer.avid.com/scripting.
  - Partly confirmed. The SDK's own release notes start at 'release_notes_2022_12' and say 'Pro Tools 2022.12 is compatible with clients using PTSL_VERSION 1 only', so PTSL did first ship with Pro Tools 2022.12. developer.avid.com/scripting exists and gets the SDK through a click-through license (via the 'Toolkit' link). No fee is mentioned there, but that page does not say which tiers are supported. The cited avid.com resource-center page returns HTTP 403 to automated fetches, and 'What's New in Pro Tools 2022.12' (https://resources.avid.com/SupportFiles/PT/Whats_New_in_Pro_Tools_2022.12.pdf) does not mention PTSL. So 'works with every tier including Intro' is UNVERIFIED. Test it on Intro/Artist before relying on it. Also note that every SDK file is marked 'CONFIDENTIAL ... subject to an Avid SDK license'. Get the SDK from developer.avid.com and do not use or redistribute third-party GitHub copies. (https://developer.avid.com/scripting/)
- [CONFIRMED] PTSL GetTrackList returns each track's name, index, id, color and attributes (is_selected, is_muted, is_soloed, is_record_enabled, is_hidden, etc.). Setters exist for selection (SelectTracksByName, 2023.9), mute and solo (SetTrackMuteState and SetTrackSoloState, 2023.12) and colour (SetTrackColor, 2025.10). Transport is gRPC on localhost:31416.
  - Confirmed in the 2025.10 PTSL.proto. The 'Track' message has name, type, id (hex), index, color (hex string), track_attributes, id_compressed, format, timebase and parent_folder_*. TrackAttributes has is_inactive, is_hidden, is_selected, is_soloed, is_record_enabled, is_muted, is_input_monitoring_on, is_locked, is_frozen, the *_safe flags and others. Note that is_selected, is_hidden, is_inactive and is_input_monitoring_on are TrackAttributeState enums (None / explicit / implicit), not bools. Versions: CId_SelectTracksByName=73 '@since Pro Tools 2023.09'; SetTrackMuteState=85 and SetTrackSoloState=86 '@since Pro Tools 2023.12'; SetTrackColor=153 '@since 2025.10', which takes a palette color_index, not an RGB value. Selection, mute and solo setters address tracks by name, not by ID. Port: the SDK README uses 'localhost:31416' as the server address, and py-ptsl's client defaults to the same. Clients must call RegisterConnection (company_name/application_name, since 2023.03) to get a session_id. (https://github.com/danielrdehaan/Scripts/blob/main/Pro-Tools/PTSL_SDK_CPP.2025.10.0.1232349/Source/PTSL.proto)
- [CONFIRMED] No PTSL command exposes meter levels. Fader values cannot be read: GetTrackControlBreakpoints (2025.10) is documented as 'Defined but not yet implemented', and SetTrackControlBreakpoints replaces all existing values for the control, including automation.
  - Confirmed. The 2025.10 proto has no meter command; 'Meter' appears only as a TrackType. CId_GetTrackControlBreakpoints=149 carries '@note Defined but not yet implemented', and so does CId_GetTrackControlInfo=148, so the value range and step count cannot be queried either. CId_SetTrackControlBreakpoints=150 says 'Any existing values for the control are replaced by those from this call' and 'A value at time zero must always be included'. Writing one static value therefore wipes the volume automation. Volume values are a float documented as 'min: -1.0 to max: 1.0', with no documented mapping to dB. No other PTSL command sets or gets fader or volume level. (https://github.com/danielrdehaan/Scripts/blob/main/Pro-Tools/PTSL_SDK_CPP.2025.10.0.1232349/Source/PTSL.proto)
- [CONFIRMED] PTSL's event system (SubscribeToEvents/PollEvents, a long-poll stream) arrived as experimental in 2025.06 with session events only. 2025.10 added TrackMute, TrackSolo, TrackRecordEnabled and TrackInputMonitor state-changed events. There are no selection, volume or track-list events, so those must be polled.
  - Confirmed. The 2025.06 release notes have a heading 'Event System (Experimental)' and list only SessionOpened/Created/Closed. PollEvents is 'A long-polling API that streams real-time events'. The 2025.10 'New events' are TrackRecordEnabledStateChanged, MenuItemSelected, TrackInputMonitorStateChanged, TrackSoloStateChanged, TrackMuteStateChanged and BatchJobStatusChanged. EventId has nothing for selection, volume, track add/remove/rename/reorder or bank. Important details: each track-state subscription is filtered by one track_id (TrackMuteStateChangedFilterBody has 'string track_id'), so 24 tracks need 24 subscriptions per event type. Only one PollEvents stream is allowed per PTSL session. Subscriptions persist across Pro Tools sessions. Whether the 'experimental' label still applies after 2025.06 is not stated. (https://github.com/danielrdehaan/Scripts/blob/main/Pro-Tools/PTSL_SDK_CPP.2025.10.0.1232349/Documentation/release_notes.doxygen)
- [UNCERTAIN] The PTSL 2026.04 SDK reportedly removed the track-control-breakpoint commands, so PTSL may now have no volume control at all. This comes from one third-party changelog.
  - Corroborated, but only by third-party sources. Presto's v0.3.11 release notes say they regenerated the catalog from 'PTSL_SDK_CPP.2026.04.0.1301892/Source/PTSL.proto'. The command count went from 159 to 153. Removed: CId_GetTrackControlInfo, CId_GetTrackControlBreakpoints, CId_SetTrackControlBreakpoints, CId_InstallMenuHandler/UninstallMenuHandler, CId_GetPlaylistElements, the scrub commands, EnableCueProVideoPlugIn, EnableAPI and ExchangePublicKeys. Added: SetTrackHeight, Get/ClearTrackMainOutputAssignments, ShowRendererWindow, GetRendererOutSignalPath and DeleteSignalPaths. Presto's generated catalog (ptsl_catalog_generated.py) has 153 entries and no 'Breakpoint' command, and Presto moved pan control to macOS UI automation. No Avid primary source could be read because the SDK is behind a login. Whether Pro Tools 2026.x hosts still accept the removed commands is UNVERIFIED. Plan as if PTSL has no reliable volume control. (https://github.com/LoyanLi/Presto/blob/main/docs/releases/v0.3.11-release.md)
- [CONFIRMED] HUI meters are A0 0y sv (y = strip 0-7, s = left/right, v = 0x0-0xC), with thresholds at -60/-50/-40/-30/-20/-14/-10/-8/-6/-4/-2/0 dB clip. Names are sysex F0 00 00 66 05 00 10 yy + 4 characters. LEDs use zone/port CC pairs (strip ports: select 1, mute 2, solo 3, rec 7). Faders are B0 0z hi / B0 2z lo (nominal 14-bit). The host pings 90 00 00 and the surface replies 90 00 7F.
  - Confirmed against the document. Meter values: v=1 is >= -60 dB, then 2=-50, 3=-40, 4=-30, 5=-20, 6=-14, 7=-10, 8=-8, 9=-6, a=-4, b=-2, and c is >=0 dB (clip). Names: <hdr> 10 yy + 4 chars + F7, where yy 0..7 are channels and 8 is SELECT-ASSIGN. Host-to-surface LED messages are b0 0c zz followed by b0 2c 4p (on) or 0p (off). Surface-to-host messages are b0 0f zz followed by b0 2f 4p/0p. Fader touch is zone z, port 0. Rec/rdy is the eighth column of the zone table, i.e. port 7 (the table header misprints it as 'Port 8'). Caveats: this is a reverse-engineered community document, not an official Mackie spec. The doc states the HUI's internal fader resolution is about 9 bits. HUI meters have only 13 coarse steps per side, so they cannot support accurate dB readouts or peak hold numbers. (https://htlab.net/computer/protocol/mackie-control/HUI.pdf)
- [CONFIRMED] Pro Tools allows up to four MIDI controllers, and the row number sets their order. The 2025.10 Reference Guide lists Command|8, HUI, Surround Panner and NI Komplete Kontrol, so HUI is the only general-purpose surface protocol and Mackie Control is not listed.
  - Confirmed with one correction. The Reference Guide says 'The MIDI Controllers page lets you configure up to four different MIDI controllers' and 'The number of the row indicates the order of the selected controllers'. The Type list reads 'Command | 8 (Windows only)', HUI, Surround Panner, NI Komplete Kontrol. On macOS the general-purpose choice is therefore HUI only. Mackie Control/MCU is not offered, and the Behringer WING guide likewise says to use Mackie HUI for Pro Tools. The row colour 'corresponds to the controller focus around Pro Tools track and plugin controls'. (https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_2025.10.pdf)
- [UNCERTAIN] HUI in Pro Tools is limited to 4 ports (32 faders), and the lowest port always covers channels 1-8, so a second set of HUI devices shows the next banks rather than mirroring the UF8. HUI metering is unavailable while EUCON is enabled.
  - The cited page is SSL Live console help (ipMIDI), not UF8 documentation. Confirmed: 4 HUI controllers x 8 channels = 32. SSL Live says 'A maximum of four ports per DAW is possible in Pro Tools via HUI (up to 32 DAW control faders)', which agrees with the Avid four-controller limit. Corrected: 'the lowest port will always be DAW channels 1-8' is SSL Live's own port mapping. In Pro Tools generally, the row number in Peripherals > MIDI Controllers sets bank order (Avid Reference Guide). The conclusion holds: extra HUI controllers get later banks and do not mirror. The UF8 and WING guides both add HUI controllers #2/#3 to extend the surface. UNVERIFIED: 'Metering is unavailable when EUCON is enabled' is an SSL Live statement and has not been checked for UF8/V-MIDI or in Avid documentation. (https://livehelp.solidstatelogic.com/Help/DAWControl.html)
- [CONFIRMED] The UF8 talks to Pro Tools over HUI through SSL V-MIDI ports, one HUI controller per UF8 (Layer 1 uses ports 1-4). Its LCD shows 4-character names and '12-segment track metering + clip'.
  - Confirmed by UF8 User Guide Rev5. It says 'The HUI ... protocol is the way in which Pro Tools communicates with UF8'. 'DAW 1 (LAYER 1): SSL V-MIDI Ports 1-4' means one port per UF8 unit: the 1st UF8 uses Port 1 and the 2nd–4th use Ports 2–4. Layer 2 uses ports 5–8 and Layer 3 uses 9–12, so Ableton on Layer 2 would use V-MIDI 5. Setup: 'Configure each UF8 unit as a HUI Type', Receive From/Send To 'SSL V-MIDI Port 1 Source/Destination'. Pro Tools LCD: 'TrkNam - Displays the 4-character track name' and 'DAW Track Metering - 12-segment track metering + clip'. SSL also says it has 'added a number of features such as CHANNEL and PLUGIN mode' on top of HUI. Caveat: Rev5 predates SSL 360 v2.1, which changed the name length (next claim). A single UF8 uses only one of Pro Tools' four MIDI-controller slots. (https://eu1.download.solidstatelogic.com/UF8/SSL%20UF8%20User%20Guide_Rev5.pdf)
- [UNCERTAIN] SSL 360 V2.1 (Aug 2026) shows 8-character track names and Pro Tools track colours on the UF8 and UF1. This means SSL already adds a non-HUI Pro Tools data channel (probably PTSL) on top of HUI.
  - Facts confirmed, mechanism unverified. The SSL press release, datelined 'Oxford, UK - 11 August' with page metadata 2026-08-11, says 'UF8 and UF1 now display longer eight-character track names' and that they 'reflect Pro Tools track colours directly on their displays'. It also says 'UC1 now communicates directly with Pro Tools solo and mute functions'. HUI carries only 4-character names and has no colour message, so some non-HUI data path must exist. That part is a sound inference. 'Probably PTSL' is UNVERIFIED: the release names no mechanism and says nothing about PTSL, EUCON or HUI in a Pro Tools context. It fits PTSL GetTrackList (full name plus hex colour) and SetTrackMute/SoloState. Implication: a bridge that only proxies HUI will still see 4-character names. It has to read names and colours through PTSL itself. (https://ssl.hummingbirdmedia.com/ssl-enhances-the-industry-standard-u-series-controller-ecosystem-with-ssl-360-v21-update)
- [CONFIRMED] Pro Tools inserts on audio, Aux and Instrument tracks are pre-fader; only Master Fader inserts are post-fader. A per-track AAX meter therefore reads pre-fader, pre-mute levels.
  - Insert placement is confirmed by the Reference Guide: 'Audio, Auxiliary Input, and Instrument track inserts are pre-fader, and Master Faders inserts are post-fader'. Routing Folder tracks also have inserts and their placement is not stated in that sentence. The 'pre-mute' part is not stated by Avid; it is UNVERIFIED, though consistent with mute acting at the fader/output stage. More important for this project: Pro Tools' own track meters follow Options > Pre-Fader Metering ('With post-fader metering, the level meters respond to fader position'). Post-fader is the default, and Master meters are always post-fader. So an insert-based AAX meter will not match Pro Tools' on-screen meters with the default setting. (https://resources.avid.com/SupportFiles/PT/Pro_Tools_Reference_Guide_2025.10.pdf)
- [CONFIRMED] An AAX plug-in learns its own track name through AAX_eNotificationEvent_TrackNameChanged (Pro Tools 11.2+). TrackUID and TrackPosition are 'not currently sent' and there is no colour notification. JUCE passes the name to AudioProcessor::updateTrackProperties.
  - Confirmed in the AAX SDK 2.9.0 bundled in JUCE master (AAX_SDK_CURRENT_REVISION 20209000). TrackNameChanged ('AXtn') is marked 'Supported in Pro Tools 11.2 and higher'. TrackUIDChanged ('AXtu'), TrackPositionChanged ('AXtp') and InsertPositionChanged are marked '(not currently sent)'. No track-colour notification exists. The only colour enum is AAX_EHighlightColor, which is for control highlighting. JUCE's AAX wrapper handles AAX_eNotificationEvent_TrackNameChanged and calls pluginInstance->updateTrackProperties(props). As a result, an AAX plug-in cannot reliably tell which track index it sits on. (https://github.com/juce-framework/JUCE/blob/master/modules/juce_audio_plugin_client/AAX/SDK/Interfaces/AAX_Enums.h)
- [REFUTED] The AAX SDK is now dual-licensed (commercial or GPLv3, since 2.8.0) and bundled with JUCE. Retail Pro Tools still needs PACE (Eden/wraptool) signing with an iLok, plus Avid authorization to release; developers report the signing tools are free once approved.
  - The 'since 2.8.0' detail is wrong. JUCE added the AAX SDK LICENSE.txt ('subject to commercial or open-source licensing ... Or: You may also use this code under the terms of the GPL v3') in commit 9883d0c on 2024-05-23. At that commit the bundled AAX_Version.h shows AAX_SDK_CURRENT_REVISION 20207000 (2.7.0). JUCE 8.0.0 says 'Bundled the AAX SDK', 8.0.3 'Updated the AAX SDK to 2.8.0', and current master ships 2.9.0. So the dual licence predates 2.8.0. The cited Dplug guide confirms PACE Eden signing ('once PACE grants you access to PACE Eden'), wraptool, an iLok licence and 'You can't ever release AAX plug-ins without Avid's approval'. Unsigned builds run only in a Pro Tools Developer build. 'Signing tools are free once approved' is not in that source and is UNVERIFIED. (https://github.com/juce-framework/JUCE/blob/master/modules/juce_audio_plugin_client/AAX/SDK/LICENSE.txt)
- [UNCERTAIN] The EUCON SDK is for applications to be controlled by Avid surfaces, and EUCON has never been open to third-party hardware or surfaces, so a meter-bridge client cannot use it.
  - The first part is confirmed. developer.avid.com/eucon says 'Note that the EUCON SDK is for software developers who would like their software to be controlled by Avid hardware or control apps.' The page offers a 'Download Evaluation Toolkit'. It says nothing either way about third-party surfaces, so 'has never been open to third-party hardware' is UNVERIFIED as an absolute statement. The practical conclusion stands: no public SDK lets a third-party app act as a EUCON surface toward Pro Tools. Separately, SSL documentation reports that Pro Tools HUI metering stops when EUCON is enabled (UNVERIFIED for UF8). The bridge should warn users who have EUCON turned on. (https://developer.avid.com/eucon/)
- [CONFIRMED] The Behringer WING offers MCU or HUI emulation over USB MIDI or DIN5, with a configurable number of emulated controllers. For Pro Tools, Behringer's DAW guide reportedly uses HUI slots #1-#3 on WING ports 1-3 for 24 faders.
  - Confirmed. The WING Operation Manual (2025-10-20), SETUP > DAW, lists 'CONNECTION: select between DIN5 or USB MIDI', 'EMULATION: select between MCU or HUI protocols' and 'CONFIGURATION: determines the number of DAW controllers emulated'. The Behringer 'WING DAW-CONTROL V1.0' guide (the text was retrieved but its exact URL was not recorded) gives the Pro Tools steps: 'use Mackie HUI'; 'Select HUI in #1 and assign WING (port 1) ... set #Ch's to 8'; '#2 and #3 ... WING (Port 2) & WING (Port3)'. That is 24 faders. Corrections and additions from the same guide: 'USB required for multiple devices', so DIN5 gives only one 8-channel controller. On macOS the ports are named WING 1/2/3 (Master, Extender 1, Extender 2) plus WING 4 as a general MIDI port. Behringer recommends MCU for Ableton Live. (https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf)

### Missed points
- Slot budget conflict: Pro Tools allows only 4 MIDI controllers (Reference Guide 2025.10). One UF8 takes 1 HUI slot and a 24-fader WING takes 3. With both connected, all 4 slots are used and a HUI-emulating bridge has none left. A bridge added as an extra HUI controller would also get later banks (row order), never the UF8's bank, so it cannot 'follow' the UF8 that way.
- CoreMIDI constraint (from standard CoreMIDI semantics, not re-fetched this session): the bridge can listen to the 'SSL V-MIDI Port 1 Source' (UF8 to Pro Tools) stream. It cannot read what Pro Tools sends to SSL 360's 'SSL V-MIDI Port 1 Destination', and that direction carries meters, 4-character names, LEDs and fader positions. To follow the UF8 bank in Pro Tools, the bridge has to be a man-in-the-middle proxy. It would create its own virtual destination and source, have Pro Tools' HUI row #1 point at them, forward traffic to and from SSL V-MIDI, and parse or inject HUI. Injecting HUI fader-touch and fader-move messages plus mute/solo/select button pairs on that proxied port is the only verified way to change Pro Tools volume without wiping automation. That proxy design is an inference and needs testing with SSL 360 (e.g. whether SSL 360 tolerates being re-routed).
- HUI has no absolute bank offset or track-index message (inferred from the HUI.pdf message set; UNVERIFIED as exhaustive). The bridge cannot learn which Pro Tools track sits on strip 1 from HUI alone. It would have to match 4-character HUI names against PTSL GetTrackList names, which is ambiguous when tracks share a 4-character abbreviation.
- Meter fidelity: neither PTSL nor any Avid API exposes meter levels. HUI gives only 13 steps (-60 dB down to below -60, up to clip) per side, for at most 8 tracks per HUI slot. Accurate dB and peak-hold readouts would need a tap plug-in on each track. An AAX tap needs PACE/Avid approval and is pre-fader. Pro Tools' own meters default to post-fader (Options > Pre-Fader Metering is a global toggle; Master meters are always post-fader). Peak hold options are 3 Second, Infinite or None.
- PTSL event subscriptions are per track_id. Selection, track list, name and colour changes, and volume all have to be polled with GetTrackList. That call goes through the PTSL command queue; its latency and cost at about 10 Hz are UNVERIFIED and should be benchmarked. PTSL setters address tracks by name, and SetTrackColor uses palette indexes.
- Volume values in SetTrackControlBreakpoints run from -1.0 to 1.0 with no documented dB mapping. The companion GetTrackControlInfo, which would return range and steps, is also 'Defined but not yet implemented' in 2025.10. Per Presto, it was removed along with the breakpoint commands in the 2026.04 SDK.
- The PTSL SDK files are marked 'CONFIDENTIAL ... subject to an Avid SDK license'. The GitHub copy used as a source (danielrdehaan/Scripts) redistributes it. The project should take the SDK from developer.avid.com and must not ship or commit the proto. py-ptsl is a usable reference client, but its PTSL_pb2 at 601.0.0 lags newer SDKs.
- SSL 360 v2.1 already shows 8-character names and colours on UF8/UF1 through an unpublished channel. The PTSL session-per-client model should allow SSL 360 and the bridge to coexist, but that is UNVERIFIED. Test running both PTSL clients at once.
- Users running EUCON (e.g. Avid Control app or S1) alongside HUI may lose HUI metering (SSL Live statement, UNVERIFIED for UF8). The bridge should detect this and warn.
- Pro Tools draws a coloured 'controller focus' outline on the tracks each MIDI controller covers (Reference Guide). This shows that Pro Tools tracks bank position internally, but no API exposes it.
- The WING in Pro Tools needs USB for more than 8 faders (DIN5 supports a single device). Its macOS ports are named 'WING 1/2/3' (plus 'WING 4' as general MIDI). The bridge can recognise the WING's HUI ports by those names when building the layout.
