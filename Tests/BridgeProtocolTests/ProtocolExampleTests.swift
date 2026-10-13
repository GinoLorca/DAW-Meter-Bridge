import Foundation
import Testing
@testable import BridgeProtocol
import MeterCore

/// Every example message in docs/PROTOCOL.md decodes to the expected values.
@Suite("PROTOCOL.md examples")
struct ProtocolExampleTests {
    static let trackRecord = """
        {"id": 140523312345, "i": 3, "n": "Lead Vox", "c": 16725558, "k": "audio",
         "m": false, "s": false, "a": false, "ms": false, "ao": true,
         "vol": 0.85, "vs": "0.0 dB"}
        """

    @Test func trackRecord() throws {
        let track = try JSONDecoder().decode(WireTrack.self, from: datagram(Self.trackRecord))
        #expect(track.id == TrackID(140_523_312_345))
        #expect(track.index == 3)
        #expect(track.name == "Lead Vox")
        #expect(track.color == 16_725_558)
        #expect(track.kind == .audio)
        #expect(!track.isMuted && !track.isSoloed && !track.isMutedViaSolo)
        #expect(track.isArmed == false)
        #expect(track.hasAudioOutput)
        #expect(track.volume == 0.85)
        #expect(track.volumeText == "0.0 dB")
    }

    @Test func hello() throws {
        let json = #"{"v":1,"t":"hello","script":"0.1.0","live":"12.4.6","session":918273,"hz":30,"vc":\#(helloCurveJSON())}"#
        guard case let .hello(hello) = try WireCodec.decodeIncoming(datagram(json)) else {
            Issue.record("not a hello")
            return
        }
        #expect(hello.script == "0.1.0")
        #expect(hello.live == "12.4.6")
        #expect(hello.session == 918_273)
        #expect(hello.hz == 30)
        let table = try #require(hello.vc)
        #expect(table.x.count == 101)
        #expect(table.db.count == 101)
        #expect(table.db.first == .some(nil))
        #expect(table.db[1] == -70.0)
        #expect(table.db.last == 6.0)
        let curve = try #require(hello.volumeCurve)
        #expect(curve.decibels(atNormalized: 0) == nil)
        #expect(curve.decibels(atNormalized: 1) == 6.0)
        #expect(abs((curve.decibels(atNormalized: 0.01) ?? 0) - -70) < 1e-9)
    }

    @Test func tracks() throws {
        let json = #"{"v":1,"t":"tracks","gen":12,"part":0,"parts":2,"total":40,"items":[\#(Self.trackRecord)]}"#
        guard case let .tracks(tracks) = try WireCodec.decodeIncoming(datagram(json)) else {
            Issue.record("not tracks")
            return
        }
        #expect(tracks.gen == 12)
        #expect(tracks.part == 0)
        #expect(tracks.parts == 2)
        #expect(tracks.total == 40)
        #expect(tracks.items.map(\.name) == ["Lead Vox"])
    }

    @Test func track() throws {
        let json = #"{"v":1,"t":"track","gen":12,"item":\#(Self.trackRecord)}"#
        guard case let .track(track) = try WireCodec.decodeIncoming(datagram(json)) else {
            Issue.record("not track")
            return
        }
        #expect(track.gen == 12)
        #expect(track.item.id == TrackID(140_523_312_345))
    }

    @Test func selection() throws {
        let selected = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"sel","id":140523312345}"#))
        #expect(selected == .selection(SelectionMessage(id: TrackID(140_523_312_345))))
        let none = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"sel","id":null}"#))
        #expect(none == .selection(SelectionMessage(id: nil)))
    }

    @Test func surfaces() throws {
        let json = """
            {"v":1,"t":"surfaces","units":[
              {"slot":1,"script":"MackieControl","role":"main","strips":[11,12,13,14,15,16,17,null]},
              {"slot":4,"script":"MackieControlXT","role":"xt","strips":[21,null,null,null,null,null,null,null]}
            ],"warn":null}
            """
        guard case let .surfaces(surfaces) = try WireCodec.decodeIncoming(datagram(json)) else {
            Issue.record("not surfaces")
            return
        }
        #expect(surfaces.warn == nil)
        let units = surfaces.surfaceUnits
        #expect(units.count == 2)
        #expect(units[0] == SurfaceUnit(
            slot: 1, scriptName: "MackieControl", role: .main,
            strips: [11, 12, 13, 14, 15, 16, 17].map { TrackID($0) } + [nil]
        ))
        #expect(units[1].role == .extender)
        #expect(units[1].slot == 4)
        #expect(units[1].strips == [TrackID(21)] + Array(repeating: nil, count: 7))
    }

    @Test func surfacesWithWarningAndNoUnits() throws {
        let json = #"{"v":1,"t":"surfaces","units":[],"warn":"MackieControl internals changed"}"#
        guard case let .surfaces(surfaces) = try WireCodec.decodeIncoming(datagram(json)) else {
            Issue.record("not surfaces")
            return
        }
        #expect(surfaces.units.isEmpty)
        #expect(surfaces.warn == "MackieControl internals changed")
    }

    @Test func meters() throws {
        let json = #"{"v":1,"t":"m","seq":5531,"d":[[140523312345,0.6123,0.5871],[140523319999,0.0,0.0]]}"#
        guard case let .meters(meters) = try WireCodec.decodeIncoming(datagram(json)) else {
            Issue.record("not meters")
            return
        }
        #expect(meters.seq == 5531)
        #expect(meters.levels == [
            MeterLevel(id: TrackID(140_523_312_345), left: 0.6123, right: 0.5871),
            MeterLevel(id: TrackID(140_523_319_999), left: 0, right: 0),
        ])
    }

    @Test func heartbeat() throws {
        #expect(try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"hb","seq":77}"#)) == .heartbeat(HeartbeatMessage(seq: 77)))
    }

    @Test func error() throws {
        let decoded = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"err","msg":"unknown track id 123 in cmd"}"#))
        #expect(decoded == .error(ErrorMessage(msg: "unknown track id 123 in cmd")))
    }

    @Test func subscribe() throws {
        let decoded = try WireCodec.decodeOutgoing(datagram(#"{"v":1,"t":"sub","port":47800,"hz":30}"#))
        #expect(decoded == .subscribe(SubscribeMessage(port: 47800, hz: 30)))
        let withApp = try WireCodec.decodeOutgoing(datagram(#"{"v":1,"t":"sub","port":47800,"hz":30,"app":1730591}"#))
        #expect(withApp == .subscribe(SubscribeMessage(port: 47800, hz: 30, app: 1_730_591)))
    }

    @Test func watch() throws {
        let decoded = try WireCodec.decodeOutgoing(datagram(#"{"v":1,"t":"watch","ids":[140523312345,140523319999]}"#))
        #expect(decoded == .watch(WatchMessage(ids: [TrackID(140_523_312_345), TrackID(140_523_319_999)])))
    }

    @Test(arguments: [
        (#"{"v":1,"t":"cmd","op":"select","id":140523312345}"#, BridgeCommand.select(TrackID(140_523_312_345))),
        (#"{"v":1,"t":"cmd","op":"mute","id":140523312345,"on":true}"#, .setMute(TrackID(140_523_312_345), true)),
        (#"{"v":1,"t":"cmd","op":"solo","id":140523312345,"on":true,"excl":null}"#, .setSolo(TrackID(140_523_312_345), true, exclusive: nil)),
        (#"{"v":1,"t":"cmd","op":"arm","id":140523312345,"on":true}"#, .setArm(TrackID(140_523_312_345), true)),
        (#"{"v":1,"t":"cmd","op":"arm","id":140523312345,"on":true,"excl":null}"#, .setArm(TrackID(140_523_312_345), true)),
        (#"{"v":1,"t":"cmd","op":"vol","id":140523312345,"val":0.8123}"#, .setVolume(TrackID(140_523_312_345), 0.8123)),
        (#"{"v":1,"t":"cmd","op":"vol","id":140523312345,"val":0.8001,"end":true}"#, .endVolumeDrag(TrackID(140_523_312_345), 0.8001)),
        (#"{"v":1,"t":"cmd","op":"vol","id":140523312345,"val":0.8001,"end":false}"#, .setVolume(TrackID(140_523_312_345), 0.8001)),
    ])
    func command(json: String, expected: BridgeCommand) throws {
        #expect(try WireCodec.decodeOutgoing(datagram(json)) == .command(CommandMessage(expected)))
    }

    @Test func exampleSessionDecodesInOrder() throws {
        let script: [String] = [
            #"{"v":1,"t":"hello","script":"0.1.0","live":"12.4.6","session":918273,"hz":30,"vc":\#(helloCurveJSON())}"#,
            #"{"v":1,"t":"tracks","gen":1,"part":0,"parts":1,"total":1,"items":[\#(Self.trackRecord)]}"#,
            #"{"v":1,"t":"sel","id":140523312345}"#,
            #"{"v":1,"t":"surfaces","units":[{"slot":1,"script":"MackieControl","role":"main","strips":[140523312345,null,null,null,null,null,null,null]}],"warn":null}"#,
            #"{"v":1,"t":"m","seq":1,"d":[[140523312345,0.5,0.4]]}"#,
            #"{"v":1,"t":"track","gen":1,"item":\#(Self.trackRecord.replacingOccurrences(of: "\"s\": false", with: "\"s\": true"))}"#,
        ]
        let types = try script.map { try WireCodec.decodeIncoming(datagram($0)).messageType }
        #expect(types == ["hello", "tracks", "sel", "surfaces", "m", "track"])
        guard case let .track(echo) = try WireCodec.decodeIncoming(datagram(script[5])) else {
            Issue.record("not track")
            return
        }
        #expect(echo.item.isSoloed)
    }
}
