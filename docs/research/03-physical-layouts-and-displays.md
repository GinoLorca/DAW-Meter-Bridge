# Physical layout research: aligning on-screen meters with SSL UF8/UF1/UC1 and Behringer Wing channel strips

## Main conclusions for the design

1. **Store the layout as a list of strip positions in mm, not as "N equal-width meters".** Both target surfaces have uneven fader spacing:
   - **UF8:** faders are about 38.5 mm apart inside one unit. When two UF8s sit side by side, the jump from fader 8 to the next unit's fader 1 is about **161 mm**.
   - **Wing in DAW mode:** the three emulated 8-channel units straddle the console's fader sections. Unit 3 is split across a gap of about 186 mm (the custom-controls section).
   - A per-unit window (8 equal slots, which is how DAWWAY describes its "Fader Bank windows") works for UF8s but not for the Wing.
2. **Calibrate each display with two numbers:** pixels per mm, and the x-offset of its active area's left edge in mm. Then each meter's centre in pixels is `(strip_x_mm − display_left_mm) × px_per_mm`. Let the user nudge individual strips to correct parallax and measurement error.
3. **A 12.6" 1920×515 bar (about 309 mm active width) covers almost exactly one UF8's 8-strip zone (308 mm).** A 14.1" 3840×1100 bar (344 mm) covers it with spare room.
   - Two or three UF8s need one display per UF8, or a 37"/49" industrial bar display.
   - The Mac's limit on external displays becomes the main constraint at that point.

---

## 1. SSL UF8 / UF1 / UC1

### Official dimensions

| Unit | W × D × H (mm) | Weight | Faders | Source |
|---|---|---|---|---|
| **UF8** | **431.0 × 265.9 × 62.7** (17" × 10.5" × 2.4") | 2.9 kg unboxed, 5.0 kg boxed | 8 × 100 mm touch-sensitive motorised | [UF8 User Guide Rev7](https://eu1.download.solidstatelogic.com/UF8/SSL%20UF8%20User%20Guide_Rev7.pdf), p.8, and its "Detailed Dimensions" drawing on p.9 |
| **UF1** | **205.0 × 265.9 × 62.5** | 1.8 kg unit, 2.88 kg boxed | 1 × 100 mm motorised | [UF1 User Guide Rev9.1](https://eu1.download.solidstatelogic.com/UF1/SSL%20UF1%20User%20Guide_Rev9.1.pdf), pp.8–9; [SSL UF1 page](https://www.solidstatelogic.com/products/uf1) |
| **UC1** | **300 × 266 × 61** (11.8" × 10.5" × 2.4") | 2.1 kg, 4.5 kg boxed | none (plug-in strip/bus-comp controller) | [UC1 User Guide Rev13.1](https://eu1.download.solidstatelogic.com/UC1/SSL%20UC1%20User%20Guide_Rev13.1.pdf), p.9; [SSL UC1 page](https://www.solidstatelogic.com/products/uc1) |

All three units are the same depth (about 266 mm), so they line up in a row. [Sound On Sound](https://www.soundonsound.com/reviews/solid-state-logic-uf1) says the UF1 "sits perfectly in a row" with UF8s and/or a UC1.

### UF8 strip geometry (measured from SSL's official drawing)

SSL does not publish a fader pitch. I rendered the p.9 "Detailed Dimensions" drawing of the UF8 User Guide Rev7 at 400 dpi and measured pixel positions.

**Scale check:** the drawing's scale (0.21529 mm/px) reproduces every labelled dimension within 0.1 mm:
- 431.0 mm width
- 265.9 mm depth
- 332.1 mm and 48.5 mm on the front view

So the drawing is to scale.

| Quantity | Value |
|---|---|
| **Fader centre-to-centre pitch** | **38.5 mm** (seven gaps measured: 38.43–38.54 mm). Estimated uncertainty about ±0.3 mm. |
| Fader 1 centre from left chassis edge | **84.3 mm** |
| Fader 8 centre from right chassis edge | **77.1 mm** |
| Fader centres from left edge | 84.3, 122.9, 161.3, 199.8, 238.3, 276.9, 315.4, 353.9 mm |
| Fader bank position | Not centred: about 3.6 mm right of the chassis centreline |
| 8-strip zone (fader 1 − ½ pitch to fader 8 + ½ pitch) | 65.1 → 373.2 mm, **308.1 mm wide** |
| V-Pot and top soft-key centres | About 80.6 mm + 38.5·k, i.e. about 3.7 mm left of each fader centre |
| SOLO/CUT/SEL button column centre | About 67.6 mm + 38.5·k |
| UF8 LCD window (drawing outline) | About 320.8 × 38.8 mm, centred (55.2 mm from each side). This is the small display the user wants to replace. |
| **Fader 8 → next UF8's fader 1, units butted together** | **161.4 mm** (about 4.2 pitches) |

### UF1 and UC1 geometry

- **UF1:** measured from its p.9 drawing (scale checked against 205.0 and 265.9 mm). The single fader's centre is **45.0 mm from the UF1's left edge** (160 mm from its right edge).
- **UC1:** no faders. It only adds width (300 mm) to a row.

### Multi-unit arrangements

- **How many UF8s:** up to 4 UF8s make "a 32-channel control surface" (UF8 guide p.10). They chain through the THRU port, but the 3rd and 4th may need their own Mac USB port.
- **Unit order:** SSL 360° has "Identify & Drag To Re-Order". Clicking a unit's image flashes the SSL logo on that UF8, and you drag the images into left-to-right order (UF8 guide p.18). The UF8s then act as one contiguous bank, numbered left to right.
- **UF1 placement:** SSL gives no rule. Its fader focuses on the leftmost channel of the bank by default, or the master via the Master key. Master is not supported in Pro Tools ([SOS review](https://www.soundonsound.com/reviews/solid-state-logic-uf1)).
  - Plausible placements are right of the UF8s or between them (**UNVERIFIED** what is "typical").
  - The bridge should support an optional "focus/selected track" meter positioned over the UF1.

### Worked examples (units butted, no gaps; x measured from the left edge of the first UF8)

| Setup | Fader centres (mm) | Total width |
|---|---|---|
| 1 × UF8 | 84.3 + 38.5k, for k = 0…7 | 431 mm |
| 2 × UF8 | Unit 1 as above; unit 2: 515.3 → 784.9 | 862 mm |
| 3 × UF8 | Unit 3: 946.3 → 1215.9. Strip zone of all 24 strips: 65.1 → 1235.2, i.e. 1170 mm | 1293 mm |
| + UF1 on the right | UF1 fader at N·431 + 45.0 (907.0 mm for 2 UF8s, 1338.0 mm for 3) | Add 205 mm |
| + UC1 | No faders | Add 300 mm |

---

## 2. Behringer Wing (full size) and Wing Compact

### Official facts

| Item | Wing | Wing Compact | Source |
|---|---|---|---|
| Dimensions | **870 W × 575 D × 201 H mm**, 24 kg | about **453 W × 574 D × 225 H mm**, 15.9 kg | [Behringer Wing](https://www.behringer.com/en/wing/wing-black); [Wing QSG spec](https://warehousesound.com/r/behringerWINGmanual.pdf); [Behringer Wing Compact](https://www.behringer.com/en/wing/wing-compact) |
| Motor faders (100 mm) | **12 + 8 + 4** = 24 | **12 + 1** = 13 | same |
| Sections | Left 12 (inputs), Centre 8 (buses/DCAs), Right 4 (mains/matrices) | Left 12 + Main fader section | [Wing User Manual FW 3.1 (Oct 2025)](https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf), §4.2, p.14–15 |
| DAW remote | MCU or HUI emulation; MIDI over DIN5 or USB; DAW button in the Custom Controls section | The DAW LAYER button must be assigned to a CC | Same manual, p.26–27 and p.51 ("SETUP → DAW") |

On both models, every group of 4 faders shares one 320×48 LCD, so the faders are physically grouped in fours.

### DAW mode mapping (the most important Wing finding)

The manual (p.51) says SETUP → DAW → **CONFIGURATION** "determines the number of DAW controllers emulated by the console" and shows which console controls belong to each emulated controller. Figure 43 (p.52) shows the **"MCU + 2x EXTENDER"** setting with a numbered overlay. Reading that diagram:

| Emulated unit | MIDI port (macOS) | Physical faders | DAW strips |
|---|---|---|---|
| 1: MCU main | WING 1 (MIDI DAW 1) | Left L1–L8, plus the custom-controls/transport/wheel area | 1–8 |
| 2: Extender 1 | WING 2 | Left L9–L12 **+ Centre C1–C4** | 9–16 |
| 3: Extender 2 | WING 3 | Centre C5–C8 **+ Right R1–R4**, split by the custom-controls section | 17–24 |

So each 8-channel DAW bank is **not** contiguous on one section. A bridge laid out as "8 equal slots per unit" cannot line up with the Wing.

### DAW setup (official WING DAW-Control doc, read only via search snippets)

The official PDF ([WING DAW Documentation](https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf)) returned HTTP 500 every time I tried. Search snippets of it say:
- **Pro Tools:** use HUI. Peripherals → MIDI Controllers: #1 HUI on WING port 1 with 8 ch; #2 and #3 on WING ports 2 and 3 for the full surface.
- **Ableton:** "Mackie Control" on WING port 1, plus "Mackie ControlXT" on ports 2 and 3.
- **Limits:** the MCU implementation supports up to 24 faders. A community wiki says DIN only carries one MCU, so USB is needed for all three.

[Drew Brashler's CC reference](https://drewbrashler.com/2026/behringer-wing-custom-controls-reference/) lists DAW V-Pots as M1–M8 (main surface) and EXT1–EXT16 (extended surface), which is consistent with 24 DAW strips.

### Wing fader pitch (ESTIMATE, low–medium confidence)

There is no official figure. I measured the manual's Figure 9, a full-width line drawing of the fader surface, and checked its scale two independent ways:
- Overall width 870 mm / 1716 px = 0.507 mm/px
- 100 mm fader travel between a fully-up cap (L1) and a fully-down cap (C8) = 197 px, giving 0.508 mm/px

The two agree within 0.2%. The resulting estimates:

| Quantity | Estimate |
|---|---|
| Pitch within a group of 4 | **≈23.3–23.8 mm** |
| Across a 4-fader group boundary | **≈34.5 mm** |
| L12 → C1 (left-section bank buttons in between) | **≈62 mm** |
| C8 → R1 (custom-controls section in between) | **≈186 mm** |
| Fader centres from the console's left edge | L1 61.6, L2 84.9, L3 108.8, L4 132.1, L5 166.5, L6 189.9, L7 213.2, L8 236.5, L9 271.0, L10 294.3, L11 317.6, L12 341.5, C1 403.3, C2 426.6, C3 450.2, C4 473.8, C5 507.8, C6 531.3, C7 554.9, C8 578.2, R1 763.8, R2 787.1, R3 810.4, R4 834.0 mm |

All of these are **UNVERIFIED** until someone measures a real console.

**Wing Compact DAW mapping (which emulated units its 12 faders get): UNVERIFIED.**

---

## 3. Bar-type displays and how many UF8 strips each covers

"Strips" = active width ÷ 38.5 mm. "UF8 units" = active width ÷ 431 mm.

| Display | Active area W × H (mm) | Strips | UF8 units | px/mm (px per strip) | Inputs | Source / confidence |
|---|---|---|---|---|---|---|
| 8.8" 1920×480 (often natively 480×1920) | ≈217.0 × 54.2 (calculated) | 5.6 | 0.50 | 8.85 (341) | mini-HDMI / USB-C | Calculated; [DFRobot 8.8" is 480×1920 portrait](https://wiki.dfrobot.com/_SKU_FIT0941_8.8_480%C3%971920_DSI_Bar_Touch_display_for_Raspberry_Pi) |
| **12.3" 1920×720** (e.g. ASUS ROG Strix XG129C) | **292.03 × 109.51** | **7.6** (about 16 mm short of one UF8 zone) | 0.68 | 6.575 (253) | USB-C DP-Alt + HDMI; 10-point touch | [ASUS XG129C](https://rog.asus.com/de/monitors/accessories/rog-strix-xg129c/wtb/), high. Generic Amazon 12.3" bars use the same 1920×720 module family. |
| **12.6" 1920×515** (Wisecoco and others; panel BOE NV126B5M) | **≈309.3 × 83.0** | **8.0**, the best match to one UF8 zone (308.1 mm) | 0.72 | 6.207 (239) | mini-HDMI (some USB-C); touch on some versions | Marketplace listings give 309.31 × 82.97, which my diagonal calculation confirms; [52Pi EP-0190](https://wiki-md.52pi.com/docs/EP-0190), medium |
| **14.1" 3840×1100** (DFRobot DFR1125 / Wisecoco / KeebMonkey) | **344.2 × 98.6**; outline width 369.5 | **8.9** | 0.80 | 11.16 (430); 283 ppi | Single USB-C (video + touch + power) or mini-HDMI | [CNX Software](https://cnx-software.com/2024/10/27/14-inch-4k-ultra-wide-touch-display-for-raspberry-pi-and-lattepanda-boards), high |
| 14.5" 2560×720 | ≈354.5 × 99.7 (calculated) | 9.2 | 0.82 | 7.22 (278) | USB-C | Newegg listing only, low |
| 27.6" 1920×360 (signage) | 688.9 × 129.2 | 17.9 (16 strips need 739 mm, so too short for 2 UF8s) | 1.60 | 2.79 (107) | HDMI | [Santek](https://www.santechnology.com/products/digital_signage.php), medium |
| **37" 1920×540** (Winmate W38L100, BOE BM370A, Philips 37BDL) | **904.32 × 254.34** | 23.5. Covers **2 × UF8 (862 mm)** or the **entire Wing (870 mm)**. | 2.10 | 2.12 (82); low ppi | HDMI | [Winmate W38L100](https://www.directindustry.com/prod/winmate-inc/product-35784-2834715.html), medium. Industrial signage, unlikely to be on Amazon. |
| 49.5" stretched bar (Winsonic) | 1209.6 × 340.2 | 31.4. Covers all 24 strips of 3 butted UF8s (1170 mm). | 2.81 | — | HDMI | Search snippet only, low |

I found no 15.6" 3840×1100 or 16" bar on the market (**UNVERIFIED** that one exists).

### Fits for the Wing (using the estimated positions)

- **Left section (12 faders):** spans about 50–353 mm, so a 12.6" (309 mm) or 14.1" (344 mm) bar fits.
- **Centre section (8 faders):** spans about 392–590 mm (≈198 mm), so an 8.8" (217 mm) bar fits.
- **Whole Wing:** only a ≈37" 1920×540 bar covers all 24 faders.

### Fits for multiple UF8s

All 12–14" bar housings are well under 431 mm wide. One display per UF8 therefore fits side by side, with about 123 mm between the active areas of neighbouring 12.6" units.

---

## 4. macOS compatibility gotchas

1. **External display count limits.** This decides whether a "one bar per UF8" setup is even possible.
   - Base M1/M2: **1** external display.
   - Base M3: 2, and only with the lid closed.
   - Base M4/M5 and Pro chips: 2.
   - Max chips: 3–4.
   - A Thunderbolt dock does not raise the limit. DisplayLink USB adapters are the workaround and need a driver.
   - Source: [Plugable KB](https://kb.plugable.com/en_US/understanding-external-display-support-on-apple-m1-m2-m3-and-m4-chips).
2. **Some panels are natively portrait.** 8.8" 1920×480 boards show up as 480×1920 ([moOde forum](https://moodeaudio.org/forum/showthread.php?pid=60169)), and 52Pi lists its 12.6" as "515x1920".
   - macOS Rotation (System Settings → Displays) is needed.
   - Docks and adapters can hide the rotation option, and rotation sometimes doesn't persist after reconnecting.
   - [52Pi](https://wiki-md.52pi.com/docs/EP-0190) warns that "some macOS systems may experience compatibility issues" and that not all docks pass the 515×1920 mode. Connect directly to the Mac.
   - The app should use the `NSScreen` frame after rotation and never assume the screen is landscape.
3. **Unusual resolutions and EDID.** Apple Silicon has no built-in way to add custom modes, and ultrawide modes have gone missing on Apple Silicon before ([MacTrast on Apple's acknowledgement](https://www.mactrast.com/2020/12/apple-says-fix-is-on-the-way-for-issue-with-ultrawide-monitors-on-m1-apple-silicon-macs/amp/)).
   - [BetterDisplay](https://github.com/waydabber/BetterDisplay) offers EDID overrides on Apple Silicon (Pro licence), custom HiDPI modes, and rotation persistence.
4. **HiDPI.**
   - 14.1" 3840×1100 (283 ppi) is a candidate for 2× "looks like 1920×550". Whether macOS offers it automatically is **UNVERIFIED**.
   - 1920×515 has an odd height, so it cannot be an integer 2× mode and will run at 1×.
   - Meter drawing should use `backingScaleFactor` and snap to physical pixels.
   - Calibration must be stored in physical px/mm, independent of the scaled mode.
5. **Menu bar on the bar display.** With "Displays have separate Spaces" on, macOS can draw a menu bar on every display ([TroikaTronix](https://support.troikatronix.com/support/solutions/articles/13000029168-macos-how-to-turn-off-the-menu-bar-on-an-external-display)). That costs about 24–37 pt of a 515–720 px-tall panel.
   - The app needs a borderless window at a level above the menu bar, or the user must turn the setting off.
6. **No native touch on macOS.** Mac devices "don't have touch screen support integrated" ([CTOUCH](https://support.ctouch.eu/hc/en-us/articles/360008669640)).
   - A USB touch overlay needs the commercial UPDD driver, and touch has to be mapped to the right screen ([Elo/UPDD](https://elosupport.elotouch.com/hc/en-us/articles/31650699605399-How-can-I-Identify-my-Touch-Monitor-on-MacOS)).
   - Plan for mouse/trackpad clicks and Shift-drag first. Treat touch as optional.
7. **Connectors.** USB-C bars need DisplayPort Alt Mode (fine on Mac Thunderbolt ports, not on USB-A). Mini-HDMI bars need an HDMI port or adapter.

---

## 5. Design notes from the geometry

- **Per-strip offsets.** The display sits behind and above the faders. Strips far to the side of where the user sits will show a small sideways parallax shift (simple geometry). A global offset plus optional per-strip ±mm trim, saved per layout, handles both parallax and measurement error.
- **Default meter anchor.** Use the **fader centre**. Offer an alternative anchor at the strip's V-Pot/soft-key column (about 3.7 mm left on the UF8).
- **Built-in templates.**
  - UF8: 8 strips, pitch 38.5 mm, first strip at 84.3 mm, unit width 431 mm.
  - UF1: 1 strip at 45.0 mm, width 205 mm.
  - UC1: width 300 mm, no strips.
  - Wing "MCU+2XT": the 24 positions above, marked as estimates.
  - Wing Compact: TBD.
  - Users chain units left to right with optional gap values.
- **DAWWAY comparison.** DAWWAY places "Fader Bank windows" per surface/extender and lists UF1, UF8 and Wing ([dawway.co.uk](https://dawway.co.uk/)). Matching the Wing needs finer-grained groups (sub-groups of 4) than DAWWAY's per-bank windows.

## Items marked UNVERIFIED

- Exact UF8 pitch on a real unit. I measured 38.5 mm from SSL's drawing; on a real unit, the distance from fader 1 centre to fader 8 centre should be about 269.6 mm.
- All Wing pitch values.
- Wing Compact DAW mapping.
- The other CONFIGURATION options besides "MCU + 2x EXTENDER".
- Whether Live and Pro Tools assign Wing ports 1/2/3 to tracks 1–8/9–16/17–24 left to right.
- A "typical" UF1 position.
- Housing widths and native orientation of specific Amazon listings.
- Whether macOS offers HiDPI automatically on 3840×1100 bars.


## Open questions
- Physical check of UF8 pitch: does the distance from fader 1 centre to fader 8 centre measure about 269.6 mm (7 x 38.5) on the user's unit, and are the user's UF8s butted together or spaced apart?
- How are the user's UF8, UF1 and UC1 arranged left to right, and where should the UF1 sit relative to the bridge (a focus/selected-track meter above it)?
- What are the Wing's real fader pitch and section gaps? Measure L1-L4, L4-L5, L12-C1 and C8-R1 to validate the ~23.5/34.5/62/186 mm estimates.
- Which CONFIGURATION options does the Wing firmware offer besides 'MCU + 2x EXTENDER' (e.g. MCU only, MCU + 1x EXTENDER), and what does the Wing Compact map in DAW mode?
- Do Ableton Live (Mackie Control + 2x ControlXT) and Pro Tools (HUI #1-#3) order the three Wing units as tracks 1-8, 9-16, 17-24 left to right, matching the physical L/C/R mapping?
- Which exact Amazon display will the user buy? Its housing width, native orientation (portrait vs landscape EDID), connector (USB-C DP Alt vs mini-HDMI) and touch controller all affect calibration and setup.
- Which Mac model does the user have? This determines how many external displays (bars) can be driven natively, or whether DisplayLink is needed.
- Will the user mount one display per surface (multiple 12.6/14-inch bars) or one long bar? Large 27-49 inch stretched bars are industrial signage, mostly not sold on Amazon, and low in pixel density.
- At what height and depth will the display sit relative to the faders? This decides whether per-strip parallax trims are needed.
- Is a 15.6-inch or 16-inch 3840x1100 bar actually sold? None were found during this research.


## Verification
- [CONFIRMED] SSL UF8 official dimensions are 431.0 W x 265.9 D x 62.7 H mm (2.9 kg unboxed); faders are 8 x 100 mm motorised; up to 4 UF8s form a 32-channel surface, ordered left-to-right in SSL 360 via Identify & Drag To Re-Order.
  - Confirmed in the UF8 User Guide Rev7. The spec text on p.8 says '431 x 266 x 62.7 mm' and 'Unboxed - 2.9 kg'. The to-scale drawing on p.9 labels 431.0 mm and 265.9 mm. The guide lists '8 x 100 mm ... touch-sensitive motorised faders' and says 'A maximum of 4 UF8s can be used to create a 32-channel control surface'. The 'Identify & Drag To Re-Order' section is on p.18. Minor caveat: the drawing's side view shows a 44.9 mm chassis height plus 18.7 mm knob height. So 62.7 mm is the overall height including knobs, and it changes when the stands are fitted. (https://eu1.download.solidstatelogic.com/UF8/SSL%20UF8%20User%20Guide_Rev7.pdf)
- [CONFIRMED] UF8 fader centre-to-centre pitch is about 38.5 mm (measured from SSL's to-scale Detailed Dimensions drawing). Fader 1 is 84.3 mm from the left edge and fader 8 is 77.1 mm from the right edge, so the 8-strip zone is about 308 mm wide (65.1 to 373.2 mm).
  - Independently reproduced by pixel analysis of the 300-ppi embedded drawing on p.9. Panel edges are at x=242 and 1743.5 px, which is 1501.5 px for 431.0 mm (3.484 px/mm); the 265.9 mm height cross-checks at 3.482 px/mm. The eight fader-cap centres are at 535.5, 669.5, 803.5, 937.5, 1072.0, 1206.0, 1340.5 and 1474.5 px, giving a pitch of 134.14 px = 38.50 mm. Fader 1 is 84.25 mm from the left edge and fader 8 is 77.2 mm from the right edge. That gives a strip zone of about 65.0 to 373.05 mm (308 mm). Caveat: this is a measurement of a drawing, not a published tolerance (about ±0.3 mm), and SSL publishes no fader-pitch figure. (https://eu1.download.solidstatelogic.com/UF8/SSL%20UF8%20User%20Guide_Rev7.pdf)
- [CONFIRMED] When UF8s are butted together, the distance from one unit's fader 8 to the next unit's fader 1 is about 161.4 mm (about 4.2 pitches), so a multi-UF8 bridge must model per-unit gaps rather than one evenly spaced 16/24-strip row.
  - The arithmetic follows from the measured drawing: 77.2 + 84.25 = 161.45 mm, which is 4.19 pitches of 38.5 mm. This assumes zero gap between chassis. Real desks will have a variable gap from stands, feet, cables or spacing, so the bridge needs a separate x-offset per unit, set by calibration, not a fixed constant. The conclusion (no uniform 16/24-strip grid) is correct. (https://eu1.download.solidstatelogic.com/UF8/SSL%20UF8%20User%20Guide_Rev7.pdf)
- [CONFIRMED] SSL UF1 is 205.0 x 265.9 x 62.5 mm (1.8 kg unit) with its single fader centred about 45.0 mm from its left edge (measured from the official drawing). The UC1 is 300 x 266 x 61 mm with no faders; all three units share the ~266 mm depth.
  - The UF1 guide spec reads 'Width 205 mm x Height 265.9 mm x Depth 62.5 mm' (SSL calls the 265.9 front-to-back size 'Height') and 'Unboxed (unit only) - 1.8 kg'. The p.9 drawing labels 205.0 and 265.9. Pixel measurement puts the panel edges at 327.5 and 1235.5 px (4.429 px/mm) and the fader slot/cap centre at 527 px, which is 45.04 mm from the left edge. The SSL UC1 product page says '300 x 266 x 61mm (Width X Depth X Height)', 2.1 kg unboxed. Important behavioural caveat: the UF1 fader is NOT part of the UF8 bank. It banks one channel at a time, follows selection ('Scroll Into View' in Pro Tools) or can switch to the DAW MASTER fader. So a bridge strip over the UF1 must follow UF1's own channel, not a UF8 bank slot. (https://solidstatelogic.com/products/uc1)
- [CONFIRMED] Behringer Wing is 870 W x 575 D x 201 H mm with 24 x 100 mm motor faders in three sections: left 12, centre 8, right 4. The Wing Compact has 12 + 1 faders and is about 453 mm wide.
  - The WING Black page gives 'Dimensions (HxWxD): 201 x 870 x 575 mm', 24 kg, '24 motorized 100 mm faders' and '12 + 8 + 4'. The original WING Quick Start Guide (2019) gives the same 201 x 870 x 575 mm and 24 kg. The WING manual says 'The 12 faders on the left section ... 8 faders in the center ... 4 faders on the right'. For the Wing Compact, the product page lists faders as '12 + 1' but its dimension field is mislabelled ('HxWxD 57.43 x 45.337 x 22.5 cm'). The Compact QSG spec gives 'H x W x D 225 x 453 x 574 mm', 15.4 kg, so 453 mm width is correct. (https://www.behringer.com/en/wing/wing-black)
- [CONFIRMED] In Wing SETUP > DAW, CONFIGURATION sets how many DAW controllers are emulated. The 'MCU + 2x EXTENDER' diagram maps unit 1 (MCU) to left faders L1-L8 plus the custom-control/transport area, unit 2 to L9-L12 + centre C1-C4, and unit 3 to centre C5-C8 + right R1-R4. DAW banks therefore straddle physical sections.
  - Manual §5.5 says CONFIGURATION 'determines the number of DAW controllers emulated by the console and shows the control surfaces on the console that correspond to each emulated controller'. I checked the Figure 43 screenshot (CONFIGURATION = 'MCU + 2x EXTENDER') against Figure 9 proportions. Box '1' covers L1-L8, box '2' covers L9-L12 + C1-C4, box '3' covers C5-C8, a second '1' covers the custom-control/jog-wheel section, and a second '3' covers R1-R4. Caveat: other CONFIGURATION values (fewer emulated units) produce different maps. Read the active configuration, or let the user pick it, rather than hard-coding one. (https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf)
- [UNCERTAIN] Wing fader pitch is estimated at about 23.3-23.8 mm within each group of 4, about 34.5 mm across group boundaries, about 62 mm from L12 to C1, and about 186 mm from C8 to R1 (measured from the manual's full-width Figure 9).
  - I reproduced the numbers from Figure 9 (1725 px wide; chassis edges at about 3 and 1719 px, i.e. 1.972 px/mm for 870 mm). Fader slots are 46-47 px apart within a group (≈23.3-23.8 mm), 68 px across group boundaries (≈34.5 mm), 122 px from L12 to C1 (≈61.9 mm) and 366 px from C8 to R1 (≈185.6 mm). However, Figure 9 is a manual illustration with no dimensions, not a dimensioned drawing. Behringer publishes no fader-pitch or offset figures, so whether it is to scale is UNVERIFIED. Treat these as defaults only and require on-device calibration or physical measurement. (https://cdn-media.empowertribe.com/25951c6f808c0a79abc407c07d5639d1/User-Manual_WING-series_2025-10-20.pdf)
- [CONFIRMED] Wing DAW setup: Pro Tools uses HUI with three 8-channel HUI devices on WING ports 1-3; Ableton uses Mackie Control on port 1 plus Mackie ControlXT on ports 2 and 3; the MCU implementation supports up to 24 faders over USB.
  - The cited mediavalet URL returned HTTP 500 to me. I verified against Music Tribe's 'WING DAW-CONTROL V1.0' PDF (2020), which is the same document. For Pro Tools: 'Select HUI in #1 and assign WING (port 1) ... set #Ch's to 8', then #2 and #3 on WING ports 2 and 3. For Ableton Live: 'Mackie Control' on WING Port 1 and 'Mackie ControlXT for second and third device' on WING Port 2 and Port 3, with Track and Remote ON. 'The MCU implementation offers support for up to 24 faders', and HUI does too. 'USB required for multiple devices'. On macOS the ports are named 'WING 1' (master), 'WING 2'/'WING 3' (extenders) and 'WING 4' (general MIDI). (https://cdn.mediavalet.com/aunsw/musictribe/8dfF-gre_U2g9m5vYrGQcg/Q5o7CAMZrUi23K0kfX_Pow/Original/WING_DAW_Documentation.pdf)
- [UNCERTAIN] A 12.6-inch 1920x515 bar has an active area of about 309.3 x 83.0 mm, which covers about 8.0 UF8 strips: the closest single-display match to one UF8's 308 mm strip zone (about 239 px per strip).
  - The cited 52Pi EP-0190 page does NOT state an active area or outline size. It gives only '12.6 Inch', 'FHD 1920x515' (and elsewhere '515x1920'), HDMI input and 10-point touch. Geometry from the diagonal (square pixels) gives 309.1 x 82.9 mm at 0.161 mm pitch: 8.03 strips at about 239 px per strip, consistent with the claim. The 309.3 x 83.0 figure is therefore UNVERIFIED as a datasheet value. The bezel and active-area offset are also unpublished, and these matter for alignment. (https://wiki-md.52pi.com/docs/EP-0190)
- [CONFIRMED] A 12.3-inch 1920x720 bar (e.g. ASUS ROG Strix XG129C) has a 292.032 x 109.512 mm viewing area, covering only about 7.6 UF8 strips (about 16 mm short of one UF8 zone). It has USB-C DP Alt Mode, HDMI and 10-point touch.
  - The ASUS spec page lists 'Display Viewing Area (H x V) : 292.032 ×109.512', pixel pitch 0.153 mm, 'USB-C x 2 (DP Alt Mode x1 + DC In x1)', 'HDMI(v1.2) x 1' and 'Projective Capacitive 10-point Touch'. 292.0 / 38.5 = 7.59 strips, about 16 mm short of 308 mm. Caveats: ASUS lists no macOS support, physical size with stand is 30.4 x 13.0 x 17.7 cm, and touch on macOS is not supported out of the box. (https://rog.asus.com/monitors/accessories/rog-strix-xg129c/spec/)
- [CONFIRMED] A 14-inch 3840x1100 bar (DFRobot DFR1125 class) has a 344.2 x 98.6 mm viewable area and a 369.5 mm outline width, covering about 8.9 UF8 strips at about 283 ppi. A single USB-C cable carries video, touch and power, with mini-HDMI as an alternative.
  - The DFRobot wiki gives viewable area '344.2(H)×98.6(V)', outline '369.5(H)×288.6(V)×5.1(D)' (the 288.6 V value looks suspicious for a bar panel; verify it physically) and pixel pitch 0.08964 (mislabelled µm; it is mm), which is about 283 ppi. Inputs are 'Type-C/mini HDMI'. Type-C CN1/CN2 carry 'Power, touch, audio/video signals'. Caveats: with HDMI input 'only Type-C CN1 supports touch'. The driver board is a separate 125 x 93 mm board. Power is PD 5-20 V, and whether a Mac USB-C port alone can power it at full brightness is UNVERIFIED. macOS compatibility is not stated. 344.2 / 38.5 = 8.94 strips, so the 8 UF8 strips use only about 3437 of 3840 px. (https://wiki.dfrobot.com/_SKU_DFR1125_14_inch_4K_Type-C_Bar_Touch_Display_Screen)
- [UNCERTAIN] 37-inch 1920x540 stretched signage bars have a 904.32 x 254.34 mm active area, wide enough to span the entire 870 mm Wing or two butted UF8s (862 mm).
  - The cited DirectIndustry/Winmate page returned HTTP 403, so the 904.32 x 254.34 mm figure is UNVERIFIED. Diagonal geometry for 37 inches at 1920:540 gives 904.7 x 254.4 mm (0.471 mm pitch, about 54 ppi), consistent with the claim. Caveats: the bezel/outline of such panels likely exceeds the 870 mm Wing width (outline UNVERIFIED). Full coverage is not needed anyway. The Wing L1-to-R4 fader span is only about 772 mm (Figure 9 estimate). Two butted UF8s need only about 65-804 mm, about 739 mm of strip zone, so narrower or cheaper panels may suffice. (https://www.directindustry.com/prod/winmate-inc/product-35784-2834715.html)
- [REFUTED] Native external-display limits on Apple Silicon: 1 for base M1/M2, 2 for base M3 (lid closed only), 2 for base M4/M5 and Pro chips, 3-4 for Max chips. A Thunderbolt dock does not raise the limit; DisplayLink is the workaround.
  - These are MacBook limits presented as chip limits. Desktops differ. Apple's Mac mini (2023) specs: M2 'supports up to two displays' and M2 Pro up to three. The current Mac mini (M6 / M5 Pro) supports up to three external displays, including 'up to two external displays over a single Thunderbolt port' (M6) or three (M5 Pro). The Plugable source itself lists M5 Pro at three displays and M5 Max at four, not two. Base M3 MacBooks: Apple specs say 'One external display ... Close the MacBook Pro lid to use a second external display', i.e. 1 with the lid open and 2 with it closed. Correct parts: a dock does not raise the native limit, and DisplayLink (screen-capture based, needs a driver) is the usual workaround. Check the specific Mac model rather than the chip family. (https://support.apple.com/en-us/111837)
- [UNCERTAIN] Many small bar panels are natively portrait (e.g. 8.8-inch shows as 480x1920; 52Pi describes its 12.6-inch as 515x1920) and need OS rotation. 52Pi warns some macOS systems have compatibility issues and not all docks pass the mode, so connect directly.
  - The 52Pi warnings are confirmed verbatim: 'Some macOS systems may experience compatibility issues' and 'connect the HDMI cable directly to the native HDMI port ... not all docking stations support the 515x1920 resolution output'. But 52Pi describes the panel both ways ('FHD 1920x515' in specs, '515x1920' in the description, display mode 'Landscape and Portrait'). It does not explicitly say the native timing is portrait or that OS rotation is required. The 8.8-inch 480x1920 example was not verified (Waveshare pages returned 404). The 52Pi unit is HDMI-only for video (touch over USB), so a Mac needs an HDMI port or a USB-C-to-HDMI adapter. (https://wiki-md.52pi.com/docs/EP-0190)
- [UNCERTAIN] macOS has no native touchscreen support; USB touch bars need a third-party driver (UPDD) with per-display touch mapping, so click/Shift-drag via mouse should be the primary interaction.
  - The cited ctouch article returned 404. Touch-Base confirms UPDD V7 is a universal (Intel/ARM) macOS driver supporting 'full multi-touch gestures', but its pages I could reach do not state that macOS lacks native touch, nor document per-display mapping on macOS. Apple ships no touchscreen support for macOS, so the claim is very likely true. Whether generic HID touch digitizers act as a single-point absolute mouse on macOS without UPDD (and on which display) is UNVERIFIED. The design conclusion (mouse/trackpad + Shift for fine drag as primary, touch optional) is sound. (https://www.touch-base.com/drivers.html)

### Missed points
- Research limitation: the shared WebSearch budget for this run was used up, so verification relied on WebFetch of primary pages and on PDFs (UF8/UF1 guides, WING manual, WING DAW-CONTROL V1.0, WING/WING Compact QSGs). Several cited URLs (WING_DAW_Documentation mediavalet URL: HTTP 500; DirectIndustry: 403; ctouch: 404) could not be fetched.
- UF1 is an independent single-channel controller. Its fader banks one channel at a time, follows selection (Pro Tools 'Scroll Into View') or switches to the DAW MASTER fader ('UF1 can switch to control the MASTER fader in MCU protocol DAWs'). The bridge must model the UF1 strip as following UF1's own channel, not as UF8 bank slot 9. UF1 also uses 'HUI+PTSL' for Pro Tools (UF1 User Guide Rev9.1).
- UC1 has no faders but occupies 300 mm of the desk row. A bridge spanning UF8 + UC1 + UF1 needs blank or utility regions in the layout model, not just strip slots.
- Each UF8 is a separate HUI/MCU device on its own SSL V-MIDI port (Pro Tools: 'Configure each UF8 unit as a HUI Type ... incrementing the port number'). The SSL 360 drag-order maps to DAW channel blocks of 8 per unit, so the layout model should be per-unit [unit index -> x-offset -> 8 strips].
- WING on macOS exposes ports 'WING 1' (MCU/HUI master), 'WING 2'/'WING 3' (extenders) and 'WING 4' (general MIDI). 'USB required for multiple devices'; DIN gives only one emulated unit. Each WING section's layer buttons in DAW mode 'navigate faders in banks of 8' and '<4 / 4>' by single channel (WING DAW-CONTROL V1.0).
- WING DAW mode has a large non-fader gap: the custom-control/jog section between C8 and R1 (≈186 mm, Figure 9 estimate). It belongs to emulated unit 1, so DAW channel 17-24 strips are split 4 + gap + 4 physically. The layout model needs arbitrary per-strip x positions, not per-unit uniform pitch.
- Datasheets rarely give the bar display's active-area offset within its bezel, and EDID-reported physical size (CGDisplayScreenSize) on cheap bar panels is often inaccurate (UNVERIFIED per model). Plan an on-screen calibration step (drag first/last strip edges over physical faders, or enter the measured mm) and convert mm -> points via NSScreen frame / backingScaleFactor.
- macOS behaviour on a short bar display (general macOS knowledge, not verified against Apple docs in this pass): with 'Displays have separate Spaces' on, each display gets a menu bar (~24-37 pt), which eats a 515-1100 px-tall bar. The Dock can also land there. Use a borderless window at a level above the menu bar or offer an 'auto-hide menu bar' recommendation. A 3840x1100 panel may default to a HiDPI 'looks like 1920x550' mode.
- Current Mac mini (M6 / M5 Pro) supports up to three external displays, two or three over a single Thunderbolt port (apple.com/mac-mini/specs). That relaxes the multi-bar constraint for desktop users compared with MacBooks.
- DFR1125 practical caveats: separate 125 x 93 mm driver board to mount. Touch works only via CN1 when using HDMI. PD 5-20 V power may exceed what a Mac USB-C port supplies (UNVERIFIED). No macOS compatibility statement.
- UF8 height of 62.7 mm includes knobs (drawing: 44.9 mm chassis + 18.7 mm knob), and the six stand angles raise the rear edge. The bar display's mounting height and tilt relative to the UF8's built-in TFT row will vary, so vertical alignment and tilt are user settings, not constants.
