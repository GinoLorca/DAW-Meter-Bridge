"""Track snapshots, ordering and diffs."""

import os
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_live
from MeterBridge import lom
from MeterBridge.tracks import RECORD_KEYS, TrackStateTracker, snapshot_record
from MeterBridge.volume_curve import approximate_curve, parse_db, sample_curve, sample_song_curve


class OrderingTests(unittest.TestCase):
    def test_order_is_visible_then_returns_then_main(self):
        song = fake_live.FakeSong(track_count=5, return_count=2)
        kinds = [(track.name, kind) for track, kind in lom.ordered_tracks(song)]
        self.assertEqual(
            kinds,
            [
                ("Kick", "audio"),
                ("Snare", "audio"),
                ("Hats", "audio"),
                ("Bass", "audio"),
                ("Keys", "midi"),
                ("A-Reverb", "return"),
                ("B-Delay", "return"),
                ("Main", "main"),
            ],
        )

    def test_folded_group_children_are_left_out(self):
        song = fake_live.FakeSong(track_count=5, group=True)
        names = [track.name for track, _kind in lom.ordered_tracks(song)]
        self.assertEqual(names[:5], ["Drums", "Kick", "Snare", "Hats", "Bass"])
        song.set_folded(True)
        names = [track.name for track, _kind in lom.ordered_tracks(song)]
        self.assertEqual(names[:3], ["Drums", "Bass", "Keys"])
        self.assertEqual(lom.visible_kind(song.group), "group")

    def test_track_id_prefers_live_ptr(self):
        song = fake_live.FakeSong(track_count=1)
        track = song.tracks[0]
        self.assertEqual(lom.track_id(track), track._live_ptr)

        class NoPointer(object):
            pass

        other = NoPointer()
        self.assertEqual(lom.track_id(other), id(other))


class RecordTests(unittest.TestCase):
    def setUp(self):
        self.song = fake_live.FakeSong(track_count=16, group=True)
        self.tracker = TrackStateTracker()
        self.tracker.read(self.song)

    def record(self, name):
        return self.tracker.records[self.song.find(name)._live_ptr]

    def test_record_has_protocol_keys_in_order(self):
        for record in self.tracker.full_list():
            self.assertEqual(tuple(record.keys()), RECORD_KEYS)

    def test_indices_follow_list_order(self):
        self.assertEqual([r["i"] for r in self.tracker.full_list()], list(range(len(self.tracker.order))))
        self.assertEqual(self.tracker.full_list()[-1]["k"], "main")

    def test_audio_track_record(self):
        kick = self.song.find("Kick")
        kick.mixer_device.volume.value = 0.5
        kick.mute = True
        self.tracker.read(self.song)
        record = self.record("Kick")
        self.assertEqual(record["id"], kick._live_ptr)
        self.assertEqual(record["n"], "Kick")
        self.assertEqual(record["c"], 0xFF94A6)
        self.assertEqual(record["k"], "audio")
        self.assertIs(record["m"], True)
        self.assertIs(record["a"], False)
        self.assertIs(record["ao"], True)
        self.assertEqual(record["vol"], 0.5)
        self.assertEqual(record["vs"], "-14.0 dB")

    def test_volume_is_rounded_from_float32(self):
        self.song.find("Kick").mixer_device.volume.value = 0.8123
        self.tracker.read(self.song)
        self.assertEqual(self.record("Kick")["vol"], 0.8123)

    def test_main_return_group_and_midi_specifics(self):
        main = self.record("Main")
        self.assertEqual((main["k"], main["m"], main["s"], main["a"], main["ms"]), ("main", False, False, None, False))
        reverb = self.record("A-Reverb")
        self.assertEqual((reverb["k"], reverb["a"]), ("return", None))
        group = self.record("Drums")
        self.assertEqual((group["k"], group["a"]), ("group", None))
        keys = self.record("Keys")
        self.assertEqual((keys["k"], keys["a"], keys["ao"]), ("midi", False, True))
        triggers = self.record("Clip Triggers")
        self.assertEqual((triggers["k"], triggers["ao"]), ("midi", False))

    def test_muted_via_solo(self):
        self.song.find("Bass").solo = True
        self.tracker.read(self.song)
        self.assertIs(self.record("Bass")["s"], True)
        self.assertIs(self.record("Bass")["ms"], False)
        self.assertIs(self.record("Kick")["ms"], True)
        self.assertIs(self.record("A-Reverb")["ms"], False)

    def test_selection_inside_folded_group_is_none(self):
        snare = self.song.find("Snare")
        self.song.view.selected_track = snare
        self.tracker.read(self.song)
        self.assertEqual(self.tracker.selected_id, snare._live_ptr)
        self.song.set_folded(True)
        self.tracker.read(self.song)
        self.assertIsNone(self.tracker.selected_id)

    def test_unreadable_properties_fall_back(self):
        class Broken(object):
            _live_ptr = 99

            @property
            def name(self):
                raise RuntimeError("gone")

        record = snapshot_record(Broken(), "audio", 0, 99)
        self.assertEqual(record["n"], "")
        self.assertIsNone(record["c"])
        self.assertEqual(record["vol"], 0.0)
        self.assertEqual(record["vs"], "")


class DiffTests(unittest.TestCase):
    def setUp(self):
        self.song = fake_live.FakeSong(track_count=8, group=True)
        self.tracker = TrackStateTracker()

    def poll(self):
        self.tracker.read(self.song)
        return self.tracker.diff()

    def test_first_diff_is_full_with_selection(self):
        full, changed, selection = self.poll()
        self.assertTrue(full)
        self.assertEqual(changed, [])
        self.assertTrue(selection)

    def test_no_change_is_quiet(self):
        self.poll()
        self.assertEqual(self.poll(), (False, [], False))

    def test_property_change_reports_one_record(self):
        self.poll()
        self.song.find("Keys").arm = True
        full, changed, selection = self.poll()
        self.assertFalse(full)
        self.assertEqual([r["n"] for r in changed], ["Keys"])
        self.assertIs(changed[0]["a"], True)
        self.assertFalse(selection)

    def test_folding_needs_a_full_list(self):
        self.poll()
        self.song.set_folded(True)
        full, _changed, _selection = self.poll()
        self.assertTrue(full)

    def test_rename_is_a_record_change_reorder_is_full(self):
        self.poll()
        self.song.find("Bass").name = "Sub Bass"
        self.assertEqual([r["n"] for r in self.poll()[1]], ["Sub Bass"])
        self.song.tracks.reverse()
        self.assertTrue(self.poll()[0])

    def test_selection_change(self):
        self.poll()
        self.song.view.selected_track = self.song.master_track
        _full, _changed, selection = self.poll()
        self.assertTrue(selection)
        self.assertEqual(self.tracker.selected_id, self.song.master_track._live_ptr)

    def test_reset_forces_full(self):
        self.poll()
        self.tracker.reset()
        full, _changed, selection = self.poll()
        self.assertTrue(full)
        self.assertTrue(selection)

    def test_refresh_one_track(self):
        self.poll()
        bass = self.song.find("Bass")
        bass.mixer_device.volume.value = 0.3
        record = self.tracker.refresh(bass._live_ptr)
        self.assertEqual(record["vol"], 0.3)
        self.assertIsNone(self.tracker.refresh(bass._live_ptr))
        self.assertEqual(self.poll(), (False, [], False))

    def test_volume_text_is_cached_until_the_value_changes(self):
        calls = []
        parameter = self.song.find("Kick").mixer_device.volume
        original = type(parameter).__str__

        def counting_str(param):
            calls.append(param)
            return original(param)

        type(parameter).__str__ = counting_str
        try:
            self.poll()
            before = len(calls)
            self.poll()
            self.assertEqual(len(calls), before)
            parameter.value = 0.2
            self.poll()
            self.assertEqual(len(calls), before + 1)
        finally:
            type(parameter).__str__ = original


class VolumeCurveTests(unittest.TestCase):
    def test_parse_db(self):
        self.assertEqual(parse_db("-6.0 dB"), -6.0)
        self.assertEqual(parse_db("6.0 dB"), 6.0)
        self.assertEqual(parse_db("+6.0 dB"), 6.0)
        self.assertEqual(parse_db("0.0 dB"), 0.0)
        self.assertEqual(parse_db("−12.5 dB"), -12.5)
        self.assertIsNone(parse_db("-inf dB"))
        self.assertIsNone(parse_db("garbage"))
        self.assertIsNone(parse_db(None))

    def test_samples_101_points_from_the_main_volume(self):
        song = fake_live.FakeSong(track_count=2)
        curve, problem = sample_song_curve(song)
        self.assertIsNone(problem)
        self.assertEqual(len(curve["x"]), 101)
        self.assertEqual(len(curve["db"]), 101)
        self.assertEqual(curve["x"][0], 0.0)
        self.assertEqual(curve["x"][85], 0.85)
        self.assertEqual(curve["x"][100], 1.0)
        self.assertIsNone(curve["db"][0])
        self.assertEqual(curve["db"][85], 0.0)
        self.assertEqual(curve["db"][100], 6.0)

    def test_unparseable_curve_falls_back(self):
        class Silly(object):
            def str_for_value(self, value):
                return "loud"

        curve, problem = sample_curve(Silly())
        self.assertIsNotNone(problem)
        self.assertEqual(curve, approximate_curve())
        curve, problem = sample_curve(None)
        self.assertIsNotNone(problem)
        self.assertEqual(len(curve["db"]), 101)


if __name__ == "__main__":
    unittest.main()
