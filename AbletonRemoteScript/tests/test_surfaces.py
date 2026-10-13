"""Surface introspection: unit order, strips, and graceful failure."""

import os
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_live
from MeterBridge.surfaces import mackie_role, physical_order, read_surfaces, strip_track_ids


def ids(tracks):
    return [None if t is None else t._live_ptr for t in tracks]


class MackieControl(object):
    """A MackieControl whose private strip attribute was renamed by a Live update."""

    def __init__(self):
        self._MackieControl__strips_v2 = []


class MackieControlXT(object):
    """An XT without channel_strips()."""


class StripWithoutAssignedTrack(object):
    pass


class RaisingStrip(object):
    def assigned_track(self):
        raise RuntimeError("boom")


class ForkedMackieControl(fake_live.MackieControl):
    """A renamed fork (e.g. a customised UF8 script) still counts as a main unit."""


class SurfaceTests(unittest.TestCase):
    def setUp(self):
        self.song = fake_live.FakeSong(track_count=40)

    def test_empty_slots(self):
        self.assertEqual(read_surfaces([None] * 7), ([], None))
        self.assertEqual(read_surfaces([]), ([], None))
        self.assertEqual(read_surfaces(None), ([], None))

    def test_single_main_unit(self):
        controller, slots = fake_live.build_mackie_stack(self.song)
        slots[3] = fake_live.OtherScript()
        units, warn = read_surfaces(slots)
        self.assertIsNone(warn)
        self.assertEqual(len(units), 1)
        self.assertEqual(units[0]["slot"], 1)
        self.assertEqual(units[0]["script"], "MackieControl")
        self.assertEqual(units[0]["role"], "main")
        self.assertEqual(units[0]["strips"], ids(self.song.visible_tracks[:8]))
        self.assertEqual(list(units[0].keys()), ["slot", "script", "role", "strips"])

    def test_bank_offset_moves_the_strips(self):
        controller, slots = fake_live.build_mackie_stack(self.song)
        controller.bank(1)
        units, _warn = read_surfaces(slots)
        self.assertEqual(units[0]["strips"], ids(self.song.visible_tracks[8:16]))

    def test_strips_past_the_end_are_null(self):
        song = fake_live.FakeSong(track_count=5)
        _controller, slots = fake_live.build_mackie_stack(song)
        units, _warn = read_surfaces(slots)
        self.assertEqual(units[0]["strips"][:5], ids(song.visible_tracks[:5]))
        self.assertEqual(units[0]["strips"][5:], [None, None, None])

    def test_right_extensions_follow_the_main_unit(self):
        controller, slots = fake_live.build_mackie_stack(self.song, left_xts=0, right_xts=2)
        units, warn = read_surfaces(slots)
        self.assertIsNone(warn)
        self.assertEqual([(u["slot"], u["role"]) for u in units], [(1, "main"), (2, "xt"), (3, "xt")])
        self.assertEqual(strip_track_ids(units), ids(self.song.visible_tracks[:24]))
        self.assertEqual(controller.strip_count, 24)

    def test_left_extensions_come_before_the_main_unit(self):
        _controller, slots = fake_live.build_mackie_stack(self.song, left_xts=2, right_xts=1)
        units, _warn = read_surfaces(slots)
        self.assertEqual(
            [(u["slot"], u["script"], u["role"]) for u in units],
            [(1, "MackieControlXT", "xt"), (2, "MackieControlXT", "xt"), (3, "MackieControl", "main"),
             (4, "MackieControlXT", "xt")],
        )
        self.assertEqual(strip_track_ids(units), ids(self.song.visible_tracks[:32]))

    def test_physical_order_rule_with_gaps(self):
        entries = [
            {"slot": 6, "role": "xt"},
            {"slot": 4, "role": "main"},
            {"slot": 2, "role": "xt"},
            {"slot": 1, "role": "xt"},
            {"slot": 7, "role": "xt"},
        ]
        self.assertEqual([e["slot"] for e in physical_order(entries)], [1, 2, 4, 6, 7])
        self.assertEqual([e["slot"] for e in physical_order([{"slot": 5, "role": "xt"}, {"slot": 2, "role": "xt"}])],
                         [2, 5])

    def test_leftover_xts_without_ports_extend_the_bank(self):
        # The user's Bronx setup: UF8 MackieControl in slot 1, leftover XTs in slots 4-6.
        controller = fake_live.FakeStripController(self.song)
        controller.strip_count = 32
        slots = [None] * 7
        slots[0] = fake_live.MackieControl(controller, 0)
        slots[1] = fake_live.OtherScript()
        slots[2] = fake_live.OtherScript()
        for k, slot in enumerate((3, 4, 5)):
            slots[slot] = fake_live.MackieControlXT(controller, 8 * (k + 1))
        units, warn = read_surfaces(slots)
        self.assertIsNone(warn)
        self.assertEqual([u["slot"] for u in units], [1, 4, 5, 6])
        controller.bank(1)
        units, _warn = read_surfaces(slots)
        self.assertEqual(units[0]["strips"], ids(self.song.visible_tracks[32:40]))

    def test_missing_private_attribute_reports_empty_strips_and_warns(self):
        slots = [MackieControl(), None, None]
        units, warn = read_surfaces(slots)
        self.assertEqual(units, [{"slot": 1, "script": "MackieControl", "role": "main", "strips": [None] * 8}])
        self.assertIn("slot 1", warn)
        self.assertIn("_MackieControl__channel_strips", warn)

    def test_xt_without_channel_strips_warns(self):
        _controller, slots = fake_live.build_mackie_stack(self.song)
        slots[1] = MackieControlXT()
        units, warn = read_surfaces(slots)
        self.assertEqual([u["role"] for u in units], ["main", "xt"])
        self.assertEqual(units[1]["strips"], [None] * 8)
        self.assertEqual(units[0]["strips"], ids(self.song.visible_tracks[:8]))
        self.assertIn("MackieControlXT in slot 2", warn)

    def test_strip_failures_warn_instead_of_raising(self):
        controller, slots = fake_live.build_mackie_stack(self.song)
        main = slots[0]
        main._MackieControl__channel_strips = [StripWithoutAssignedTrack()] * 8
        units, warn = read_surfaces(slots)
        self.assertEqual(units[0]["strips"], [None] * 8)
        self.assertIn("assigned_track", warn)
        main._MackieControl__channel_strips = [RaisingStrip()] * 8
        units, warn = read_surfaces(slots)
        self.assertEqual(units[0]["strips"], [None] * 8)
        self.assertIn("boom", warn)
        main._MackieControl__channel_strips = 42
        units, warn = read_surfaces(slots)
        self.assertIn("unreadable", warn)

    def test_unreadable_slot_list_warns(self):
        class Exploding(object):
            def __iter__(self):
                raise RuntimeError("no slots")

        units, warn = read_surfaces(Exploding())
        self.assertEqual(units, [])
        self.assertIn("no slots", warn)

    def test_two_main_units_warn(self):
        controller, slots = fake_live.build_mackie_stack(self.song)
        slots[4] = fake_live.MackieControl(controller, 0)
        units, warn = read_surfaces(slots)
        self.assertEqual([u["slot"] for u in units], [1, 5])
        self.assertIn("2 MackieControl units", warn)

    def test_roles(self):
        controller = fake_live.FakeStripController(self.song)
        self.assertEqual(mackie_role(fake_live.MackieControl(controller, 0)), "main")
        self.assertEqual(mackie_role(fake_live.MackieControlXT(controller, 0)), "xt")
        self.assertEqual(mackie_role(ForkedMackieControl(controller, 0)), "main")
        self.assertIsNone(mackie_role(fake_live.OtherScript()))
        self.assertIsNone(mackie_role(None))

    def test_forked_main_unit_is_read(self):
        controller = fake_live.FakeStripController(self.song)
        slots = [ForkedMackieControl(controller, 0)]
        units, warn = read_surfaces(slots)
        self.assertIsNone(warn)
        self.assertEqual(units[0]["script"], "ForkedMackieControl")
        self.assertEqual(units[0]["strips"], ids(self.song.visible_tracks[:8]))

    def test_returns_view(self):
        controller, slots = fake_live.build_mackie_stack(self.song)
        controller.view_returns = True
        units, _warn = read_surfaces(slots)
        self.assertEqual(units[0]["strips"], ids(self.song.return_tracks) + [None] * 6)


if __name__ == "__main__":
    unittest.main()
