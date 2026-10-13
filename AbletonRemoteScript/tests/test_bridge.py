"""The Bridge state machine end to end, on a fake song with a recording transport."""

import json
import os
import random
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_live
from meterbridge_rig import Rig
from MeterBridge import protocol


class SubscribeTests(unittest.TestCase):
    def test_nothing_is_sent_before_a_sub(self):
        rig = Rig()
        rig.run(2.0)
        self.assertEqual(rig.types(), [])
        self.assertTrue(rig.transport.is_open)

    def test_sub_sends_hello_tracks_sel_surfaces_then_meters(self):
        rig = Rig(track_count=12)
        rig.subscribe(port=47900, hz=30)
        types = rig.types()
        self.assertEqual(types[:5], ["hello", "tracks", "sel", "surfaces", "m"])
        self.assertTrue(all(port == 47900 for _m, port, _size in rig.transport.sent))
        hello = rig.messages("hello")[0]
        self.assertEqual(hello["session"], 4242)
        self.assertEqual(hello["hz"], 30)
        self.assertEqual(hello["live"], "12.4.6")
        self.assertEqual(len(hello["vc"]["x"]), 101)
        self.assertEqual(hello["vc"]["db"][85], 0.0)
        tracks = rig.messages("tracks")[0]
        self.assertEqual((tracks["gen"], tracks["part"], tracks["parts"], tracks["total"]), (1, 0, 1, 15))
        self.assertEqual([item["n"] for item in tracks["items"]][-3:], ["A-Reverb", "B-Delay", "Main"])
        self.assertEqual(rig.messages("sel")[0]["id"], rig.tid("Kick"))
        surfaces = rig.messages("surfaces")[0]
        self.assertIsNone(surfaces["warn"])
        self.assertEqual(surfaces["units"][0]["strips"], [t._live_ptr for t in rig.song.visible_tracks[:8]])

    def test_large_sets_are_chunked(self):
        rig = Rig(track_count=200)
        rig.subscribe()
        parts = rig.messages("tracks")
        self.assertEqual(len(parts), 7)
        self.assertEqual(sum(len(p["items"]) for p in parts), 203)
        self.assertTrue(all(size <= protocol.MAX_DATAGRAM_BYTES for _m, _p, size in rig.transport.sent))

    def test_keepalive_does_not_resend_state(self):
        rig = Rig()
        rig.subscribe()
        rig.keep_alive(4.0)
        self.assertEqual(rig.types().count("hello"), 1)
        self.assertEqual(rig.types().count("tracks"), 1)

    def test_heartbeat_every_second(self):
        rig = Rig()
        rig.subscribe()
        rig.keep_alive(3.05)
        beats = rig.messages("hb")
        self.assertEqual([b["seq"] for b in beats], [1, 2, 3])

    def test_meter_rate_follows_hz(self):
        for hz in (30, 20, 60):
            with self.subTest(hz=hz):
                rig = Rig()
                rig.subscribe(hz=hz)
                rig.clear()
                rig.keep_alive(2.0, hz=hz)
                count = len(rig.messages("m"))
                self.assertAlmostEqual(count / 2.0, min(hz, 1 / 0.016), delta=hz * 0.12)

    def test_meter_seq_increases(self):
        rig = Rig()
        rig.subscribe()
        rig.keep_alive(0.5)
        seqs = [m["seq"] for m in rig.messages("m")]
        self.assertEqual(seqs, list(range(1, len(seqs) + 1)))

    def test_timeout_stops_meters_and_deltas_then_resubscribe_resends_everything(self):
        rig = Rig()
        rig.subscribe()
        rig.run(4.9)
        self.assertGreater(len(rig.messages("m")), 100)
        rig.run(0.2)
        self.assertFalse(rig.bridge.is_subscribed)
        rig.clear()
        rig.song.find("Kick").mute = True
        rig.run(3.0)
        self.assertEqual(rig.types(), [])
        rig.subscribe()
        self.assertEqual(rig.types()[:4], ["hello", "tracks", "sel", "surfaces"])
        self.assertEqual(rig.messages("tracks")[0]["gen"], 2)
        self.assertTrue(any(i["m"] for i in rig.messages("tracks")[0]["items"] if i["n"] == "Kick"))

    def test_session_is_stable_and_random_by_default(self):
        first = Rig(session=None)
        second = Rig(session=None)
        self.assertNotEqual(first.bridge.session, second.bridge.session)
        first.subscribe()
        first.run(6.0)
        first.subscribe()
        sessions = {m["session"] for m in first.messages("hello")}
        self.assertEqual(sessions, {first.bridge.session})

    def test_new_port_resubscribes(self):
        rig = Rig()
        rig.subscribe(port=47800)
        rig.subscribe(port=47810)
        self.assertEqual(rig.types().count("hello"), 2)
        self.assertEqual(rig.transport.sent[-1][1], 47810)


class AppRestartTests(unittest.TestCase):
    """A new `app` value (the app restarted its Live source) within 5 s gets the full state again."""

    def quick_restart(self, first_app, second_app):
        rig = Rig(track_count=20)
        rig.subscribe(app=first_app)
        rig.keep_alive(3.0, app=first_app)
        rig.run(2.0)  # the app is gone for 2 s: still within the 5 s timeout
        self.assertTrue(rig.bridge.is_subscribed)
        rig.clear()
        rig.subscribe(app=second_app)
        rig.run(0.2)
        return rig

    def test_new_app_value_resends_hello_tracks_sel_and_surfaces(self):
        rig = self.quick_restart(111, 222)
        self.assertEqual(rig.types()[:4], ["hello", "tracks", "sel", "surfaces"])
        self.assertEqual(rig.messages("tracks")[0]["gen"], 2)

    def test_same_or_absent_app_value_is_a_keepalive(self):
        for second in (111, None):
            with self.subTest(second=second):
                rig = self.quick_restart(111, second)
                self.assertNotIn("hello", rig.types())
                self.assertNotIn("tracks", rig.types())
                self.assertIn("m", rig.types())
                self.assertEqual(rig.bridge.subscription.app, 111)

    def test_switching_back_to_live_after_a_bank_change_gets_the_new_strips(self):
        # Source Live -> Simulator -> Live within 5 s while the surface banked: the app's socket was
        # closed when the script sent the new `surfaces`, so it needs them again.
        rig = Rig(track_count=20)
        rig.subscribe(app=1)
        rig.keep_alive(2.0, app=1)
        rig.controller.bank(1)
        rig.run(1.0)
        rig.clear()
        rig.subscribe(app=2)
        surfaces = rig.messages("surfaces")
        self.assertEqual(len(surfaces), 1)
        self.assertEqual(surfaces[0]["units"][0]["strips"][0], rig.song.visible_tracks[8]._live_ptr)


class DeltaTests(unittest.TestCase):
    def setUp(self):
        self.rig = Rig(track_count=12, group=True)
        self.rig.subscribe()
        self.rig.run(0.2)
        self.rig.clear()

    def test_state_change_sends_one_track_delta(self):
        self.rig.song.find("Bass").arm = True
        self.rig.run(0.2)
        deltas = self.rig.messages("track")
        self.assertEqual([d["item"]["n"] for d in deltas], ["Bass"])
        self.assertEqual(deltas[0]["gen"], 1)
        self.assertIs(deltas[0]["item"]["a"], True)

    def test_folding_sends_a_new_generation(self):
        self.rig.song.set_folded(True)
        self.rig.run(0.2)
        tracks = self.rig.messages("tracks")
        self.assertEqual(tracks[0]["gen"], 2)
        self.assertNotIn("Kick", [i["n"] for i in tracks[0]["items"]])
        surfaces = self.rig.messages("surfaces")
        self.assertEqual(len(surfaces), 1)
        self.assertEqual(surfaces[0]["units"][0]["strips"][0], self.rig.tid("Drums"))

    def test_selection_change_and_folded_selection(self):
        self.rig.song.view.selected_track = self.rig.song.find("Snare")
        self.rig.run(0.2)
        self.assertEqual([m["id"] for m in self.rig.messages("sel")], [self.rig.tid("Snare")])
        self.rig.song.set_folded(True)
        self.rig.run(0.2)
        self.assertEqual(self.rig.messages("sel")[-1]["id"], None)

    def test_bank_change_sends_surfaces_once(self):
        self.rig.controller.bank(1)
        self.rig.run(0.5)
        surfaces = self.rig.messages("surfaces")
        self.assertEqual(len(surfaces), 1)
        self.assertEqual(surfaces[0]["units"][0]["strips"][0], self.rig.song.visible_tracks[8]._live_ptr)


class CommandFlowTests(unittest.TestCase):
    def setUp(self):
        self.rig = Rig(track_count=12)
        self.rig.subscribe()
        self.rig.run(0.2)
        self.rig.clear()

    def cmd(self, op, name, **fields):
        message = {"v": 1, "t": "cmd", "op": op, "id": self.rig.tid(name)}
        message.update(fields)
        return message

    def test_commands_are_only_applied_in_the_tick(self):
        bridge = self.rig.bridge
        writes_before = len(self.rig.song.writes)
        bridge.handle_message(self.cmd("mute", "Bass", on=True), self.rig.now)
        bridge.handle_message(self.cmd("vol", "Bass", val=0.25), self.rig.now)
        self.assertFalse(self.rig.song.find("Bass")._mute)
        self.assertNotAlmostEqual(self.rig.song.find("Bass").mixer_device.volume.value, 0.25, places=4)
        self.assertEqual(len(self.rig.song.writes), writes_before)
        self.assertEqual(len(bridge.commands), 2)
        self.rig.tick()
        self.assertTrue(self.rig.song.find("Bass")._mute)
        self.assertAlmostEqual(self.rig.song.find("Bass").mixer_device.volume.value, 0.25, places=6)
        self.assertEqual(len(self.rig.song.writes), writes_before + 2)

    def test_echo_arrives_in_the_same_tick(self):
        self.rig.push(self.cmd("solo", "Bass", on=True, excl=None))
        self.rig.tick()
        names = [d["item"]["n"] for d in self.rig.messages("track")]
        self.assertIn("Bass", names)
        self.assertIn("Kick", names)  # now muted via solo
        self.assertEqual(len(names), len(set(names)))

    def test_volume_echo_is_one_track(self):
        self.rig.push(self.cmd("vol", "Keys", val=0.5))
        self.rig.tick()
        deltas = self.rig.messages("track")
        self.assertEqual([(d["item"]["n"], d["item"]["vol"], d["item"]["vs"]) for d in deltas],
                         [("Keys", 0.5, "-14.0 dB")])

    def test_select_echoes_sel(self):
        self.rig.push(self.cmd("select", "Hats"))
        self.rig.tick()
        self.assertEqual([m["id"] for m in self.rig.messages("sel")], [self.rig.tid("Hats")])

    def test_errors_go_back_as_err(self):
        self.rig.push({"v": 1, "t": "cmd", "op": "mute", "id": 123, "on": True})
        self.rig.push(self.cmd("mute", "Main", on=True))
        self.rig.push({"v": 1, "t": "cmd", "op": "warp", "id": 1})
        self.rig.tick()
        self.assertEqual(
            [m["msg"] for m in self.rig.messages("err")],
            ["unknown cmd op 'warp'", "unknown track id 123 in cmd", "the main track has no mute; ignored"],
        )

    def test_refusal_retries_on_following_ticks(self):
        self.rig.song.refuse_writes = 2
        self.rig.push(self.cmd("mute", "Snare", on=True))
        self.rig.tick()
        self.rig.tick()
        self.assertFalse(self.rig.song.find("Snare")._mute)
        self.rig.tick()
        self.assertTrue(self.rig.song.find("Snare")._mute)
        self.assertEqual(self.rig.messages("err"), [])

    def test_commands_apply_without_a_subscription(self):
        rig = Rig()
        rig.push({"v": 1, "t": "cmd", "op": "mute", "id": rig.tid("Kick"), "on": True})
        rig.tick()
        self.assertTrue(rig.song.find("Kick")._mute)


class GestureFlowTests(unittest.TestCase):
    """Volume drags through the Bridge: one gesture and one undo step per drag (docs/PROTOCOL.md `vol`)."""

    def setUp(self):
        self.rig = Rig(track_count=12)
        self.rig.subscribe()
        self.rig.run(0.2)
        self.rig.clear()

    def vol(self, value, **fields):
        message = {"v": 1, "t": "cmd", "op": "vol", "id": self.rig.tid("Bass"), "val": value}
        message.update(fields)
        self.rig.push(message)

    def assert_closed(self):
        song = self.rig.song
        self.assertEqual(
            song.gestures,
            [("begin_undo_step", None), ("begin_gesture", "Bass"), ("end_gesture", "Bass"), ("end_undo_step", None)],
        )
        self.assertEqual(song.undo_depth, 0)
        self.assertEqual(len(self.rig.bridge.gestures), 0)

    def test_a_30_message_drag_is_one_gesture_closed_by_end(self):
        writes_before = len(self.rig.song.writes)
        for step in range(30):
            self.vol(0.3 + step * 0.01)
            self.rig.tick(0.033)
        self.assertEqual(self.rig.song.undo_depth, 1)
        self.vol(0.7, end=True)
        self.rig.tick()
        self.assert_closed()
        self.assertEqual(len(self.rig.song.writes) - writes_before, 31)
        self.assertEqual(self.rig.messages("err"), [])

    def test_an_idle_drag_closes_after_half_a_second_without_commands(self):
        self.vol(0.3)
        self.rig.tick()
        self.rig.run(0.45)
        self.assertEqual(self.rig.song.undo_depth, 1)
        self.rig.run(0.1)
        self.assert_closed()

    def test_the_end_of_the_subscription_closes_a_drag(self):
        self.rig.bridge.gestures.idle = 100.0  # only the subscription's end can close it here
        self.vol(0.3)
        self.rig.tick()
        while self.rig.bridge.is_subscribed:
            self.assertEqual(self.rig.song.undo_depth, 1)
            self.rig.tick(0.1)
        self.assert_closed()

    def test_resending_the_current_value_writes_nothing_and_opens_nothing(self):
        self.vol(0.3, end=True)
        self.rig.tick()
        writes = list(self.rig.song.writes)
        self.vol(0.3)
        self.vol(0.3, end=True)
        self.rig.tick()
        self.rig.run(0.6)
        self.assertEqual(self.rig.song.writes, writes)
        self.assert_closed()

    def test_close_ends_an_open_drag(self):
        self.vol(0.3)
        self.rig.tick()
        self.rig.bridge.close()
        self.assert_closed()


class DatagramRobustnessTests(unittest.TestCase):
    """One bad datagram costs only itself, never the rest of the tick's batch."""

    def setUp(self):
        self.rig = Rig(track_count=12)
        self.rig.subscribe()
        self.rig.run(0.2)
        self.rig.clear()

    def mute(self, name):
        return {"v": 1, "t": "cmd", "op": "mute", "id": self.rig.tid(name), "on": True}

    def test_a_failing_datagram_does_not_drop_the_rest_of_the_batch(self):
        bridge = self.rig.bridge
        handle = bridge.handle_message

        def exploding(message, now):
            if message.get("boom"):
                raise RuntimeError("boom")
            return handle(message, now)

        bridge.handle_message = exploding
        self.rig.push({"v": 1, "t": "sub", "boom": 1})
        self.rig.push(self.mute("Kick"))
        self.rig.tick()
        self.assertTrue(self.rig.song.find("Kick")._mute)
        self.assertEqual(bridge.stats["errors"], 1)
        self.assertTrue(any("error handling a datagram" in line for line in self.rig.lines))

    def test_huge_integers_are_rejected_and_the_next_datagram_still_applies(self):
        self.rig.transport.push_raw(('{"v":1,"t":"sub","port":47800,"hz":%s}' % ("9" * 400)).encode("utf-8"))
        self.rig.push(self.mute("Kick"))
        self.rig.transport.push_raw(
            ('{"v":1,"t":"cmd","op":"vol","id":%d,"val":%s}' % (self.rig.tid("Snare"), "9" * 400)).encode("utf-8")
        )
        before = self.rig.bridge.subscription.last_sub
        self.rig.push({"v": 1, "t": "sub", "port": 47800, "hz": 30})
        self.rig.tick()
        self.assertTrue(self.rig.song.find("Kick")._mute)
        self.assertEqual(self.rig.bridge.hz, 30)
        self.assertGreater(self.rig.bridge.subscription.last_sub, before)
        self.assertEqual([m["msg"] for m in self.rig.messages("err")], ["cmd vol needs a numeric val"])
        self.assertEqual(self.rig.bridge.stats["errors"], 0)

    def test_oversize_datagrams_are_dropped_unread(self):
        rig = Rig()
        padded = json.dumps({"v": 1, "t": "sub", "port": 47800, "pad": "x" * 9000}).encode("utf-8")
        rig.transport.push_raw(padded)
        rig.tick()
        self.assertEqual(rig.types(), [])
        self.assertFalse(rig.bridge.is_subscribed)
        self.assertTrue(any("larger than 8192 bytes" in line for line in rig.lines))

    def test_deeply_nested_json_is_ignored(self):
        self.rig.transport.push_raw(b'{"v":1,"t":"watch","ids":' + b"[" * 4000 + b"]" * 4000 + b"}")
        self.rig.push(self.mute("Snare"))
        self.rig.tick()
        self.assertTrue(self.rig.song.find("Snare")._mute)
        self.assertEqual(self.rig.bridge.subscription.watch, [])
        self.assertEqual(self.rig.bridge.stats["errors"], 0)


class PollTimingTests(unittest.TestCase):
    """The state and surface polls never read Live in the same tick; slow reads are logged."""

    def instrument(self, rig):
        reads, surfaces = [], []
        tracker_read = rig.bridge.tracker.read
        read_surfaces = rig.bridge._read_surfaces

        def counting_read(song):
            reads.append(rig.now)
            return tracker_read(song)

        def counting_surfaces():
            surfaces.append(rig.now)
            return read_surfaces()

        rig.bridge.tracker.read = counting_read
        rig.bridge._read_surfaces = counting_surfaces
        return reads, surfaces

    def test_polls_never_share_a_tick(self):
        for jitter in (False, True):
            with self.subTest(jitter=jitter):
                rig = Rig(track_count=24)
                rig.subscribe()
                reads, surfaces = self.instrument(rig)
                rng = random.Random(5)
                elapsed = 0.0
                next_sub = 1.0
                next_cmd = 0.25
                while elapsed < 5.0:
                    if elapsed >= next_sub:
                        next_sub += 1.0
                        rig.push({"v": 1, "t": "sub", "port": 47800, "hz": 30})
                    if jitter and elapsed >= next_cmd:
                        # Commands force a state poll in the tick they are applied.
                        next_cmd += rng.uniform(0.05, 0.4)
                        rig.push({"v": 1, "t": "cmd", "op": "mute", "id": rig.tid("Bass"), "on": rng.random() < 0.5})
                    dt = rng.uniform(0.008, 0.045) if jitter else 0.016
                    rig.tick(dt)
                    elapsed += dt
                self.assertGreater(len(reads), 35)
                self.assertGreater(len(surfaces), 35)
                self.assertEqual(sorted(set(reads) & set(surfaces)), [])

    def test_surfaces_are_still_polled_when_ticks_are_100_ms(self):
        # Without Live.Base.Timer, update_display drives ticks every 100 ms: both polls are due on
        # every tick, and the surface poll may wait at most one tick.
        rig = Rig(track_count=12)
        rig.subscribe()
        reads, surfaces = self.instrument(rig)
        rig.keep_alive(4.0, dt=0.1)
        self.assertGreaterEqual(len(reads), 30)
        self.assertGreaterEqual(len(surfaces), 18)

    def test_slow_reads_are_logged_rate_limited_with_the_track_count(self):
        ticks = [0.0]

        def perf_clock():
            ticks[0] += 0.003  # every read appears to take 3 ms
            return ticks[0]

        rig = Rig(track_count=12, perf_clock=perf_clock)
        rig.subscribe()
        rig.keep_alive(3.0)
        lines = [line for line in rig.lines if "reading" in line]
        self.assertEqual(len(lines), 1)
        self.assertIn("reading 15 tracks from Live took 3.0 ms", lines[0])
        self.assertGreater(rig.bridge.stats["slow_reads"], 20)
        self.assertAlmostEqual(rig.bridge.slowest_read, 0.003, places=6)

    def test_fast_reads_are_not_logged(self):
        rig = Rig(track_count=12)
        rig.subscribe()
        rig.keep_alive(1.0)
        self.assertEqual([line for line in rig.lines if "reading" in line], [])
        self.assertEqual(rig.bridge.stats["slow_reads"], 0)


class MeterFlowTests(unittest.TestCase):
    def test_meter_set_is_strips_selected_main_and_watched(self):
        rig = Rig(track_count=20)
        rig.song.view.selected_track = rig.song.find("Perc")
        rig.subscribe()
        frame = rig.messages("m")[-1]
        expected = [t._live_ptr for t in rig.song.visible_tracks[:8]]
        expected += [rig.tid("Perc"), rig.song.master_track._live_ptr]
        self.assertEqual([e[0] for e in frame["d"]], expected)
        rig.push({"v": 1, "t": "watch", "ids": [rig.tid("A-Reverb"), 987654321]})
        rig.run(0.1)
        frame = rig.messages("m")[-1]
        self.assertEqual([e[0] for e in frame["d"]], expected + [rig.tid("A-Reverb")])
        for _tid, left, right in frame["d"]:
            self.assertEqual(left, round(left, 4))
            self.assertTrue(0.0 <= left <= 1.0 and 0.0 <= right <= 1.0)

    def test_watch_removal_sends_one_zero_frame(self):
        rig = Rig(track_count=20)
        rig.subscribe()
        reverb = rig.tid("A-Reverb")
        rig.push({"v": 1, "t": "watch", "ids": [reverb]})
        rig.run(0.1)
        rig.push({"v": 1, "t": "watch", "ids": []})
        rig.clear()
        rig.run(0.2)
        frames = [[e for e in m["d"] if e[0] == reverb] for m in rig.messages("m")]
        self.assertEqual(frames[0], [[reverb, 0.0, 0.0]])
        self.assertTrue(all(f == [] for f in frames[1:]))

    def test_moving_meters(self):
        rig = Rig(track_count=8)
        rig.subscribe()
        rig.keep_alive(1.0)
        kick = rig.tid("Kick")
        values = {e[1] for m in rig.messages("m") for e in m["d"] if e[0] == kick}
        self.assertGreater(len(values), 5)


class RobustnessTests(unittest.TestCase):
    def test_wrong_version_is_ignored_with_one_warning(self):
        rig = Rig()
        rig.push({"v": 2, "t": "sub", "port": 47800})
        rig.push({"v": "1", "t": "sub", "port": 47800})
        rig.push({"v": True, "t": "sub", "port": 47800})
        rig.tick()
        self.assertEqual(rig.types(), [])
        self.assertEqual(len([line for line in rig.lines if "protocol version" in line]), 1)

    def test_garbage_and_unknown_types_are_ignored(self):
        rig = Rig()
        rig.transport.push_raw(b"\x00\xff garbage")
        rig.transport.push_raw(b"[]")
        rig.push({"v": 1, "t": "future-thing", "x": 1})
        rig.subscribe()
        self.assertEqual(rig.types()[0], "hello")

    def test_bind_failure_retries_every_five_seconds(self):
        rig = Rig()
        rig.transport.fail_open = True
        rig.run(1.0)
        self.assertFalse(rig.transport.is_open)
        self.assertTrue(any("could not listen" in line for line in rig.lines))
        rig.transport.fail_open = False
        rig.run(3.0)
        self.assertFalse(rig.transport.is_open)
        rig.run(2.0)
        self.assertTrue(rig.transport.is_open)

    def test_a_failing_step_does_not_stop_the_others(self):
        rig = Rig()

        def broken_surfaces():
            raise RuntimeError("slots exploded")

        rig.bridge._control_surfaces = broken_surfaces
        rig.subscribe()
        surfaces = rig.messages("surfaces")[0]
        self.assertEqual(surfaces["units"], [])
        self.assertIn("slots exploded", surfaces["warn"])
        rig.run(0.5)
        self.assertGreater(len(rig.messages("m")), 10)

    def test_exceptions_in_steps_are_logged_rate_limited(self):
        rig = Rig()
        rig.subscribe()
        rig.bridge._song = lambda: (_ for _ in ()).throw(RuntimeError("song gone"))
        rig.run(3.0)
        errors = [line for line in rig.lines if "song gone" in line]
        self.assertGreaterEqual(len(errors), 1)
        self.assertLessEqual(len(errors), 2)
        self.assertGreater(rig.bridge.stats["errors"], 10)
        self.assertGreater(len(rig.messages("m")), 50)

    def test_missing_private_attribute_still_lists_unit_with_warning(self):
        class MackieControl(object):
            pass

        rig = Rig(slots=[MackieControl(), None, None, None, None, None, None])
        rig.subscribe()
        surfaces = rig.messages("surfaces")[0]
        self.assertEqual(surfaces["units"][0]["strips"], [None] * 8)
        self.assertIn("_MackieControl__channel_strips", surfaces["warn"])
        self.assertTrue(any("bank follow" in line for line in rig.lines))

    def test_close_stops_everything(self):
        rig = Rig()
        rig.subscribe()
        rig.bridge.close()
        self.assertTrue(rig.transport.closed)
        rig.clear()
        rig.run(1.0)
        self.assertEqual(rig.types(), [])

    def test_unicode_names_survive(self):
        song = fake_live.FakeSong(track_count=3)
        song.find("Kick").name = "Kick \U0001f941 Grün"
        rig = Rig(song=song)
        rig.subscribe()
        names = [i["n"] for i in rig.messages("tracks")[0]["items"]]
        self.assertEqual(names[0], "Kick \U0001f941 Grün")


if __name__ == "__main__":
    unittest.main()
