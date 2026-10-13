"""The calibration tone schedule and the capture analysis that fits it."""

import math
import os
import sys
import unittest

_TOOLS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools")
if _TOOLS not in sys.path:
    sys.path.insert(0, _TOOLS)

import capture_meters  # noqa: E402
import make_calibration_tone as tone  # noqa: E402


def synthetic_frames(onset, meter_for_db, rate=60.0, lag=0.15):
    """Meter frames for the whole tone: silence, then each step after a short rise."""
    frames = []
    t = onset - 1.0
    end = onset + tone.total_seconds() - tone.LEAD_SECONDS
    while t < end:
        position = t - onset
        value = 0.0
        for start, stop, level in tone.schedule():
            if start <= position < stop:
                settle = min(1.0, (position - start) / lag)
                value = meter_for_db(level) * settle
        frames.append((t, value, value * 0.999))
        t += 1.0 / rate
    return frames


class ToneScheduleTests(unittest.TestCase):
    def test_steps_are_loudest_first_and_evenly_spaced(self):
        steps = tone.schedule()
        self.assertEqual([s[2] for s in steps], tone.LEVELS_DB)
        self.assertEqual(steps[0][0], 0.0)
        for (start, end, _), (next_start, _, _) in zip(steps, steps[1:]):
            self.assertAlmostEqual(end - start, tone.TONE_SECONDS)
            self.assertAlmostEqual(next_start - end, tone.GAP_SECONDS)

    def test_sample_peaks_follow_the_levels(self):
        start, end, level = tone.schedule()[5]
        t0 = tone.LEAD_SECONDS + start + 0.5
        peak = max(abs(tone.sample_at(t0 + i / 48000.0)) for i in range(4800))
        self.assertAlmostEqual(20 * math.log10(peak), level, places=2)

    def test_lead_and_gaps_are_silent(self):
        self.assertEqual(tone.sample_at(0.5), 0.0)
        start, end, _ = tone.schedule()[0]
        self.assertEqual(tone.sample_at(tone.LEAD_SECONDS + end + tone.GAP_SECONDS / 2), 0.0)


class AnalysisTests(unittest.TestCase):
    def test_recovers_each_step_from_meter_frames(self):
        def meter(db):
            return math.pow(10.0, db / 20.0) ** 0.5

        steps = capture_meters.analyse(synthetic_frames(100.0, meter))
        self.assertEqual(len(steps), len(tone.LEVELS_DB))
        for step in steps:
            self.assertAlmostEqual(step["value"], meter(step["decibels"]), delta=0.002)
            self.assertLess(step["spread"], 0.01)
            self.assertGreater(step["readings"], 30)

    def test_rejects_a_capture_without_the_tone(self):
        with self.assertRaises(ValueError):
            capture_meters.analyse([(0.0, 0.0, 0.0), (1.0, 0.01, 0.01)])


if __name__ == "__main__":
    unittest.main()
