# Live meter calibration (measured)

**Result (Live 12.4.6, measured 2026-10-13):** the track meter value that the Live Object Model reports (`Track.output_meter_left` / `output_meter_right`, 0..1) is **linear in dB**, from −70 dBFS to +6 dBFS:

```
value = (dBFS + 70) / 76          dBFS = 76 · value − 70
```

| Point | Value |
|---|---|
| −70 dBFS and below (meter floor) | 0 |
| 0 dBFS | 0.92105 (the script rounds it to 0.9211) |
| +6 dBFS (top of scale) | 1 |

This replaces the earlier guesses recorded in [02-ableton-live.md](02-ableton-live.md) §1.4: 20·log10, the LiveControl formula, and "same curve as the volume fader". None of them was right.

## Method

1. **Test tone.** `AbletonRemoteScript/tools/make_calibration_tone.py` writes a 48 kHz, 24-bit stereo WAV: a 997 Hz sine, identical on both channels, held for 2.5 s at each of 19 peak levels (0, −1, −2, −3, −4.5, −6, −9, … −60, −70 dBFS) with 0.5 s silences between. A sample-peak check of the file reads each step within 0.001 dB.
2. **Setup.** One audio track named `CAL` in Live 12.4.6 (48 kHz project). Fader 0.0 dB, pan centre, no devices, Warp off, not armed.
3. **Capture.** `AbletonRemoteScript/tools/capture_meters.py` stood in for the app. It subscribed to the MeterBridge script at 60 Hz, watched the `CAL` track, and took the median meter value over each step after a 1 s settle. It recorded 3,936 frames, about 65 per step.

## Measured values

| dBFS | Meter (L = R) | (dB + 70) / 76 |
|---:|---:|---:|
| 0.0 | 0.9211 | 0.92105 |
| −1.0 | 0.9079 | 0.90789 |
| −2.0 | 0.8947 | 0.89474 |
| −3.0 | 0.8816 | 0.88158 |
| −4.5 | 0.8618 | 0.86184 |
| −6.0 | 0.8421 | 0.84211 |
| −9.0 | 0.8026 | 0.80263 |
| −12.0 | 0.7632 | 0.76316 |
| −15.0 | 0.7237 | 0.72368 |
| −18.0 | 0.6842 | 0.68421 |
| −21.0 | 0.6447 | 0.64474 |
| −24.0 | 0.6053 | 0.60526 |
| −30.0 | 0.5263 | 0.52632 |
| −36.0 | 0.4474 | 0.44737 |
| −42.0 | 0.3684 | 0.36842 |
| −48.0 | 0.2895 | 0.28947 |
| −54.0 | 0.2105 | 0.21053 |
| −60.0 | 0.1316 | 0.13158 |
| −70.0 | 0.0000 | 0.00000 |

- **Exact match.** Every step matches the formula to the 4th decimal, which is the script's rounding.
- **No ripple.** The spread within each step was 0, so for a steady tone Live's "smoothed momentary peak" settles exactly on the peak level.
- **Stereo.** Left and right were identical.

## How the app uses it

- **Built-in table.** `MeterCalibration.ableton12` encodes the result as a two-point table (0 → −70 dB, 1 → +6 dB), flagged as measured. Readouts therefore show plain numbers, without "≈".
- **Clip LED.** It latches at `clipValue = 0.9212`. A full-scale sine arrives as 0.9211, so the LED lights only **above** 0 dBFS.
- **Selection.**
  - The app picks the table when the script's `hello` reports a Live 12 version.
  - A table saved in the settings (`liveMeterCalibration`) still takes priority.
  - Live 11 and versions newer than 12 stay uncalibrated until measured.
- **Simulator.** It emits values on the same scale, so the demo looks and reads like Live.

## Caveats and re-running

- **Fast transients.** This was measured with a steady tone. Live smooths its meter, so short transient overs may read lower than their true sample peak, and the clip LED can miss a single-sample over that Live's own clip indicator catches.
- **Live 11 is unmeasured.** Live 12 reworked meter ballistics. To measure it:
  1. Run `python3 AbletonRemoteScript/tools/make_calibration_tone.py --out tone.wav` (pass `--rate` to match the project).
  2. Quit DAW Meter Bridge.
  3. Run `python3 AbletonRemoteScript/tools/capture_meters.py --track CAL`, and play the tone on a track named `CAL` set up as above.
  4. If the result differs from Live 12, add a table for that version next to `MeterCalibration.ableton12`.
