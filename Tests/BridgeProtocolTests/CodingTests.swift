import Foundation
import Testing
@testable import BridgeProtocol
import MeterCore

/// Ids above 2^53 lose precision through Double; these must survive exactly.
let bigIDs: [TrackID] = [
    TrackID(9_007_199_254_740_993), // 2^53 + 1
    TrackID(0x7FFF_FFFF_FFFF_FFFE),
    TrackID(Int64.max),
    TrackID(140_523_312_345),
]

func sampleTrack(_ id: TrackID, index: Int = 0, name: String = "Lead Vox") -> WireTrack {
    WireTrack(
        id: id, index: index, name: name, color: 0x5CFFE8, kind: .audio,
        isMuted: false, isSoloed: true, isArmed: false, isMutedViaSolo: false,
        hasAudioOutput: true, volume: 0.7, volumeText: "-6.0 dB"
    )
}

@Suite("Decoding rules")
struct DecodingRuleTests {
    @Test func unknownFieldsAreIgnored() throws {
        let json = #"{"v":1,"t":"hb","seq":3,"future":{"a":[1,2]},"x":null}"#
        #expect(try WireCodec.decodeIncoming(datagram(json)) == .heartbeat(HeartbeatMessage(seq: 3)))
        let track = #"{"id":5,"i":0,"n":"A","c":null,"k":"audio","m":false,"s":false,"a":null,"ms":false,"ao":true,"vol":0.5,"vs":"-12.0 dB","new":1}"#
        let decoded = try JSONDecoder().decode(WireTrack.self, from: datagram(track))
        #expect(decoded.color == nil)
        #expect(decoded.isArmed == nil)
    }

    @Test func unknownTypeIsReportedNotRejected() throws {
        #expect(try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"tempo","bpm":120}"#)) == .unknown(type: "tempo"))
        #expect(try WireCodec.decodeOutgoing(datagram(#"{"v":1,"t":"ping"}"#)) == .unknown(type: "ping"))
    }

    @Test func otherVersionsAreRejected() {
        #expect(throws: BridgeProtocolError.unsupportedVersion(2)) {
            try WireCodec.decodeIncoming(datagram(#"{"v":2,"t":"hb","seq":1}"#))
        }
        #expect(throws: BridgeProtocolError.unsupportedVersion(0)) {
            try WireCodec.decodeIncoming(datagram(#"{"v":0,"t":"hb","seq":1}"#))
        }
        #expect(throws: BridgeProtocolError.unsupportedVersion(nil)) {
            try WireCodec.decodeIncoming(datagram(#"{"t":"hb","seq":1}"#))
        }
        #expect(throws: BridgeProtocolError.unsupportedVersion(2)) {
            try WireCodec.decodeOutgoing(datagram(#"{"v":2,"t":"sub","port":1,"hz":30}"#))
        }
    }

    @Test func malformedInputThrowsMalformed() {
        let bad = [
            "not json",
            "[1,2,3]",
            #"{"v":1}"#,
            #"{"v":1,"t":"hb"}"#,
            #"{"v":1,"t":"m","seq":1,"d":[[1,0.5]]}"#,
            #"{"v":1,"t":"cmd","op":"explode","id":1}"#,
            #"{"v":1,"t":"cmd","op":"mute","id":1}"#,
            #"{"v":1,"t":"sel","id":12345678901234567890}"#,
        ]
        for json in bad {
            do {
                _ = try WireCodec.decodeIncoming(datagram(json))
                if json.contains("\"cmd\"") { _ = try WireCodec.decodeOutgoing(datagram(json)) }
                Issue.record("decoded malformed input: \(json)")
            } catch let error {
                guard case .malformed = error else {
                    Issue.record("expected malformed for \(json), got \(error)")
                    continue
                }
            }
        }
    }

    @Test func unknownTrackKindFallsBackToAudio() throws {
        let json = #"{"id":5,"i":0,"n":"A","c":null,"k":"hologram","m":false,"s":false,"a":null,"ms":false,"ao":true,"vol":0.5,"vs":"x"}"#
        #expect(try JSONDecoder().decode(WireTrack.self, from: datagram(json)).kind == .audio)
    }

    @Test func idsAbove2To53DecodeExactly() throws {
        for id in bigIDs {
            let raw = id.rawValue
            let sel = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"sel","id":\#(raw)}"#))
            #expect(sel == .selection(SelectionMessage(id: id)))
            let meters = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"m","seq":1,"d":[[\#(raw),0.1,0.2]]}"#))
            #expect(meters == .meters(MetersMessage(seq: 1, entries: [WireMeter(id: id, left: 0.1, right: 0.2)])))
            let watch = try WireCodec.decodeOutgoing(datagram(#"{"v":1,"t":"watch","ids":[\#(raw)]}"#))
            #expect(watch == .watch(WatchMessage(ids: [id])))
        }
        // Neighbours of 2^53 + 1 must stay distinct (they collapse through Double).
        let a = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"sel","id":9007199254740992}"#))
        let b = try WireCodec.decodeIncoming(datagram(#"{"v":1,"t":"sel","id":9007199254740993}"#))
        #expect(a != b)
    }
}

@Suite("Encoding")
struct EncodingTests {
    @Test func outgoingMessagesAreCompactAndExact() throws {
        let sub = String(decoding: try WireCodec.encode(SubscribeMessage(port: 47800, hz: 30)), as: UTF8.self)
        #expect(sub == #"{"hz":30,"port":47800,"t":"sub","v":1}"#)
        let subWithApp = String(decoding: try WireCodec.encode(SubscribeMessage(port: 47800, hz: 30, app: 1_730_591)), as: UTF8.self)
        #expect(subWithApp == #"{"app":1730591,"hz":30,"port":47800,"t":"sub","v":1}"#)

        let watch = String(decoding: try WireCodec.encode(WatchMessage(ids: [TrackID(140_523_312_345), TrackID(Int64.max)])), as: UTF8.self)
        #expect(watch == #"{"ids":[140523312345,9223372036854775807],"t":"watch","v":1}"#)

        let id = TrackID(140_523_312_345)
        let expected: [(BridgeCommand, String)] = [
            (.select(id), #"{"id":140523312345,"op":"select","t":"cmd","v":1}"#),
            (.setMute(id, true), #"{"id":140523312345,"on":true,"op":"mute","t":"cmd","v":1}"#),
            (.setSolo(id, true, exclusive: nil), #"{"excl":null,"id":140523312345,"on":true,"op":"solo","t":"cmd","v":1}"#),
            (.setSolo(id, false, exclusive: false), #"{"excl":false,"id":140523312345,"on":false,"op":"solo","t":"cmd","v":1}"#),
            (.setSolo(id, true, exclusive: true), #"{"excl":true,"id":140523312345,"on":true,"op":"solo","t":"cmd","v":1}"#),
            (.setArm(id, false), #"{"id":140523312345,"on":false,"op":"arm","t":"cmd","v":1}"#),
            (.setVolume(id, 0.8123), #"{"id":140523312345,"op":"vol","t":"cmd","v":1,"val":0.8123}"#),
            (.endVolumeDrag(id, 0.8001), #"{"end":true,"id":140523312345,"op":"vol","t":"cmd","v":1,"val":0.8001}"#),
        ]
        for (command, json) in expected {
            #expect(String(decoding: try WireCodec.encode(.command(CommandMessage(command))), as: UTF8.self) == json)
        }
    }

    @Test func volumeIsClampedAndFinite() throws {
        let id = TrackID(1)
        for (input, wire) in [(1.7, 1.0), (-0.2, 0.0), (Double.nan, 0.0), (Double.infinity, 1.0), (0.123456789, 0.123457)] {
            let data = try WireCodec.encode(CommandMessage(.setVolume(id, input)))
            #expect(try jsonObject(data)["val"] as? Double == wire)
        }
    }

    @Test func nullsAreWrittenExplicitly() throws {
        let sel = try jsonObject(try WireCodec.encode(SelectionMessage(id: nil)))
        #expect(sel["id"] is NSNull)

        let surfaces = try jsonObject(try WireCodec.encode(SurfacesMessage(units: [
            WireSurfaceUnit(slot: 1, script: "MackieControl", role: "main", strips: [TrackID(1), nil]),
        ], warn: nil)))
        #expect(surfaces["warn"] is NSNull)
        let unit = try #require((surfaces["units"] as? [[String: Any]])?.first)
        #expect((unit["strips"] as? [Any])?.last is NSNull)

        var track = sampleTrack(TrackID(1))
        track.color = nil
        track.isArmed = nil
        let tracks = try jsonObject(try WireCodec.encode(TracksMessage(gen: 1, part: 0, parts: 1, total: 1, items: [track])))
        let item = try #require((tracks["items"] as? [[String: Any]])?.first)
        #expect(item["c"] is NSNull)
        #expect(item["a"] is NSNull)
        #expect(Set(item.keys) == ["id", "i", "n", "c", "k", "m", "s", "a", "ms", "ao", "vol", "vs"])

        let hello = try jsonObject(try WireCodec.encode(HelloMessage(
            script: "0.1.0", live: "12.4.6", session: 1, hz: 30,
            vc: VolumeCurveTable(sampling: .liveApproximation)
        )))
        let db = try #require((hello["vc"] as? [String: Any])?["db"] as? [Any])
        #expect(db.count == 101)
        #expect(db.first is NSNull)
    }

    @Test func everyMessageCarriesVersionAndType() throws {
        let messages: [IncomingMessage] = [
            .hello(HelloMessage(script: "s", live: "l", session: 7, hz: 30, vc: nil)),
            .tracks(TracksMessage(gen: 1, part: 0, parts: 1, total: 0, items: [])),
            .track(TrackMessage(gen: 1, item: sampleTrack(TrackID(1)))),
            .selection(SelectionMessage(id: TrackID(1))),
            .surfaces(SurfacesMessage(units: [])),
            .meters(MetersMessage(seq: 1, entries: [])),
            .heartbeat(HeartbeatMessage(seq: 1)),
            .error(ErrorMessage(msg: "x")),
        ]
        for message in messages {
            let object = try jsonObject(try WireCodec.encode(message))
            #expect(object["v"] as? Int == 1)
            #expect(object["t"] as? String == message.messageType)
        }
    }

    @Test func unknownMessagesCannotBeEncoded() {
        #expect(throws: BridgeProtocolError.self) { try WireCodec.encode(IncomingMessage.unknown(type: "x")) }
        #expect(throws: BridgeProtocolError.self) { try WireCodec.encode(OutgoingMessage.unknown(type: "x")) }
    }
}

@Suite("Round trips")
struct RoundTripTests {
    static let incoming: [IncomingMessage] = [
        .hello(HelloMessage(script: "0.1.0", live: "12.4.6", session: 918_273, hz: 30, vc: VolumeCurveTable(sampling: .liveApproximation))),
        .hello(HelloMessage(script: "0.1.0", live: "11.3.42", session: Int64.max, hz: 25, vc: nil)),
        .tracks(TracksMessage(gen: 12, part: 1, parts: 2, total: 5, items: bigIDs.enumerated().map { sampleTrack($1, index: $0, name: "Track \($0) / ünï") })),
        .track(TrackMessage(gen: 12, item: sampleTrack(bigIDs[0]))),
        .selection(SelectionMessage(id: bigIDs[2])),
        .selection(SelectionMessage(id: nil)),
        .surfaces(SurfacesMessage(units: [
            WireSurfaceUnit(slot: 1, script: "MackieControl", role: "main", strips: bigIDs + [nil, nil, nil, nil]),
            WireSurfaceUnit(slot: 2, script: "MackieControlXT", role: "xt", strips: Array(repeating: nil, count: 8)),
        ], warn: "renamed attribute")),
        .meters(MetersMessage(seq: 5531, entries: bigIDs.map { WireMeter(id: $0, left: 0.6123, right: 0.5871) })),
        .heartbeat(HeartbeatMessage(seq: 77)),
        .error(ErrorMessage(msg: "unknown track id 123 in cmd")),
    ]

    @Test(arguments: incoming)
    func incomingRoundTrip(_ message: IncomingMessage) throws {
        let data = try WireCodec.encode(message)
        #expect(try WireCodec.decodeIncoming(data) == message)
    }

    static let outgoing: [OutgoingMessage] = [
        .subscribe(SubscribeMessage(port: 47800, hz: 30)),
        .subscribe(SubscribeMessage(port: 65535, hz: 60)),
        .subscribe(SubscribeMessage(port: 47800, hz: 30, app: Int(Int32.max))),
        .watch(WatchMessage(ids: bigIDs)),
        .watch(WatchMessage(ids: [])),
    ] + bigIDs.flatMap { id -> [OutgoingMessage] in
        [
            .command(CommandMessage(.select(id))),
            .command(CommandMessage(.setMute(id, true))),
            .command(CommandMessage(.setMute(id, false))),
            .command(CommandMessage(.setSolo(id, true, exclusive: nil))),
            .command(CommandMessage(.setSolo(id, true, exclusive: true))),
            .command(CommandMessage(.setSolo(id, false, exclusive: false))),
            .command(CommandMessage(.setArm(id, true))),
            .command(CommandMessage(.setVolume(id, 0.8123))),
            .command(CommandMessage(.setVolume(id, 0))),
            .command(CommandMessage(.setVolume(id, 1))),
            .command(CommandMessage(.endVolumeDrag(id, 0.5))),
            .command(CommandMessage(.endVolumeDrag(id, 0))),
        ]
    }

    @Test(arguments: outgoing)
    func outgoingRoundTrip(_ message: OutgoingMessage) throws {
        let data = try WireCodec.encode(message)
        #expect(try WireCodec.decodeOutgoing(data) == message)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(" ") && !text.contains("\n"), "not compact: \(text)")
    }
}
