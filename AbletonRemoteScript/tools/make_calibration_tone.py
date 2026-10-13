"""Writes the meter-calibration test tone.

A stereo 997 Hz sine (identical channels) at known peak levels, one level per step,
with short silences between steps. Play it on an audio track with the fader at 0 dB,
pan centred, no devices and Warp off, while tools/capture_meters.py records what
Live's track meter reports. The schedule here is what capture_meters.py analyses.

    python3 tools/make_calibration_tone.py --out "MeterBridge Calibration Tone.wav"
"""

import argparse
import math
import struct
import wave

#: Peak level of each step, in dBFS, loudest first.
LEVELS_DB = [0.0, -1.0, -2.0, -3.0, -4.5, -6.0, -9.0, -12.0, -15.0, -18.0, -21.0, -24.0,
             -30.0, -36.0, -42.0, -48.0, -54.0, -60.0, -70.0]
#: Silence before the first step, so the capture can find where the tone starts.
LEAD_SECONDS = 2.0
TONE_SECONDS = 2.5
GAP_SECONDS = 0.5
TAIL_SECONDS = 1.0
FREQUENCY = 997.0
#: Raised-cosine fade at each step's edges, so steps don't click.
FADE_SECONDS = 0.005
FULL_SCALE_24 = (1 << 23) - 1


def schedule():
    """(start, end, dBFS) of each step in seconds, relative to the first step's start."""
    steps = []
    start = 0.0
    for level in LEVELS_DB:
        steps.append((start, start + TONE_SECONDS, level))
        start += TONE_SECONDS + GAP_SECONDS
    return steps


def total_seconds():
    return LEAD_SECONDS + len(LEVELS_DB) * (TONE_SECONDS + GAP_SECONDS) + TAIL_SECONDS


def sample_at(t):
    """Signal value (-1...1) at `t` seconds from the start of the file."""
    position = t - LEAD_SECONDS
    for start, end, level in schedule():
        if start <= position < end:
            gain = math.pow(10.0, level / 20.0)
            edge = min(position - start, end - position)
            if edge < FADE_SECONDS:
                gain *= 0.5 - 0.5 * math.cos(math.pi * edge / FADE_SECONDS)
            return gain * math.sin(2.0 * math.pi * FREQUENCY * position)
    return 0.0


def write(path, rate=48000):
    frames = int(round(total_seconds() * rate))
    with wave.open(path, "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(3)
        out.setframerate(rate)
        chunk = bytearray()
        for index in range(frames):
            value = int(round(sample_at(index / float(rate)) * FULL_SCALE_24))
            value = max(-FULL_SCALE_24, min(FULL_SCALE_24, value))
            sample = struct.pack("<i", value)[:3]
            chunk += sample
            chunk += sample
            if len(chunk) >= 1 << 20:
                out.writeframes(bytes(chunk))
                chunk = bytearray()
        out.writeframes(bytes(chunk))
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", default="MeterBridge Calibration Tone.wav", help="output WAV path")
    parser.add_argument("--rate", type=int, default=48000, help="sample rate; match Live's (default 48000)")
    args = parser.parse_args()
    frames = write(args.out, args.rate)
    print("wrote %s: %.1f s, %d Hz, 24-bit stereo, %d steps from %+.1f to %+.1f dBFS"
          % (args.out, frames / float(args.rate), args.rate, len(LEVELS_DB), LEVELS_DB[0], LEVELS_DB[-1]))


if __name__ == "__main__":
    main()
