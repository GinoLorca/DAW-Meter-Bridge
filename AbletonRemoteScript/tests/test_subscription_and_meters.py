"""Subscription keep-alive and timeout; meter selection, rounding and drop-out frames."""

import os
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_live
from MeterBridge.meters import MeterFrameBuilder, read_levels, round_level, select_ids
from MeterBridge.subscription import Subscription


class SubscriptionTests(unittest.TestCase):
    def test_first_sub_is_new_and_keepalive_is_not(self):
        sub = Subscription()
        self.assertTrue(sub.on_sub({"port": 47800, "hz": 30}, 10.0))
        self.assertTrue(sub.active)
        self.assertFalse(sub.on_sub({"port": 47800, "hz": 30}, 11.0))
        self.assertFalse(sub.on_sub({"port": 47800, "hz": 30}, 15.9))

    def test_new_port_is_a_new_subscription(self):
        sub = Subscription()
        sub.on_sub({"port": 47800}, 10.0)
        sub.on_watch({"ids": [1, 2]})
        self.assertTrue(sub.on_sub({"port": 47900}, 10.5))
        self.assertEqual(sub.reply_port, 47900)
        self.assertEqual(sub.watch, [])

    def test_new_app_value_is_a_new_subscription(self):
        sub = Subscription()
        self.assertTrue(sub.on_sub({"port": 47800, "app": 7}, 10.0))
        sub.on_watch({"ids": [1, 2]})
        self.assertFalse(sub.on_sub({"port": 47800, "app": 7}, 11.0))
        self.assertEqual(sub.watch, [1, 2])
        # The app restarted its source within 5 s: same port, new app value.
        self.assertTrue(sub.on_sub({"port": 47800, "app": 8}, 12.0))
        self.assertEqual(sub.app, 8)
        self.assertEqual(sub.watch, [])
        self.assertFalse(sub.on_sub({"port": 47800, "app": 8}, 13.0))

    def test_absent_or_invalid_app_never_starts_a_subscription_or_clears_the_value(self):
        sub = Subscription()
        sub.on_sub({"port": 47800, "app": 7}, 10.0)
        for app in (None, "8", 8.0, True, [8]):
            with self.subTest(app=app):
                message = {"port": 47800}
                if app is not None:
                    message["app"] = app
                self.assertFalse(sub.on_sub(message, 11.0))
                self.assertEqual(sub.app, 7)
        # A first app value after subs without one starts over too (an app that just learned to send it).
        sub = Subscription()
        sub.on_sub({"port": 47800}, 10.0)
        sub.on_watch({"ids": [3]})
        self.assertTrue(sub.on_sub({"port": 47800, "app": 9}, 11.0))
        self.assertEqual(sub.watch, [3])

    def test_huge_hz_is_the_default_and_never_raises(self):
        sub = Subscription()
        self.assertTrue(sub.on_sub({"port": 47800, "hz": 10 ** 400}, 1.0))
        self.assertEqual((sub.port, sub.hz, sub.active), (47800, 30, True))

    def test_timeout_after_five_seconds(self):
        sub = Subscription()
        sub.on_sub({"port": 47800}, 10.0)
        sub.on_watch({"ids": [7]})
        self.assertFalse(sub.expire(14.99))
        self.assertTrue(sub.active)
        self.assertTrue(sub.expire(15.0))
        self.assertFalse(sub.active)
        self.assertEqual(sub.watch, [])
        self.assertFalse(sub.expire(16.0))
        self.assertTrue(sub.on_sub({"port": 47800}, 16.0))

    def test_sub_after_a_long_gap_is_new_even_before_expire_runs(self):
        sub = Subscription()
        sub.on_sub({"port": 47800}, 10.0)
        self.assertTrue(sub.on_sub({"port": 47800}, 15.0))

    def test_defaults_and_hz(self):
        sub = Subscription()
        self.assertEqual(sub.reply_port, 47800)
        sub.on_sub({}, 1.0)
        self.assertEqual((sub.port, sub.hz), (47800, 30))
        sub.on_sub({"port": 47800, "hz": 90}, 1.5)
        self.assertEqual(sub.hz, 60)

    def test_watch_parsing(self):
        sub = Subscription()
        sub.on_watch({"ids": [3, 3, "4", True, 5, None, 6.0]})
        self.assertEqual(sub.watch, [3, 5])
        sub.on_watch({"ids": "nope"})
        self.assertEqual(sub.watch, [3, 5])
        sub.on_watch({"ids": []})
        self.assertEqual(sub.watch, [])


class MeterTests(unittest.TestCase):
    def test_rounding_and_clamping(self):
        self.assertEqual(round_level(0.61234567), 0.6123)
        self.assertEqual(round_level(0.99996), 1.0)
        self.assertEqual(round_level(1.7), 1.0)
        self.assertEqual(round_level(-0.2), 0.0)
        self.assertEqual(round_level(float("nan")), 0.0)
        self.assertEqual(round_level(None), 0.0)

    def test_select_ids_priority_dedupe_and_unknowns(self):
        known = set(range(1, 100))
        chosen = select_ids([1, 2, None, 3, 2], 50, 99, [3, 60, 1000, 61], known)
        self.assertEqual(chosen, [1, 2, 3, 50, 99, 60, 61])
        self.assertEqual(select_ids([], None, None, [], known), [])

    def test_select_ids_caps_at_64(self):
        known = set(range(1000))
        chosen = select_ids(list(range(1, 33)), 500, 999, list(range(100, 200)), known)
        self.assertEqual(len(chosen), 64)
        self.assertEqual(chosen[:34], list(range(1, 33)) + [500, 999])

    def test_levels_use_left_right_or_level(self):
        song = fake_live.FakeSong(track_count=16)
        song.now = 12.3
        kick = song.find("Kick")
        left, right = read_levels(kick, True)
        self.assertEqual((left, right), (round(kick.output_meter_left, 4), round(kick.output_meter_right, 4)))
        triggers = song.find("Clip Triggers")
        self.assertFalse(triggers.has_audio_output)
        level = round(triggers.output_meter_level, 4)
        self.assertEqual(read_levels(triggers, False), (level, level))
        # A stale has_audio_output still works: left/right raise, the level is used.
        self.assertEqual(read_levels(triggers, True), (level, level))

    def test_drop_out_gets_one_zero_frame(self):
        song = fake_live.FakeSong(track_count=4)
        song.now = 3.0
        tracks = {t._live_ptr: t for t in song.tracks}
        a, b, c, _d = list(tracks)

        def lookup(tid):
            return tracks.get(tid), True

        builder = MeterFrameBuilder()
        self.assertEqual([e[0] for e in builder.build([a, b, c], lookup)], [a, b, c])
        frame = builder.build([a, c], lookup)
        self.assertEqual([e[0] for e in frame], [a, c, b])
        self.assertEqual(frame[2], [b, 0.0, 0.0])
        self.assertEqual([e[0] for e in builder.build([a, c], lookup)], [a, c])

    def test_vanished_track_is_zero(self):
        builder = MeterFrameBuilder()
        self.assertEqual(builder.build([5], lambda tid: (None, True)), [[5, 0.0, 0.0]])

    def test_frame_never_exceeds_64_entries(self):
        song = fake_live.FakeSong(track_count=80)
        tracks = {t._live_ptr: t for t in song.tracks}
        ids = list(tracks)

        def lookup(tid):
            return tracks.get(tid), True

        builder = MeterFrameBuilder()
        self.assertEqual(len(builder.build(ids[:64], lookup)), 64)
        frame = builder.build(ids[10:74], lookup)
        self.assertEqual(len(frame), 64)
        self.assertEqual([e[0] for e in frame], ids[10:74])


if __name__ == "__main__":
    unittest.main()
