"""Command parsing and application: solo/arm exclusivity, guards, clamping, refusal retries, drag gestures."""

import os
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_live
from MeterBridge.commands import (
    APPLIED,
    ERROR,
    IGNORED,
    RETRY,
    Command,
    CommandQueue,
    VolumeGestures,
    is_refusal,
    parse_command,
)
from MeterBridge.tracks import TrackStateTracker


class ParseTests(unittest.TestCase):
    def test_valid_commands(self):
        command, problem = parse_command({"op": "solo", "id": 5, "on": True, "excl": None})
        self.assertIsNone(problem)
        self.assertEqual((command.op, command.track_id, command.on, command.exclusive), ("solo", 5, True, None))
        command, _ = parse_command({"op": "solo", "id": 5, "on": False})
        self.assertIsNone(command.exclusive)
        command, _ = parse_command({"op": "vol", "id": 5, "val": 1})
        self.assertEqual(command.value, 1.0)
        command, _ = parse_command({"op": "select", "id": 5})
        self.assertEqual(command.op, "select")
        command, _ = parse_command({"op": "arm", "id": 5, "on": True, "excl": False})
        self.assertEqual((command.op, command.on, command.exclusive), ("arm", True, False))
        command, _ = parse_command({"op": "arm", "id": 5, "on": True})
        self.assertIsNone(command.exclusive)

    def test_vol_end_flag(self):
        for fields, end in (({}, False), ({"end": False}, False), ({"end": None}, False), ({"end": True}, True)):
            with self.subTest(fields=fields):
                message = {"op": "vol", "id": 5, "val": 0.5}
                message.update(fields)
                command, problem = parse_command(message)
                self.assertIsNone(problem)
                self.assertIs(command.end, end)

    def test_invalid_commands(self):
        bad = [
            {"op": "pan", "id": 5},
            {"op": "mute", "id": "5", "on": True},
            {"op": "mute", "id": True, "on": True},
            {"op": "mute", "id": 5},
            {"op": "mute", "id": 5, "on": 1},
            {"op": "solo", "id": 5, "on": True, "excl": "yes"},
            {"op": "vol", "id": 5},
            {"op": "vol", "id": 5, "val": "0.5"},
            {"op": "vol", "id": 5, "val": float("inf")},
            {"op": "vol", "id": 5, "val": 10 ** 400},
            {"op": "vol", "id": 5, "val": 0.5, "end": 1},
            {"op": "vol", "id": 5, "val": 0.5, "end": "yes"},
            {"op": "arm", "id": 5, "on": True, "excl": 0},
            {"id": 5},
        ]
        for message in bad:
            with self.subTest(message=message):
                command, problem = parse_command(message)
                self.assertIsNone(command)
                self.assertTrue(problem)

    def test_refusal_detection(self):
        self.assertTrue(is_refusal(RuntimeError(fake_live.UNDO_REFUSAL)))
        self.assertTrue(is_refusal(RuntimeError(fake_live.NOTIFICATION_REFUSAL)))
        self.assertFalse(is_refusal(RuntimeError("Invalid value")))


class ApplyTests(unittest.TestCase):
    def setUp(self):
        self.song = fake_live.FakeSong(track_count=8, return_count=2)
        self.tracker = TrackStateTracker()
        self.tracker.read(self.song)
        self.queue = CommandQueue()

    def run_one(self, op, name, **fields):
        message = {"op": op, "id": self.song.find(name)._live_ptr}
        message.update(fields)
        command, problem = parse_command(message)
        self.assertIsNone(problem)
        self.queue.enqueue(command)
        results = self.queue.apply(self.song, self.tracker.resolve)
        self.assertEqual(len(results), 1)
        return results[0]

    def soloed(self):
        return [t.name for t in self.song.tracks + self.song.return_tracks if t._solo]

    def test_mute_and_select(self):
        self.assertEqual(self.run_one("mute", "Snare", on=True).status, APPLIED)
        self.assertTrue(self.song.find("Snare")._mute)
        self.assertEqual(self.run_one("select", "B-Delay").status, APPLIED)
        self.assertIs(self.song.view.selected_track, self.song.find("B-Delay"))

    def test_exclusive_solo_true_clears_tracks_and_returns(self):
        self.song.find("Kick").solo = True
        self.song.find("A-Reverb").solo = True
        self.run_one("solo", "Bass", on=True, excl=True)
        self.assertEqual(self.soloed(), ["Bass"])

    def test_additive_solo_false_keeps_others(self):
        self.song.find("Kick").solo = True
        self.run_one("solo", "Bass", on=True, excl=False)
        self.assertEqual(self.soloed(), ["Kick", "Bass"])

    def test_null_follows_exclusive_solo_preference(self):
        self.song.exclusive_solo = True
        self.song.find("Kick").solo = True
        self.run_one("solo", "Bass", on=True, excl=None)
        self.assertEqual(self.soloed(), ["Bass"])
        self.song.exclusive_solo = False
        self.run_one("solo", "Snare", on=True, excl=None)
        self.assertEqual(self.soloed(), ["Snare", "Bass"])

    def test_unsolo_never_touches_others(self):
        for name in ("Kick", "Bass"):
            self.song.find(name).solo = True
        self.run_one("solo", "Bass", on=False, excl=True)
        self.assertEqual(self.soloed(), ["Kick"])

    def test_exclusive_solo_includes_tracks_in_folded_groups(self):
        song = fake_live.FakeSong(track_count=6, group=True)
        song.set_folded(True)
        song.find("Snare").solo = True
        tracker = TrackStateTracker()
        tracker.read(song)
        queue = CommandQueue()
        command, _ = parse_command({"op": "solo", "id": song.find("Keys")._live_ptr, "on": True, "excl": True})
        queue.enqueue(command)
        queue.apply(song, tracker.resolve)
        self.assertFalse(song.find("Snare")._solo)
        self.assertTrue(song.find("Keys")._solo)

    def test_only_changed_values_are_written(self):
        self.song.writes = []
        self.run_one("mute", "Kick", on=False)
        self.run_one("solo", "Kick", on=False, excl=True)
        self.assertEqual(self.song.writes, [])

    def test_main_track_rejects_mute_and_solo(self):
        for op in ("mute", "solo"):
            with self.subTest(op=op):
                result = self.run_one(op, "Main", on=True, excl=None)
                self.assertEqual(result.status, ERROR)
                self.assertIn("main track", result.message)

    def test_arm_ignored_where_not_armable(self):
        for name in ("Main", "A-Reverb"):
            self.assertEqual(self.run_one("arm", name, on=True).status, IGNORED)
        self.assertEqual(self.run_one("arm", "Keys", on=True).status, APPLIED)
        self.assertTrue(self.song.find("Keys")._arm)

    def test_arm_ignored_on_groups(self):
        song = fake_live.FakeSong(track_count=4, group=True)
        tracker = TrackStateTracker()
        tracker.read(song)
        queue = CommandQueue()
        queue.enqueue(Command("arm", song.group._live_ptr, on=True))
        self.assertEqual(queue.apply(song, tracker.resolve)[0].status, IGNORED)

    def armed(self, song=None):
        song = song or self.song
        return [t.name for t in song.tracks if t.can_be_armed and t._arm]

    def test_arm_null_follows_exclusive_arm_preference(self):
        self.song.exclusive_arm = True
        self.song.find("Kick").arm = True
        self.assertEqual(self.run_one("arm", "Snare", on=True, excl=None).status, APPLIED)
        self.assertEqual(self.armed(), ["Snare"])
        self.song.exclusive_arm = False
        self.run_one("arm", "Bass", on=True)  # excl absent: same as null
        self.assertEqual(self.armed(), ["Snare", "Bass"])

    def test_additive_arm_false_keeps_others(self):
        self.song.exclusive_arm = True
        self.song.find("Kick").arm = True
        self.run_one("arm", "Bass", on=True, excl=False)
        self.assertEqual(self.armed(), ["Kick", "Bass"])

    def test_exclusive_arm_true_disarms_even_with_the_preference_off(self):
        self.song.exclusive_arm = False
        for name in ("Kick", "Snare"):
            self.song.find(name).arm = True
        self.run_one("arm", "Keys", on=True, excl=True)
        self.assertEqual(self.armed(), ["Keys"])

    def test_disarm_never_touches_others(self):
        self.song.exclusive_arm = True
        for name in ("Kick", "Bass"):
            self.song.find(name).arm = True
        self.run_one("arm", "Bass", on=False, excl=True)
        self.assertEqual(self.armed(), ["Kick"])

    def test_exclusive_arm_includes_tracks_in_folded_groups_and_skips_unarmable_tracks(self):
        song = fake_live.FakeSong(track_count=6, group=True)
        song.exclusive_arm = True
        song.set_folded(True)
        song.find("Snare").arm = True
        tracker = TrackStateTracker()
        tracker.read(song)
        queue = CommandQueue()
        command, _ = parse_command({"op": "arm", "id": song.find("Keys")._live_ptr, "on": True, "excl": None})
        queue.enqueue(command)
        song.writes = []
        self.assertEqual(queue.apply(song, tracker.resolve)[0].status, APPLIED)
        self.assertEqual(self.armed(song), ["Keys"])
        # Only the two arm changes were written: the group, returns and Main were never touched.
        self.assertEqual(song.writes, ["'Snare' arm -> False", "'Keys' arm -> True"])

    def test_volume_is_clamped(self):
        self.run_one("vol", "Bass", val=1.7)
        self.assertEqual(self.song.find("Bass").mixer_device.volume.value, 1.0)
        self.run_one("vol", "Bass", val=-3)
        self.assertEqual(self.song.find("Bass").mixer_device.volume.value, 0.0)
        self.run_one("vol", "Main", val=0.5)
        self.assertEqual(self.song.master_track.mixer_device.volume.value, 0.5)

    def test_unknown_track(self):
        self.queue.enqueue(Command("mute", 123, on=True))
        result = self.queue.apply(self.song, self.tracker.resolve)[0]
        self.assertEqual(result.status, ERROR)
        self.assertEqual(result.message, "unknown track id 123 in cmd")

    def test_other_errors_are_reported_not_raised(self):
        class Broken(object):
            def __init__(self):
                self.view = None

        self.queue.enqueue(Command("select", self.song.find("Kick")._live_ptr))
        result = self.queue.apply(Broken(), self.tracker.resolve)[0]
        self.assertEqual(result.status, ERROR)
        self.assertEqual(len(self.queue), 0)


class RetryTests(unittest.TestCase):
    def setUp(self):
        self.song = fake_live.FakeSong(track_count=4)
        self.tracker = TrackStateTracker()
        self.tracker.read(self.song)
        self.queue = CommandQueue()
        self.kick = self.song.find("Kick")
        self.snare = self.song.find("Snare")

    def apply(self):
        return [(r.status, r.command.op) for r in self.queue.apply(self.song, self.tracker.resolve)]

    def test_refused_command_is_retried_next_tick_and_keeps_order(self):
        self.queue.enqueue(Command("mute", self.kick._live_ptr, on=True))
        self.queue.enqueue(Command("mute", self.snare._live_ptr, on=True))
        self.song.refuse_writes = 2
        self.assertEqual(self.apply(), [(RETRY, "mute")])
        self.assertEqual(self.apply(), [(RETRY, "mute")])
        self.assertFalse(self.kick._mute)
        self.assertFalse(self.snare._mute)
        self.assertEqual(self.apply(), [(APPLIED, "mute"), (APPLIED, "mute")])
        self.assertTrue(self.kick._mute)
        self.assertTrue(self.snare._mute)

    def test_gives_up_after_three_retries(self):
        self.queue.enqueue(Command("mute", self.kick._live_ptr, on=True))
        self.song.refuse_writes = 100
        statuses = [self.apply() for _ in range(4)]
        self.assertEqual(statuses[:3], [[(RETRY, "mute")]] * 3)
        self.assertEqual(statuses[3], [(ERROR, "mute")])
        self.assertEqual(len(self.queue), 0)
        self.assertFalse(self.kick._mute)

    def test_exclusive_arm_retry_is_idempotent(self):
        self.snare.arm = True
        self.queue.enqueue(Command("arm", self.kick._live_ptr, on=True, exclusive=None))
        self.song.refuse_writes = 1
        self.assertEqual(self.apply(), [(RETRY, "arm")])
        self.assertTrue(self.snare._arm)
        self.assertEqual(self.apply(), [(APPLIED, "arm")])
        self.assertTrue(self.kick._arm)
        self.assertFalse(self.snare._arm)

    def test_exclusive_solo_retry_is_idempotent(self):
        self.snare.solo = True
        self.queue.enqueue(Command("solo", self.kick._live_ptr, on=True, exclusive=True))
        self.song.refuse_writes = 1
        self.assertEqual(self.apply(), [(RETRY, "solo")])
        self.assertEqual(self.apply(), [(APPLIED, "solo")])
        self.assertTrue(self.kick._solo)
        self.assertFalse(self.snare._solo)

    def test_volume_end_flag_survives_coalescing(self):
        self.queue.enqueue(Command("vol", self.kick._live_ptr, value=0.1))
        self.queue.enqueue(Command("vol", self.kick._live_ptr, value=0.2, end=True))
        self.queue.enqueue(Command("vol", self.kick._live_ptr, value=0.3))
        self.assertEqual(len(self.queue), 1)
        self.assertTrue(self.queue._pending[0].end)
        self.assertAlmostEqual(self.queue._pending[0].value, 0.3, places=6)

    def test_volume_changes_coalesce(self):
        for value in (0.1, 0.2, 0.3):
            self.queue.enqueue(Command("vol", self.kick._live_ptr, value=value))
        self.queue.enqueue(Command("vol", self.snare._live_ptr, value=0.4))
        self.assertEqual(len(self.queue), 2)
        self.apply()
        self.assertAlmostEqual(self.kick.mixer_device.volume.value, 0.3, places=6)

    def test_per_tick_limit(self):
        queue = CommandQueue(max_per_tick=3)
        for _ in range(5):
            queue.enqueue(Command("select", self.kick._live_ptr))
        self.assertEqual(len(queue.apply(self.song, self.tracker.resolve)), 3)
        self.assertEqual(len(queue), 2)

    def test_queue_overflow_drops_oldest(self):
        queue = CommandQueue(max_queued=2)
        for name in ("Kick", "Snare", "Hats"):
            queue.enqueue(Command("mute", self.song.find(name)._live_ptr, on=True))
        self.assertEqual(len(queue), 2)
        self.assertEqual(queue.dropped, 1)



class VolumeWrapper(object):
    """A second Python wrapper around the same Live parameter, as Live may return on each access."""

    def __init__(self, parameter, pointer):
        self._parameter = parameter
        self._live_ptr = pointer

    def __getattr__(self, name):
        return getattr(self._parameter, name)

    def __setattr__(self, name, value):
        if name in ("_parameter", "_live_ptr"):
            object.__setattr__(self, name, value)
        else:
            setattr(self._parameter, name, value)


class GestureTests(unittest.TestCase):
    """A drag (a stream of `vol`) becomes one begin/end_gesture pair inside one undo step."""

    def setUp(self):
        self.song = fake_live.FakeSong(track_count=6)
        self.tracker = TrackStateTracker()
        self.tracker.read(self.song)
        self.queue = CommandQueue()
        self.gestures = VolumeGestures()
        self.now = 100.0

    def send(self, op, name, **fields):
        message = {"op": op, "id": self.song.find(name)._live_ptr}
        message.update(fields)
        command, problem = parse_command(message)
        self.assertIsNone(problem)
        self.queue.enqueue(command)

    def tick(self, dt=0.033):
        self.now += dt
        self.gestures.end_idle(self.now)
        return [(r.status, r.command.op) for r in self.queue.apply(self.song, self.tracker.resolve, self.gestures, self.now)]

    def events(self):
        return list(self.song.gestures)

    def assert_balanced(self):
        begins = [e for e in self.song.gestures if e[0] == "begin_gesture"]
        ends = [e for e in self.song.gestures if e[0] == "end_gesture"]
        self.assertEqual(sorted(begins), sorted(("begin_gesture", name) for _e, name in ends))
        self.assertEqual(self.song.undo_depth, 0)
        self.assertEqual(len(self.gestures), 0)

    def test_a_drag_is_one_gesture_in_one_undo_step(self):
        for step in range(30):
            self.send("vol", "Bass", val=0.5 + step * 0.01)
            self.tick()
        self.assertEqual(self.events(), [("begin_undo_step", None), ("begin_gesture", "Bass")])
        self.assertEqual(self.song.undo_depth, 1)
        self.assertEqual(len([w for w in self.song.writes if w.startswith("'Bass' Volume")]), 30)
        self.send("vol", "Bass", val=0.9, end=True)
        self.assertEqual(self.tick(), [(APPLIED, "vol")])
        self.assertEqual(
            self.events(),
            [("begin_undo_step", None), ("begin_gesture", "Bass"), ("end_gesture", "Bass"), ("end_undo_step", None)],
        )
        self.assertAlmostEqual(self.song.find("Bass").mixer_device.volume.value, 0.9, places=6)
        self.assert_balanced()

    def test_gesture_begins_before_the_first_write(self):
        order = []
        self.song.on_write = order.append
        self.send("vol", "Kick", val=0.3)
        self.tick()
        self.assertEqual(order[0], "'Kick' Volume begin_gesture")
        self.assertTrue(order[1].startswith("'Kick' Volume -> "))

    def test_unchanged_value_opens_no_gesture(self):
        current = self.song.find("Kick").mixer_device.volume.value
        self.send("vol", "Kick", val=current)
        self.send("vol", "Kick", val=current, end=True)
        self.tick()
        self.assertEqual(self.events(), [])
        self.assert_balanced()

    def test_idle_drag_closes_after_half_a_second(self):
        self.send("vol", "Kick", val=0.3)
        self.tick()
        self.tick(0.4)
        self.assertEqual(len(self.gestures), 1)
        self.tick(0.11)
        self.assertEqual(self.events()[-2:], [("end_gesture", "Kick"), ("end_undo_step", None)])
        self.assert_balanced()
        # A later vol starts a new gesture and undo step.
        self.send("vol", "Kick", val=0.4)
        self.tick()
        self.assertEqual(self.events()[-2:], [("begin_undo_step", None), ("begin_gesture", "Kick")])

    def test_unchanged_vols_keep_the_drag_alive(self):
        self.send("vol", "Kick", val=0.3)
        self.tick()
        for _ in range(5):
            self.send("vol", "Kick", val=0.3)
            self.tick(0.3)
        self.assertEqual(len(self.gestures), 1)
        self.assertEqual(self.song.undo_depth, 1)

    def test_another_command_closes_the_drag_first(self):
        order = []
        self.song.on_write = order.append
        self.send("vol", "Kick", val=0.3)
        self.tick()
        self.send("mute", "Snare", on=True)
        self.tick()
        self.assertEqual(order[-2:], ["'Kick' Volume end_gesture", "'Snare' mute -> True"])
        self.assert_balanced()

    def test_two_tracks_share_one_undo_step(self):
        self.send("vol", "Kick", val=0.3)
        self.send("vol", "Snare", val=0.3)
        self.tick()
        self.send("vol", "Kick", val=0.35, end=True)
        self.tick()
        self.assertEqual(self.song.undo_depth, 1)
        self.send("vol", "Snare", val=0.35, end=True)
        self.tick()
        self.assertEqual(
            self.events(),
            [
                ("begin_undo_step", None),
                ("begin_gesture", "Kick"),
                ("begin_gesture", "Snare"),
                ("end_gesture", "Kick"),
                ("end_gesture", "Snare"),
                ("end_undo_step", None),
            ],
        )
        self.assert_balanced()

    def test_end_all_closes_everything(self):
        self.send("vol", "Kick", val=0.3)
        self.send("vol", "Snare", val=0.3)
        self.tick()
        self.gestures.end_all()
        self.assert_balanced()
        self.gestures.end_all()
        self.assert_balanced()

    def test_failed_begin_calls_get_no_end_calls(self):
        self.song.fail_gestures = True
        self.song.fail_undo_steps = True
        self.send("vol", "Kick", val=0.3)
        self.assertEqual(self.tick(), [(APPLIED, "vol")])
        self.assertAlmostEqual(self.song.find("Kick").mixer_device.volume.value, 0.3, places=6)
        self.send("vol", "Kick", val=0.4, end=True)
        self.tick()
        self.assertEqual(self.events(), [])
        self.assertEqual(self.song.undo_depth, 0)
        self.assertEqual(len(self.gestures), 0)
        # Only the gesture fails: the undo step still opens and closes once.
        self.song.fail_undo_steps = False
        self.send("vol", "Kick", val=0.5, end=True)
        self.tick()
        self.assertEqual(self.events(), [("begin_undo_step", None), ("end_undo_step", None)])

    def test_refused_write_keeps_the_pairs_balanced(self):
        self.song.refuse_writes = 2
        self.send("vol", "Kick", val=0.3)
        self.assertEqual(self.tick(), [(RETRY, "vol")])
        self.assertEqual(self.tick(), [(RETRY, "vol")])
        self.assertEqual(self.tick(), [(APPLIED, "vol")])
        self.assertEqual(self.events(), [("begin_undo_step", None), ("begin_gesture", "Kick")])
        self.tick(0.6)
        self.assert_balanced()
        # Refused until it gives up: the gesture still closes once the drag goes idle.
        self.song.refuse_writes = 100
        self.send("vol", "Kick", val=0.6)
        statuses = [self.tick() for _ in range(4)]
        self.assertEqual(statuses[-1], [(ERROR, "vol")])
        self.tick(0.6)
        self.assert_balanced()

    def test_a_new_wrapper_of_the_same_parameter_continues_the_gesture(self):
        kick = self.song.find("Kick")
        parameter = kick.mixer_device.volume
        self.gestures.touch(kick._live_ptr, VolumeWrapper(parameter, 77), self.song, 1.0)
        self.gestures.touch(kick._live_ptr, VolumeWrapper(parameter, 77), self.song, 1.1)
        self.assertEqual(self.events(), [("begin_undo_step", None), ("begin_gesture", "Kick")])
        # A different parameter for the same track restarts it.
        self.gestures.touch(kick._live_ptr, VolumeWrapper(parameter, 78), self.song, 1.2)
        self.assertEqual(self.events()[2:], [("end_gesture", "Kick"), ("end_undo_step", None), ("begin_undo_step", None), ("begin_gesture", "Kick")])
        self.gestures.end_all()
        self.assert_balanced()


if __name__ == "__main__":
    unittest.main()
