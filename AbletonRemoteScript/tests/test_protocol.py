"""Encoding, chunking and message shapes against docs/PROTOCOL.md."""

import json
import os
import re
import sys
import unittest

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _path in (_ROOT, os.path.join(_ROOT, "tools"), os.path.join(_ROOT, "tests")):
    if _path not in sys.path:
        sys.path.insert(0, _path)

from MeterBridge import protocol
from MeterBridge.commands import parse_command
from MeterBridge.tracks import RECORD_KEYS

PROTOCOL_DOC = os.path.join(os.path.dirname(_ROOT), "docs", "PROTOCOL.md")


def make_record(index, name):
    return {
        "id": 140523312345 + index * 752,
        "i": index,
        "n": name,
        "c": 0xFF94A6,
        "k": "audio",
        "m": False,
        "s": False,
        "a": False,
        "ms": False,
        "ao": True,
        "vol": 0.850000,
        "vs": "0.0 dB",
    }


def protocol_doc():
    if not os.path.exists(PROTOCOL_DOC):
        return None
    with open(PROTOCOL_DOC, "rb") as handle:
        return handle.read().decode("utf-8")


class EncodingTests(unittest.TestCase):
    def test_encoding_is_compact_utf8(self):
        data = protocol.encode({"v": 1, "t": "x", "n": "Grün ♫"})
        self.assertEqual(data, '{"v":1,"t":"x","n":"Grün ♫"}'.encode("utf-8"))

    def test_lone_surrogates_do_not_raise(self):
        data = protocol.encode({"n": "bad \ud800 name"})
        self.assertIsInstance(json.loads(data.decode("utf-8")), dict)

    def test_nan_is_refused_rather_than_sent_as_invalid_json(self):
        with self.assertRaises(ValueError):
            protocol.encode({"x": float("nan")})

    def test_decode(self):
        self.assertEqual(protocol.decode(b'{"v":1,"t":"sub"}'), ({"v": 1, "t": "sub"}, None))
        self.assertIsNone(protocol.decode(b"\xff\xfe")[0])
        self.assertIsNone(protocol.decode(b"not json")[0])
        self.assertIsNone(protocol.decode(b"[1,2]")[0])

    def test_oversize_datagrams_are_dropped_unread(self):
        fits = b'{"v":1,"t":"sub"' + b" " * (protocol.MAX_DATAGRAM_BYTES - 17) + b"}"
        self.assertEqual(len(fits), protocol.MAX_DATAGRAM_BYTES)
        self.assertEqual(protocol.decode(fits), ({"v": 1, "t": "sub"}, None))
        message, problem = protocol.decode(fits[:-1] + b" }")
        self.assertIsNone(message)
        self.assertIn("larger than 8192 bytes", problem)
        self.assertIsNone(protocol.decode(None)[0])

    def test_deep_nesting_is_not_json_rather_than_an_exception(self):
        # Python 3.7-3.10 raise RecursionError (not ValueError) for deep nesting; newer ones parse it.
        nested = b'{"v":1,"t":"sub","x":' + b"[" * 4000 + b"]" * 4000 + b"}"
        message, problem = protocol.decode(nested)
        if message is None:
            self.assertEqual(problem, "datagram is not JSON")

        def too_deep(text):
            raise RecursionError("maximum recursion depth exceeded while decoding a JSON array")

        original = protocol.json.loads
        protocol.json.loads = too_deep
        try:
            self.assertEqual(protocol.decode(b"[[[]]]"), (None, "datagram is not JSON"))
        finally:
            protocol.json.loads = original

    def test_huge_integers_are_not_numbers(self):
        self.assertFalse(protocol.is_number(10 ** 400))
        self.assertTrue(protocol.is_number(10 ** 300))
        self.assertFalse(protocol.is_number(float("inf")))
        self.assertEqual(protocol.clamp_hz(10 ** 400), 30)

    def test_hz_and_port_validation(self):
        self.assertEqual(protocol.clamp_hz(None), 30)
        self.assertEqual(protocol.clamp_hz(30), 30)
        self.assertEqual(protocol.clamp_hz(500), 60)
        self.assertEqual(protocol.clamp_hz(0), 1)
        self.assertEqual(protocol.clamp_hz(24.6), 25)
        self.assertEqual(protocol.clamp_hz(True), 30)
        self.assertEqual(protocol.clamp_hz(120, max_hz=10), 10)
        self.assertEqual(protocol.valid_port(47800), 47800)
        self.assertEqual(protocol.valid_port(0), 47800)
        self.assertEqual(protocol.valid_port(70000), 47800)
        self.assertEqual(protocol.valid_port("47900"), 47800)


class ChunkingTests(unittest.TestCase):
    def assert_parts_valid(self, parts, records, gen):
        self.assertTrue(parts)
        for index, part in enumerate(parts):
            data = protocol.encode(part)
            self.assertLessEqual(len(data), protocol.MAX_DATAGRAM_BYTES)
            self.assertLessEqual(len(part["items"]), protocol.MAX_TRACKS_PER_PART)
            self.assertEqual(part["part"], index)
            self.assertEqual(part["parts"], len(parts))
            self.assertEqual(part["total"], len(records))
            self.assertEqual(part["gen"], gen)
            self.assertEqual(list(part.keys()), ["v", "t", "gen", "part", "parts", "total", "items"])
        joined = [item for part in parts for item in part["items"]]
        self.assertEqual(joined, records)

    def test_short_names_pack_32_per_part(self):
        records = [make_record(i, "Track %d" % i) for i in range(200)]
        parts = protocol.tracks_parts(3, records)
        self.assert_parts_valid(parts, records, 3)
        self.assertEqual([len(p["items"]) for p in parts], [32] * 6 + [8])

    def test_long_unicode_names_and_200_tracks_stay_under_8192_bytes(self):
        chunk = "Lead Vox \U0001f3a4 ünïcødé 漢字 ✨ "
        records = []
        for i in range(200):
            name = (chunk * 60)[: protocol.MAX_NAME_CHARS - (i % 7)]
            records.append(make_record(i, name))
        parts = protocol.tracks_parts(12, records)
        self.assert_parts_valid(parts, records, 12)
        self.assertGreater(len(parts), 7)

    def test_worst_case_escaped_names_still_fit_one_per_datagram(self):
        name = "\u0001" * protocol.MAX_NAME_CHARS  # 6 bytes each once JSON-escaped
        records = [make_record(i, name) for i in range(5)]
        parts = protocol.tracks_parts(1, records)
        self.assert_parts_valid(parts, records, 1)
        single = protocol.encode(protocol.track(1, records[0]))
        self.assertLessEqual(len(single), protocol.MAX_DATAGRAM_BYTES)

    def test_empty_list_is_one_empty_part(self):
        parts = protocol.tracks_parts(1, [])
        self.assertEqual(len(parts), 1)
        self.assertEqual(parts[0]["items"], [])
        self.assertEqual((parts[0]["part"], parts[0]["parts"], parts[0]["total"]), (0, 1, 0))


class ShapeTests(unittest.TestCase):
    """Builders produce the shapes shown in docs/PROTOCOL.md."""

    def test_track_record_keys_match_the_doc_example(self):
        doc = protocol_doc()
        if doc is None:
            self.skipTest("docs/PROTOCOL.md not found")
        match = re.search(r'```json\n(\{"id": 140523312345.*?\})\n```', doc, re.S)
        self.assertIsNotNone(match)
        example = json.loads(match.group(1))
        self.assertEqual(tuple(example.keys()), RECORD_KEYS)

    def test_cmd_examples_from_the_doc_parse(self):
        doc = protocol_doc()
        if doc is None:
            self.skipTest("docs/PROTOCOL.md not found")
        lines = [line for line in doc.splitlines() if line.startswith('{"v":1,"t":"cmd"')]
        self.assertEqual(len(lines), 6)
        commands = []
        for line in lines:
            command, problem = parse_command(json.loads(line))
            self.assertIsNone(problem, line)
            commands.append(command)
        self.assertEqual([c.op for c in commands], ["select", "mute", "solo", "arm", "vol", "vol"])
        self.assertEqual([c.end for c in commands[4:]], [False, True])

    def test_sub_example_from_the_doc_carries_an_app_value(self):
        doc = protocol_doc()
        if doc is None:
            self.skipTest("docs/PROTOCOL.md not found")
        lines = [line for line in doc.splitlines() if line.startswith('{"v":1,"t":"sub"')]
        self.assertEqual(len(lines), 1)
        self.assertTrue(protocol.is_int(json.loads(lines[0])["app"]))

    def test_simple_messages_match_the_doc_examples(self):
        self.assertEqual(protocol.encode(protocol.heartbeat(77)), b'{"v":1,"t":"hb","seq":77}')
        self.assertEqual(protocol.encode(protocol.selection(140523312345)), b'{"v":1,"t":"sel","id":140523312345}')
        self.assertEqual(protocol.encode(protocol.selection(None)), b'{"v":1,"t":"sel","id":null}')
        self.assertEqual(
            protocol.encode(protocol.meters(5531, [[140523312345, 0.6123, 0.5871], [140523319999, 0.0, 0.0]])),
            b'{"v":1,"t":"m","seq":5531,"d":[[140523312345,0.6123,0.5871],[140523319999,0.0,0.0]]}',
        )
        self.assertEqual(
            protocol.encode(protocol.error("unknown track id 123 in cmd")),
            b'{"v":1,"t":"err","msg":"unknown track id 123 in cmd"}',
        )
        record = make_record(3, "Lead Vox")
        self.assertEqual(list(protocol.track(12, record).keys()), ["v", "t", "gen", "item"])

    def test_surfaces_shape(self):
        unit = {"slot": 1, "script": "MackieControl", "role": "main", "strips": [1, 2, 3, 4, 5, 6, 7, None]}
        message = protocol.surfaces([unit], None)
        self.assertEqual(
            protocol.encode(message),
            b'{"v":1,"t":"surfaces","units":[{"slot":1,"script":"MackieControl","role":"main",'
            b'"strips":[1,2,3,4,5,6,7,null]}],"warn":null}',
        )
        self.assertEqual(protocol.surfaces([], "x" * 2000)["warn"], "x" * protocol.MAX_TEXT_CHARS)

    def test_hello_shape(self):
        curve = {"x": [k / 100.0 for k in range(101)], "db": [None] + [-70.0 + k for k in range(100)]}
        message = protocol.hello(918273, "12.4.6", 30, curve)
        self.assertEqual(list(message.keys()), ["v", "t", "script", "live", "session", "hz", "vc"])
        self.assertEqual(message["script"], protocol.SCRIPT_VERSION)
        text = protocol.encode(message).decode("utf-8")
        self.assertTrue(text.startswith('{"v":1,"t":"hello","script":"0.1.0","live":"12.4.6","session":918273,"hz":30,'))
        self.assertIn('"vc":{"x":[0.0,0.01,', text)
        self.assertIn('"db":[null,-70.0,', text)


if __name__ == "__main__":
    unittest.main()
