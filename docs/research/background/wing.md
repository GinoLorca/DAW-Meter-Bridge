# Behringer WING family as a source for a macOS DAW meter bridge

## Summary

- **There are two separate ways the WING could feed a meter bridge.**
  1. **WING as a DAW controller (Mackie MCU/HUI over USB MIDI).** The WING receives the DAW's control-surface traffic, but it does not re-publish any DAW track data (names, meters, mute/solo) on its network protocols.
     - The native/OSC parameter tree only contains DAW-mode *configuration* nodes.
     - The native meter subscription only covers the console's own audio objects.
     - So a Mac app that wants DAW track meters while the WING is the controller has two options:
       - get them from the DAW directly, or
       - sit in the MIDI path between DAW and WING as an MCU proxy. MCU meter resolution is coarse (13 steps).
  2. **WING as a console (its own channel meters).** This is very well supported. The native binary protocol on TCP/UDP 2222 streams per-channel input/output L/R levels plus gate/dyn data:
     - signed int16 values in 1/256 dB, for up to 40 channels, 8 aux, 16 bus, 4 main, 8 matrix, 8 DCA, FX, monitor and RTA;
     - about 50 ms per update (from a third-party reading of the latest doc, not confirmed on hardware);
     - names, colors, mute, solo and select are available by native or OSC parameter access.
  - Mode 2 is the precise, well-documented path. It equals "DAW meters" only when DAW tracks are routed out over USB into WING channels (hybrid/summing workflow).
- **Recommendation for the UF8-first product:** treat the WING as a *console-metering source*, implemented natively in Swift over TCP/UDP 2222. "WING as DAW controller" is a secondary mode that needs the DAW-side meter feed the UF8 path needs anyway.

---

## (a) WING DAW remote-control modes (MCU / HUI)

**Protocols and DAWs**
- The WING emulates Mackie MCU or Mackie HUI.
- DAW control arrived in firmware 1.07 "DAW Control", described as "DAW remote control (MCU/HUI), up to 24 faders via USB" ([release notes](https://survivethegig.com/wing-firmware-version-1-07-daw-control-release-notes/), [wing-docs mirror](https://wing-docs.com/version/1.07)).
- The official *WING DAW-CONTROL V1.0* document ([Music Tribe CDN](https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf); text read from the [wing-docs.com mirror](https://wing-docs.com/pdf/DAW_Documentation.pdf)) gives setup for Cubase/Nuendo, Ableton Live, Logic, Studio One and REAPER (all MCU) and Pro Tools ("please use Mackie HUI").
- It also warns that "the implementation is dependent on a predefined transmission protocol and the scope of possibilities is limited."
- The live parameter schema confirms the preset list: `/$ctl/daw/preset` has cubase, live, logicx, nuendo, protools, reaper, studioone. The DAW nodes are:
  - `/$ctl/daw/on`
  - `/$ctl/daw/conn` (DIN|USB)
  - `/$ctl/daw/emul` (MCU|HUI)
  - `/$ctl/daw/config`
  - `/$ctl/daw/ccup`
  - `/$ctl/daw/disjog`
  - `/$ctl/daw/$on` and related button-select flags
  - Source: [libwing propmap](https://github.com/dannyfiresnake/libwing/blob/main/src/propmap.jsonl), generated from a WING Compact on fw 3.0.5.
- Behringer's product page says the WING works with any software that supports MCU/HUI ([behringer.com/wing](https://www.behringer.com/wing)).

**Ports, channels and banks (full-size WING)**
- USB exposes 4 MIDI ports. On macOS they appear as WING 1–4:
  - MIDI DAW 1 = master MCU/HUI
  - MIDI DAW 2 = Extender 1
  - MIDI DAW 3 = Extender 2
  - MIDI Control = general MIDI
- "USB required for multiple devices." DIN is limited to "Control+Single MCU" ([DAW doc p.3](https://wing-docs.com/pdf/DAW_Documentation.pdf); [Remote Protocols 3.0.6 p.137](https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf)).
- The `/$ctl/daw/config` enum on the full WING is: CC (custom controls only), MSTR (single MCU), MSTR1EXT (MCU + extender), MSTR2EXT (MCU + 2x extender). This comes from the node-definition dump in [Remote Protocols 3.0.6 p.27–28](https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf).
- So the maximum is 24 DAW strips (3×8). Banking moves "in banks of 8" and single-channel steps ("<4 / 4>").
- REAPER needs surface offsets of 0/8/16 ([DAW doc](https://wing-docs.com/pdf/DAW_Documentation.pdf); RP 3.0.6 REAPER appendix pp.243–249).
- Known quirk: a Mixbus user saw a one-track offset with MCU+2XT on the WING and had to write a custom .mcp map ([Harrison forum](https://forum.harrisonconsoles.com/printthread.php?tid=12777)).

**Model limits**
- **WING Rack:** "DAW Mode on Rack is limited to CC buttons and one Mackie Control device" (RP 3.0.6 p.11).
- **Compact and Rack:** only 2 USB MIDI ports (MIDI DAW 1–2) (RP 3.0.6 p.137).
- **Compact:** the schema captured from a Compact lists `/$ctl/daw/config` as only "USER BUTTONS ONLY" or "BUTTONS + 8 FADERS" ([libwing propmap](https://github.com/dannyfiresnake/libwing/blob/main/src/propmap.jsonl)). So the Compact appears limited to 8 DAW faders. This is inferred from the schema and not confirmed on hardware.

**What the WING displays in DAW mode**
- Patrick-Gilles Maillot (author of the protocol doc) says that in DAW mode "Wing scribbles emulate an MCU-like display", black-and-white only; DAW track colors are not supported via SysEx ([behringer.world thread](https://behringer.world/viewtopic.php?p=12955)).
- Maillot's wdaw2wing app pushes remote scribble names onto a master WING's DAW layers, which is consistent with the WING rendering MCU LCD text ([behringer.world](https://behringer.world/viewtopic.php?p=11748); [Maillot WING page](https://sites.google.com/site/patrickmaillot/wing)).
- **UNVERIFIED:** whether the WING's per-strip LED meters show **DAW** meter data (MCU channel-pressure meters) in DAW mode. Neither the official DAW doc nor Remote Protocols 3.0.6 mentions DAW metering. I found no forum confirmation either way.
- Either way, MCU/HUI names are short (MCU LCD is about 7 characters per strip) and the WING strip displays are small, which is part of why an external bridge is useful.

**Can a Mac app read DAW data back from the WING over the network?**
- **No evidence that it can.**
- The full parameter tree (about 78k entries in libwing's propmap) has no DAW track name, level or state nodes, only DAW config and DAW custom-control layers (`/$ctl/user/daw1..4`).
- The native meter tokens (0xa0–0xaf) cover only console objects (RP 3.0.6 pp.96–97).
- What the app *can* do over the network:
  - toggle DAW mode (`/$ctl/daw/$on`, hash beefaeab; RP 3.0.6 p.28);
  - read/change the DAW config.

**MCU meter format, if the app proxies MIDI**
- MCU level meters are MIDI channel pressure `0xD0`. The data byte is `(strip<<4)|level`:
  - level 0x0–0xC (13 segments);
  - 0xE sets overload, 0xF clears it.
  - Source: [Ardour mackie/meter.cc](https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc).
- That is very coarse for a "large meter" display. Linux's [mcpdisp](https://appstream.ubuntu.com/jammy/universe/metainfo/mcpdisp.html) is prior art for drawing MCU scribble and meter data on screen.
- macOS CoreMIDI cannot passively snoop another app's MIDI connection. A proxy needs virtual endpoints:
  - the DAW's Mackie Control devices point at the app's virtual ports;
  - the app forwards traffic both ways to WING 1–3 and parses LCD SysEx, meters and mute/solo/select/rec LED notes.
  - This is a design inference, not a documented WING feature.

---

## (b) WING network protocols for console meters, names, colors and mute/solo

**Primary documentation**
- Behringer authorizes Patrick-Gilles Maillot to publish and maintain *WING Remote Protocols*. He is not a Music Tribe employee (RP 3.0.6 p.9).
- Versions found:
  - V3.0.5 ([CDN](https://cdn.mediavalet.com/aunsw/musictribe/mzolJdOzu0WZG59pX2LDkA/drJQVBUjakq76Xn2GcaT0Q/Original/WING%20Remote%20Protocols%20v3.0.5.pdf));
  - V3.0.6-27 ([empowertribe CDN](https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf), the version I read in full; the mediavalet V3.0.6-30 URL returned HTTP 500);
  - the current one on Maillot's Google Drive ([link from pmaillot/wapi README](https://github.com/pmaillot/wapi)), reported by a third party as **V3.1.1-a for FW 3.1.1** ([channel-strip notes](https://github.com/joelhooks/channel-strip/blob/main/.brain/resources/wing-protocol-notes.svx)). I did not read V3.1.1 myself.

**Discovery**
- Send the 5-byte UDP datagram `WING?` to port 2222 (broadcast or unicast).
- Reply: `WING,<ip>,<name>,<model>,<serial>,<firmware>`. Model is `ngc-full` (full WING), `wing-compact` or `wing-rack` (RP 3.0.6 p.16; [libwing Discovery.md](https://github.com/dannyfiresnake/libwing/blob/main/Discovery.md)).

**OSC (UDP 2223)**
- Standard OSC messages only (no bundles); maximum packet size 32 KB.
- Command forms:
  - GET with a bare address returns a `,sff`/`,sfi` triplet (display string, raw 0..1 value, real value).
  - SET takes `,s`/`,i`/`,f`; sending `-1` toggles a 0/1 parameter.
  - Bulk set to `/` or a node with a `"key=value,..."` string returns `/*` "OK".
  - `*` dumps a subtree; `?`/`#` describe a node; `/%port/` redirects the reply.
- Event subscription: `/*s` (triplets), `/*S` (native-typed values) or `/*b` (binary). Each change is delivered on both the plain and the `$`-shadow address.
- **Only ONE OSC subscription is active at a time (last requester wins), and it must be renewed under 10 s** (RP 3.0.6 pp.16, 30).
- A forum post adds that X32 allowed 16 OSC subscribers ([behringer.world](https://behringer.world/viewtopic.php?p=14236)). In practice, a meter-bridge app that relies on OSC subscription will fight with Bitfocus Companion, which renews `/*S` every 9 s ([companion connection-handler.ts](https://github.com/bitfocus/companion-module-behringer-wing/blob/main/src/handlers/connection-handler.ts)).
- **No meters over OSC.**

**Useful paths (RP 3.0.6 node tables)**
- Channel nodes `/ch/1..40/`:
  - `name` (16 characters maximum);
  - `col` (1..12 in 3.0.6; one third-party catalog lists 1..18 for newer firmware, **UNVERIFIED**);
  - `$name` / `$col` (read-only, reflect linked source);
  - `icon`, `led`;
  - `mute`, `$mute` (effective mute incl. DCA/mute group, 0..2);
  - `fdr` (−144..10 dB, 1024 steps), `$fdr`;
  - `$solo`, `$sololed`;
  - `tags`.
- Selected strip: `/$ctl/$stat/selidx` (1..76).
- Same pattern for `/aux`, `/bus`, `/main`, `/mtx`, `/dca`.
- Surface/meter tap config: `/cfg/mtr/mtrsfc/{in,bus,main,mtx,dca}` = PRE|POST.
- The Companion module uses the same paths ([channel.ts](https://github.com/bitfocus/companion-module-behringer-wing/blob/main/src/commands/channel.ts), [control.ts](https://github.com/bitfocus/companion-module-behringer-wing/blob/main/src/commands/control.ts)).

**Native binary protocol (TCP 2222)**
- Escape byte 0xDF selects a channel: `0xDF, 0xD0+ChID`. A literal 0xDF in data is sent as `0xDF 0xDE`.
- Channel IDs:
  - ChID 1 (`DF D1`) = audio engine and control requests;
  - ChID 3 (`DF D3`) = meter requests.
- Token stream (big-endian):
  - 0x00–0x3F small ints;
  - 0x80–0xBF short strings;
  - 0xD3 int16, 0xD4 int32, 0xD5 float32, 0xD6 raw float;
  - 0xD7 + 4-byte node hash selects a node;
  - 0xDC data request, 0xDD node-definition request, 0xDE end, 0xDF node-definition response.
- Parameters are addressed by 32-bit hashes; for example `0xf50f69f8` = /ch/1/mute (RP 3.0.6 pp.26, 91–95).
- Connections time out after 10 s of receive inactivity. libwing re-sends `DF D1` every 7 s.
- **Once connected, changes made at the console are pushed continuously** (RP 3.0.6 p.111; [libwing wingmon](https://github.com/dannyfiresnake/libwing/blob/main/tools/wingmon.rs)). There is no single-subscriber limit like OSC.
- Client limit is 16 TCP clients in 3.0.6 (p.16, p.91). Two third-party sources report **24 from FW 3.1.1** ([wing-mcp-server docs](https://github.com/bawaaaaah/wing-mcp-server/blob/main/docs/wing-protocol/02-osc-protocol.md), [channel-strip notes](https://github.com/joelhooks/channel-strip/blob/main/.brain/resources/wing-protocol-notes.svx)).
- WING Edit and Mixing Station use the native protocol ([forum, Maillot](https://behringer.world/viewtopic.php?p=14236)).

**Meter subscription (native ChID 3, data returned over UDP)** (RP 3.0.6 pp.96–97, 122–123)
- Setup:
  - `DF D3`, then `D3 <port.w>` declares the client UDP port;
  - then `D4 <reportId.l>`;
  - then `DC <type> <idx>... DE`.
- Index bytes are **0-based**. For example `DC A0 00 01 08 A6 04 DE` requests channels 1, 2, 9 and FX 5.
- Type tokens:
  - A0 channel (1–40), A1 aux (8), A2 bus (16), A3 main (4), A4 matrix (8);
  - A5 DCA (8), A6 FX (16), A7 source group (16), A8 output group (11);
  - A9 monitor, AA RTA;
  - AB–AF "V2" versions of channel/aux/bus/main/matrix.
- **Meter data times out after 5 s**; re-send `D4 <same id>` to renew. The doc example renews with `dfd3 d400000002 dfd1`. libwing renews every 3 s.
- UDP packet layout: `<reportId 4 bytes><int16 BE words...>`, in request order.
- Word layout:
  - channel/aux/bus/main/matrix: 8 words = in L, in R, out L, out R, gate key, gate gain, dyn key, dyn gain;
  - V2: 11 words (adds gate LED, dyn state, automix gain);
  - DCA: pre-fader L/R, post-fader L/R;
  - FX: in L/R, out L/R, 6 state words;
  - monitor: solo L/R, mon1 L/R, mon2 L/R;
  - RTA: 120 bands.
- Scale: **levels are 1/256 dB**. Gate/dyn gain words are 1/256 steps scaled per plugin model ("for most of them 1.0 (256) maps to 20 dB"). FX state words use dB = value × 6/2048.
- One third party found RTA uses /128 by measurement ([wing-mcp-server 04-metering.md](https://github.com/bawaaaaah/wing-mcp-server/blob/main/docs/wing-protocol/04-metering.md)).
- **Update rate:** not stated in 3.0.6. A third-party reading of V3.1.1 says the WING sends values "about every 50 ms" ([channel-strip notes](https://github.com/joelhooks/channel-strip/blob/main/.brain/resources/wing-protocol-notes.svx)). wing-mcp-server also says ~20 Hz. This is reasonably corroborated but I did not confirm it on hardware.
- For a smooth 60 fps meter bridge, the app should interpolate and apply its own ballistics/peak-hold.
- **UNVERIFIED:** whether channel "output L/R" is post-fader or post-processing pre-fader. libwing's demo plots words 2–3 (output) as the channel meter ([wingmeters.rs](https://github.com/dannyfiresnake/libwing/blob/main/tools/wingmeters.rs)), and Maillot's Windows `wmeters` offers PRE or POST channel views.
- Working Rust reference for the exact bytes: [libwing src/console.rs](https://github.com/dannyfiresnake/libwing/blob/main/src/console.rs) (`request_meter`, `read_meters`, `keep_alive_meters`).

**Open-source and other implementations**

| Project | Lang | Protocol | Meters | Notes |
|---|---|---|---|---|
| [dannyfiresnake/libwing](https://github.com/dannyfiresnake/libwing) (formerly dannydulai) | Rust + C FFI (`libwing.h`, cdylib) | Native + discovery | Yes | Includes a propmap of about 78k name→hash entries from Compact fw 3.0.5. License mismatch: GitHub LICENSE is Apache-2.0, Cargo.toml says MIT. Tools: wingmon, wingprop, wingmeters, wingschema. Could be linked into Swift via the C header. |
| [matterlobby/behringer-wing-typescript](https://github.com/matterlobby/behringer-wing-typescript) | TypeScript/Node | Native | Yes (`requestMeter`) | Port inspired by libwing; MIT. |
| [errere/behringer_wing_binary_data_interface_library](https://github.com/errere/behringer_wing_binary_data_interface_library) | C | Native stream codec | No | Small; MIT. |
| [bawaaaaah/wing-mcp-server](https://github.com/bawaaaaah/wing-mcp-server) | TypeScript | OSC control + native meters | Yes | Has a readable `docs/wing-protocol/` set; MIT; active Oct 2026. |
| [bitfocus/companion-module-behringer-wing](https://github.com/bitfocus/companion-module-behringer-wing) | TypeScript | OSC (`/*S`) | No | Good path catalog; MIT. |
| [ralfferreira/behringer-wing-mcp](https://github.com/ralfferreira/behringer-wing-mcp) | TypeScript | OSC | No | MIT. |
| wapi ([pmaillot/wapi](https://github.com/pmaillot/wapi), [x32ram.com/wapi](https://x32ram.com/wapi)) | C library | Native | Yes (`wMeterUDPPort`, `wSetMetersRequest`, `wRenewMeters`, `wGetMeters`) | Free binary download for Win/macOS/Linux. Source pulled from GitHub over GPL concerns; library v3.1.0-2. |
| Maillot tools ([WING page](https://sites.google.com/site/patrickmaillot/wing)) | Windows apps | Native | wmeters | wingemul emulator (Windows/Linux, simulated meters, no audio); wdaw2wing (paid; WING DAW layers driving a remote WING). |

- **No Swift/macOS-native WING library was found.**
- A Swift implementation is small: Network.framework UDP broadcast for discovery, an `NWConnection` TCP stream with the 0xDF escape/channel codec, and a UDP listener for meters.
- For node hashes, either query node definitions at runtime (`D7 <hash> DD` / `DA DD`) or embed a hash map; libwing's propmap is a ready-made reference.

---

## Which use makes sense for the meter bridge, and what the Mac app must implement

**A. Show DAW track meters while the WING is the DAW controller (MCU/HUI)**
- The WING cannot supply DAW meters or names over the network, so the data must come from the DAW. Two routes:
  1. **MCU proxy.** CoreMIDI virtual source/destination pairs that the DAW uses as Mackie Control + 2 XT. The app forwards both ways to WING 1–3 and parses:
     - meters (0xD0, 13 steps);
     - LCD SysEx (names, about 7 characters);
     - mute/solo/select/rec LED notes;
     - bank offset (to know which DAW tracks are on which WING strip).
     - Pros: one protocol for MCU-capable DAWs, and it knows the bank alignment.
     - Cons: coarse meters; Pro Tools uses HUI (different encoding); fragile ordering. Meter behavior varies by DAW (UNVERIFIED per DAW).
  2. **DAW-native meter feed** (remote script, OSC or plugin; covered by the other research topics), combined with the bank/offset info from MCU if needed.
- Rack/Compact users get at most 8 DAW strips.

**B. Show the WING's own channel meters (console or hybrid-summing workflow)**
- Implement:
  - discovery (UDP 2222 `WING?`);
  - a native TCP 2222 session with a keep-alive under 10 s;
  - a ChID 3 meter subscription with a UDP listener, renewing under 5 s;
  - decoding of int16/256 dB;
  - parameter reads for name/`$col`/`$mute`/`$solo`/`$fdr`/`selidx`, using native hashes (preferred: pushed changes, no single-subscriber limit) or OSC GET polling.
- Optional writes for mix-focus actions (mute/solo/select) are also possible.
- This gives 1/256 dB precision for up to 40 channels plus buses, gate/dyn gain reduction, and roughly 20 Hz updates.
- It equals DAW track meters only when DAW tracks are routed via USB into WING channels.
- Layout mapping: the full WING surface is 12 + 8 + 4 strips; the Compact is 3 × 4 + main.

**macOS packaging notes (medium confidence)**
- A sandboxed app needs `com.apple.security.network.client` and `com.apple.security.network.server` (to receive meter UDP on a bound port).
- Recent macOS enforces Local Network privacy, so add `NSLocalNetworkUsageDescription` ([Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)). The exact macOS version and broadcast specifics are UNVERIFIED.
- Development without hardware: Maillot's `wingemul` is Windows/Linux only, and one user could not run it on a Mac ([channel-strip notes](https://github.com/joelhooks/channel-strip/blob/main/.brain/resources/wing-protocol-notes.svx)).

## Open questions
- Does the user own a WING, and which model (full WING, Compact or Rack)? This changes the number of DAW strips (24 vs 8 vs buttons only) and the physical strip layout (12+8+4 vs 3×4) to align meters with.
- Will the WING be used as the DAW controller (MCU/HUI), or as an audio interface/console with DAW tracks routed via USB into WING channels? Only the second gives precise meters from the WING itself.
- UNVERIFIED: in DAW mode, do the WING's per-strip LED meters display DAW (MCU/HUI) meter data, and does that differ between MCU and HUI?
- UNVERIFIED: is the channel meter 'output L/R' post-fader or pre-fader/post-processing, and is it affected by /cfg/mtr/mtrsfc tap settings?
- What is the exact meter update rate and the silence/floor value of the int16 meter words on current firmware (3.1.x)? This needs a packet capture on hardware.
- Does Remote Protocols V3.1.1-a (current) change any meter tokens, the client limit (16 vs 24), the color range (1..12 vs 1..18) or the node hashes? Are node hashes stable across firmware and models?
- Would an MCU MIDI proxy between the DAW and WING ports work reliably in the user's DAW (bank offsets, extender ordering, SysEx LCD), and does that DAW emit MCU meter messages at all?
- Licensing: libwing's GitHub LICENSE file is Apache-2.0 but Cargo.toml says MIT. Which applies if the app links it?
- How does macOS Local Network privacy and App Sandbox affect UDP broadcast discovery and binding a UDP meter port in a distributed (notarized or App Store) build?

## Fact-check
- **CONFIRMED**: The WING emulates Mackie MCU or HUI over USB MIDI. USB exposes 4 ports (macOS WING 1–4: master, Extender 1, Extender 2, general MIDI), giving up to 24 DAW faders (MCU + 2 extenders). DIN is limited to custom controls plus a single MCU.
  - Confirmed by the DAW-Control V1.0 doc. It names the ports 'MIDI DAW 1 (macOS: WING 1) – Master unit', 'WING 2/3' Extenders 1/2 and 'MIDI Control (macOS: WING 4)', and says 'MCU implementation offers support for up to 24 faders' (HUI too). The DIN limit comes from a different document, Remote Protocols 3.0.6 p.137: 'DIN (limited to Control+Single MCU) or USB (Full surface)'. Caveat: the 4 ports exist only on the full-size WING. Compact and Rack expose 2. (https://wing-docs.com/pdf/DAW_Documentation.pdf)
- **CONFIRMED**: Official DAW presets: Cubase, Nuendo, Live, Logic X, Pro Tools, REAPER, Studio One. Music Tribe recommends MCU for all of them except Pro Tools, which must use HUI.
  - The /$ctl/daw/preset enum is '-, cubase, live, logicx, nuendo, protools, reaper, studioone' (Remote Protocols 3.0.6 p.87; the same in libwing propmap.jsonl). The DAW doc says 'Music Tribe recommends Mackie MCU' for Cubase/Nuendo, Live, Logic, Studio One and Reaper, and for Pro Tools 'please use Mackie HUI'. The cited mediavalet URL returned an empty file, so I verified against the identical wing-docs.com copy. (https://wing-docs.com/pdf/DAW_Documentation.pdf)
- **CONFIRMED**: WING Rack DAW mode is limited to custom-control buttons and one Mackie Control device. Compact and Rack expose only 2 USB MIDI ports, and the Compact's DAW config enum offers only 'user buttons only' or 'buttons + 8 faders'.
  - Rack: 'DAW Mode on Rack is limited to CC buttons and one Mackie Control device' (3.0.6 p.11). Ports: 'Wing Compact and Rack come with 2 separate MIDI ports' (p.137); on macOS they are named '(WING) Port 1..2' with WING-Compact/WING-Rack prefixes. Caveats: (1) the official doc lists only the generic enum CC, MSTR, MSTR1EXT, MSTR2EXT. The two-value Compact enum (CC='USER BUTTONS ONLY', MSTR='BUTTONS + 8 FADERS') comes from libwing's propmap.jsonl, which was dumped from a Wing Compact on fw 3.0.5. (2) Compact and Rack have 'no DAW control button(s)'. (https://github.com/dannyfiresnake/libwing/blob/main/propmap.jsonl)
- **CONFIRMED**: The WING's network parameter tree has only DAW-mode configuration nodes (/$ctl/daw/on, conn, emul, config, ccup, preset, $on, ...) and no DAW track names, levels or states. The native meter tokens cover only console objects, so DAW track meters cannot be read back from the WING over the network.
  - /$ctl/daw holds only on, conn, emul, config, ccup, disjog, preset, $on, $bpage and $btn* (3.0.6 p.87, 3.1.2-a, libwing propmap). No node mirrors MCU text, meters or track state, and meter tokens 0xa0–0xaf are all console objects. Caveats: this is absence of evidence from schema dumps, not a statement from Behringer. There is also a partial workaround: source-device meters (0xa7) include a 'usb audio' group (3.1.2-a footnote 92). DAW playback routed to WING USB returns can therefore be metered, but only per USB channel, not per DAW track. (https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf)
- **UNCERTAIN**: In DAW mode the WING scribble strips emulate an MCU-like black-and-white display; DAW track colors are not supported. Whether the WING strip LED meters show DAW meter data is not documented (UNVERIFIED).
  - The official doc only says each strip has 'a 2-line B/W scribble with a color LED above it' (3.0.6 p.11). The cited behringer.world thread returned HTTP 403, so I could not verify the DAW-mode color and display claims. Ardour's MCU code sends LCD text with sysex 0x12 (7-character pitch, 0x38 per line) and sends no color sysex, which is consistent with no track colors under plain MCU. Whether the WING LEDs show DAW meters is still UNVERIFIED. (https://behringer.world/viewtopic.php?p=12955)
- **CONFIRMED**: MCU meter messages are channel pressure 0xD0 with data byte (strip<<4)|level, level 0–12 (13 segments), 0xE/0xF to set/clear overload. DAW meters taken from MCU traffic are therefore coarse.
  - Ardour meter.cc writes (0xd0, (id()<<4)|segment) and uses low nibble 0xe/0xf for overload on/off. Caveat on the range: Ardour computes segment = lrintf((def/115.0)*13.0), with the comment 'we can use up to 13 segments', so it can send 0x0–0xD, not just 0–12. A parser should accept 0x0–0xD. Also from Ardour: meters are switched on by a 'Channel Meter Enable' sysex. Secondary, not verified here: a midibox forum thread says the host transfers 13 levels and the surface must decay them itself (about 300 ms per LED, per the Logic Control spec). (https://github.com/Ardour/ardour/blob/master/libs/surfaces/mackie/meter.cc)
- **CONFIRMED**: WING uses UDP 2223 for OSC and UDP+TCP 2222 for discovery ('WING?' returns 'WING,ip,name,model,serial,fw') and the native protocol. Connections time out after 10 s of inactivity.
  - 3.0.6 p.16: 'WING communicates via ports 2223 [UDP], and 2222 [UDP, TCP]'. The reply format is as stated, and 'Open connections will time out after 10 seconds of inactivity'. The native protocol is TCP 2222 (p.90). Meter data goes over UDP to a port the client chooses, not to 2222/2223. Model strings: 'ngc-full' for the standard WING (doc); libwing's Discovery.md confirms 'wing-compact'. (https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf)
- **CONFIRMED**: Only one OSC event subscription (/*s, /*S, /*b) can be active at a time (last requester wins), renewed under 10 s. Native TCP clients receive console changes continuously, with a limit of 16 clients in fw 3.0.6 (reported as 24 from fw 3.1.1).
  - 3.0.6 p.30: 'A single OSC subscription is active at any time, provided to the last requestor. Subscriptions must be renewed every 10 seconds.' The wapi wOpen section says console changes are 'data the application will continuously receive'. libwing's wingmon relies on exactly this. The current doc is V3.1.2-a, not 3.1.1. On p.16 it says 'up to 24 connected clients', but its native-interface chapter still says '(currently 16)'. The doc contradicts itself, so treat 24 as UNVERIFIED on hardware. (https://drive.google.com/file/d/1-iptgd2Uxw4qPEbmegG2Sqccf8AbRRfk/view)
- **CONFIRMED**: Meters are only available via the native protocol: select channel 3 with DF D3, then D3 <udp port>, D4 <report id>, DC <type><0-based idx>... DE. Data goes to the client UDP port as <4-byte report id><int16 BE words>, and must be renewed (resend D4 id) within 5 s.
  - Matches Table 4 and the example on pp.96–97, e.g. 'dfd3d400000002dca001dedfd1'. Indexes are 0-based: '0xdc 0xa0 0x00 0x01 0x08 ...' means channels 1, 2, 9. 'Meter data times out after 5 seconds.' Caveats: (1) the request travels inside the native TCP 2222 stream, and the examples switch back with DF D1. (2) Payload bytes equal to 0xDF must be escaped (DF DE). (3) The doc labels the meter channel inconsistently ('channel #3' in the text, channel 4 / ChID 3 in the table), but DF D3 is correct. (4) libwing packs the 4-byte id as id16+port16 and does not escape 0xDF in requests. (https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf)
- **CONFIRMED**: Channel/aux/bus/main/matrix meter groups return 8 words (in L/R, out L/R, gate key, gate gain, dyn key, dyn gain); V2 variants add gate LED, dyn state and automix gain. Levels are signed int16 in 1/256 dB. Coverage is up to 40 channels, 8 aux, 16 bus, 4 main, 8 matrix, 8 DCA, 16 FX, monitor and 120-band RTA.
  - Correct for 3.0.6 (Table 5, p.97). Other groups: DCA returns 4 words (pre/post fader L/R); FX returns 4 levels plus 6 state meters (band GR in dB = value*6/2048); monitor returns 6. Omitted from the claim: source (1–16 device groups) and output (1–11 device groups). Updates in V3.1.2-a: the wapi meter mask grows to 30 bytes and lists 'DCA 1-16', but the native token table still says dca 1…8; the local-ins source group returns 24 meters. (https://drive.google.com/file/d/1-iptgd2Uxw4qPEbmegG2Sqccf8AbRRfk/view)
- **REFUTED**: The WING sends meter packets about every 50 ms (about 20 Hz) during the 5 s subscription window, per a third-party reading of Remote Protocols V3.1.1 and a second implementation. Not stated in the 3.0.6 doc and not confirmed on hardware.
  - The ~50 ms / 5 s figure is in the official 3.0.6-27 doc itself, in the wapi 'Meters' section on p.122: 'WING will send back the respective meter data for 5 seconds, every approximately every 50ms.' V3.1.2-a says the same. The real rate on hardware is still unmeasured. libwing renews every 3 s (METERS_KEEP_ALIVE_SECONDS = 3). (https://cdn-media.empowertribe.com/f255e02a7d164692b3ac2aff862cfcad/WING%20Remote%20Protocols%20FW%203.0.6.pdf)
- **CONFIRMED**: Channel strip state paths: /ch/N/name (16 characters), /ch/N/col, /ch/N/$name and $col (linked), /ch/N/mute and $mute (effective), /ch/N/fdr and $fdr, /ch/N/$solo and $sololed. Selected strip is /$ctl/$stat/selidx (1..76).
  - The primary evidence is the 3.0.6 doc (p.47 table, p.30 subscription examples, p.83 /$ctl/$stat/selidx 1..76), not the cited channel.ts. channel.ts has name, col, $name, mute, fdr, $solo, $sololed and $presolo; selidx is in control.ts. Caveats: (1) col is a 1..12 palette index, not RGB. (2) $mute and $fdr appear only in the subscription examples, so 'effective' is UNVERIFIED. (3) Companion adds 1 to integer selidx values (it treats them as 0-based), so there is an off-by-one risk. (4) These are the WING's own mixer channels, not DAW tracks. (https://github.com/bitfocus/companion-module-behringer-wing/blob/main/src/commands/channel.ts)
- **CONFIRMED**: libwing (Rust with a C FFI header, cdylib) implements discovery, the native TCP protocol and meter subscription, and ships a 78k-entry name-to-hash map. It is the most complete open reference and could be linked from Swift. No Swift/macOS WING library was found.
  - Verified in the code: Cargo.toml has crate-type ["rlib","cdylib"]. libwing.h exposes wing_discover_scan, wing_console_connect, wing_console_request_meter, wing_console_read_meter and wing_name_to_id. The README says 'over 78,000 entries'. Caveats: (1) the propmap was generated from a Wing Compact on fw 3.0.5. (2) The license is inconsistent: Cargo.toml says MIT, the LICENSE file is Apache-2.0. (3) There are protocol quirks (see claim 9). (4) 'No Swift/macOS WING library' is UNVERIFIED: my search budget ran out before I could check. (https://github.com/dannyfiresnake/libwing)
- **CONFIRMED**: Maillot's wapi C library (free binaries for Windows/macOS/Linux, source removed from GitHub) provides wMeterUDPPort, wSetMetersRequest, wRenewMeters and wGetMeters. The current Remote Protocols PDF is hosted on his Google Drive.
  - The GitHub README says the repo 'no longer contains the wapi library for not strictly complying to GPL licensing'. x32ram.com/wapi offers Windows, macOS and Linux zips: a static libwapi.a, version 3.0.6-5. Apple Silicon/arm64 support is not stated. The four functions are documented on pp.122–123. The Drive file 1-iptgd2Uxw4qPEbmegG2Sqccf8AbRRfk is the Remote Protocols PDF, currently V3.1.2-a. The licensing terms for linking wapi into a distributed closed app are unclear. (https://github.com/pmaillot/wapi)

### Missed points
- Most important for this app: MCU meter data, track names, mute, solo and select travel from the DAW to the WING, i.e. to the WING's CoreMIDI destinations. A third-party Mac app can listen to the WING's sources (surface→DAW), but my understanding of CoreMIDI is that it cannot passively read what the DAW sends to another app's destination. This is inference from CoreMIDI design, not tested. The meter bridge would therefore need to either (a) sit in the middle as a MIDI proxy (DAW ↔ virtual ports created by the app ↔ WING 1–3), or (b) register as its own Mackie Control/Extender device in the DAW and follow banking. This decides the architecture.
- The current Remote Protocols doc is V3.1.2-a (FW 3.1.2 and above), not 3.0.6 or 3.1.1: https://drive.google.com/file/d/1-iptgd2Uxw4qPEbmegG2Sqccf8AbRRfk/view. Changes found: 24 clients on p.16 (but 'currently 16' in the native chapter), a 30-byte wapi meter mask with DCA 1–16, and a 24-meter local-ins source group. Pin the implementation against this version.
- The physical WING surface is split into a Left bank of 12 strips, a Center bank of 8 and a Right bank of 4, with the CC section in between (3.0.6 p.11). How MCU master + 2 extenders (3×8) map onto 12/8/4 is UNVERIFIED. The alignment UI must support uneven groups and gaps, not a uniform 24-strip grid.
- For Pro Tools the WING must run HUI. HUI meters and display use a different encoding from MCU 0xD0; I believe HUI meters use polyphonic aftertouch with left/right sides, but this is UNVERIFIED. The app would need a separate HUI parser.
- MCU meters must be enabled by the host ('Channel Meter Enable' sysex in Ardour) and the surface must decay them (about 300 ms per LED per the Logic Control spec, as cited on the midibox forum, a secondary source). MCU track names arrive as LCD sysex 0x12 with a 7-character pitch (6 usable) at 0x38 per line (Ardour strip.cc). Names will be truncated, and plain MCU carries no track colors.
- Source-device meters (token 0xa7) include a 'usb audio' group (V3.1.2-a footnote 92). If the WING is the Mac's audio interface, DAW outputs routed to separate USB channels can be metered at 1/256 dB over the network, a far finer fallback than 13-step MCU meters. How many meters the USB group returns is UNVERIFIED.
- USB caveat from the doc: changing the clock rate or USB audio channel count (including via snapshot load) drops USB, MIDI included, for a few seconds and can reset MIDI connections. The app must handle CoreMIDI endpoints disappearing and coming back, and must match ports by name: 'WING 1..4' on the full WING, '(WING) Port 1..2' on Compact/Rack, plus WING-Compact/WING-Rack prefixes on macOS.
- Porting libwing to Swift: it packs the 4-byte meter report id as id16+port16, does not escape 0xDF in requests, keeps the native link alive by sending DF D1 every 7 s and renews meters every 3 s, and its propmap came from a Compact on fw 3.0.5. Re-dump the schema from a full-size WING on current firmware.
- The Compact and Rack have no physical DAW button. A 24-fader DAW setup (MSTR2EXT) is only possible on the full-size WING over USB.
- Not verified: a Mac app doing UDP broadcast discovery and LAN TCP will likely trigger macOS Local Network privacy and need sandbox network entitlements. Check against Apple's docs.
- My web search budget ran out partway through, so a few sub-points stay UNVERIFIED: whether any Swift/macOS WING library exists, whether the WING shows MCU colors or DAW meters in DAW mode, and the HUI meter byte format.
