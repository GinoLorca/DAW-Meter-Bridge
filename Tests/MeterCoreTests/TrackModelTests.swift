import Foundation
import MeterCore
import Testing

/// `TrackID` travels as a bare JSON integer (Live's `_live_ptr`), per docs/PROTOCOL.md.
@Suite struct TrackIDCodingTests {
    private struct Wrapper: Codable, Equatable {
        var id: TrackID
    }

    @Test func encodesAsBareInteger() throws {
        let data = try JSONEncoder().encode(TrackID(140_523_312_345))
        #expect(String(decoding: data, as: UTF8.self) == "140523312345")
    }

    @Test func decodesFromBareInteger() throws {
        let id = try JSONDecoder().decode(TrackID.self, from: Data("140523312345".utf8))
        #expect(id == TrackID(140_523_312_345))
    }

    @Test(arguments: [Int64(0), 1, -1, 140_523_312_345, Int64.max, Int64.min])
    func roundTripsExactly(raw: Int64) throws {
        let data = try JSONEncoder().encode(TrackID(raw))
        let decoded = try JSONDecoder().decode(TrackID.self, from: data)
        #expect(decoded == TrackID(raw))
        #expect(decoded.rawValue == raw)
    }

    @Test func decodesAsAFieldOfAWireObject() throws {
        let json = #"{"id":140523312345}"#
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        #expect(decoded == Wrapper(id: TrackID(140_523_312_345)))
        let encoded = try JSONEncoder().encode(decoded)
        #expect(String(decoding: encoded, as: UTF8.self) == json)
    }

    @Test func decodesSurfaceStripArrayWithNulls() throws {
        let strips = try JSONDecoder().decode([TrackID?].self, from: Data("[11,null,33]".utf8))
        #expect(strips == [TrackID(11), nil, TrackID(33)])
    }

    @Test(arguments: [#""12""#, "1.5", #"{"rawValue":12}"#, "null", "true"])
    func rejectsAnythingButAnInteger(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TrackID.self, from: Data(json.utf8))
        }
    }

    @Test func comparesByRawValue() {
        let ids = [TrackID(3), TrackID(-1), TrackID(2)]
        #expect(ids.sorted() == [TrackID(-1), TrackID(2), TrackID(3)])
        #expect(TrackID(1) < TrackID(2))
        #expect(!(TrackID(2) < TrackID(2)))
    }

    @Test func describesItself() {
        #expect(TrackID(42).description == "track#42")
        #expect("\(TrackID(7))" == "track#7")
    }
}

/// `RGBColor` mirrors Live's `0xRRGGBB` colour integers.
@Suite struct RGBColorTests {
    @Test func splitsHexIntoChannels() {
        // 16725558 is the colour in the PROTOCOL.md track example.
        let color = RGBColor(hex: 16_725_558)
        #expect(color == RGBColor(red: 0xFF, green: 0x36, blue: 0x36))
    }

    @Test func joinsChannelsIntoHex() {
        #expect(RGBColor(red: 0x12, green: 0x34, blue: 0x56).hex == 0x123456)
        #expect(RGBColor(red: 0, green: 0, blue: 0).hex == 0)
        #expect(RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF).hex == 0xFFFFFF)
    }

    @Test(arguments: [0x000000, 0xFFFFFF, 0x123456, 0xFF3636, 0x00FF00, 0x0000FF, 0xFF0000, 0x010203])
    func hexRoundTrips(hex: Int) {
        #expect(RGBColor(hex: hex).hex == hex)
    }

    @Test(arguments: [RGBColor(red: 1, green: 2, blue: 3), RGBColor(red: 255, green: 0, blue: 128)])
    func channelsRoundTripThroughHex(color: RGBColor) {
        #expect(RGBColor(hex: color.hex) == color)
    }

    @Test func ignoresBitsAboveTwentyFour() {
        #expect(RGBColor(hex: 0x7F_123456) == RGBColor(hex: 0x123456))
        #expect(RGBColor(hex: 0x7F_123456).hex == 0x123456)
    }
}

/// `TrackKind` raw values are the protocol's `k` strings.
@Suite struct TrackKindTests {
    @Test(arguments: [
        (TrackKind.audio, "audio"),
        (.midi, "midi"),
        (.group, "group"),
        (.returnTrack, "return"),
        (.main, "main"),
    ])
    func rawValueMatchesProtocol(kind: TrackKind, wire: String) throws {
        #expect(kind.rawValue == wire)
        let decoded = try JSONDecoder().decode(TrackKind.self, from: Data("\"\(wire)\"".utf8))
        #expect(decoded == kind)
    }

    @Test func coversExactlyTheProtocolKinds() {
        #expect(Set(TrackKind.allCases.map(\.rawValue)) == ["audio", "midi", "group", "return", "main"])
    }
}

/// Capability flags and defaults of `TrackInfo`.
@Suite struct TrackInfoTests {
    @Test func defaultsDescribeAPlainAudioTrackAtUnity() {
        let track = TrackInfo(id: TrackID(1), index: 0, name: "Kick")
        #expect(track.kind == .audio)
        #expect(track.color == nil)
        #expect(!track.isMuted)
        #expect(!track.isSoloed)
        #expect(track.isArmed == false)
        #expect(!track.isMutedViaSolo)
        #expect(track.hasAudioOutput)
        #expect(track.volume == 0.85)
        #expect(track.volumeText == "0.0 dB")
    }

    @Test(arguments: [TrackKind.audio, .midi, .group, .returnTrack])
    func nonMainTracksCanMuteAndSolo(kind: TrackKind) {
        let track = makeTrack(1, kind: kind, isArmed: nil)
        #expect(track.canMute)
        #expect(track.canSolo)
    }

    @Test func mainTrackCannotMuteOrSolo() {
        let main = makeTrack(1, kind: .main, isArmed: nil)
        #expect(!main.canMute)
        #expect(!main.canSolo)
    }

    @Test(arguments: [TrackKind.group, .returnTrack, .main])
    func trackWithoutArmStateCannotArm(kind: TrackKind) {
        #expect(!makeTrack(1, kind: kind, isArmed: nil).canArm)
    }

    @Test(arguments: [TrackKind.audio, .midi], [false, true])
    func audioAndMIDITracksWithArmStateCanArm(kind: TrackKind, armed: Bool) {
        #expect(makeTrack(1, kind: kind, isArmed: armed).canArm)
    }

    /// The doc comment promises "arm exists only on audio/MIDI tracks". A group, return or main
    /// track built with the initializer's defaults (`isArmed: false`) must not claim it can arm.
    @Test(arguments: [TrackKind.group, .returnTrack, .main])
    func onlyAudioAndMIDITracksCanArm(kind: TrackKind) {
        let track = TrackInfo(id: TrackID(1), index: 0, name: "Bus", kind: kind)
        #expect(!track.canArm)
    }
}
