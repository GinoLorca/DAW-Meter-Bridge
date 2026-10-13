import BridgeLayout
import CoreGraphics
import Foundation
import MeterCore
import Testing

@Suite struct StripBindingTests {
    @Test func surfaceUnitFollowsTheHardwareBank() {
        let snapshot = Fixtures.snapshot(unitCount: 1, bankOffset: 8)
        let tracks = StripBinding.surfaceUnit(index: 0, firstStrip: 0).resolve(stripCount: 8, in: snapshot)
        #expect(tracks == (8..<16).map { Fixtures.id($0) })
    }

    @Test func wingSectionsMapToTheirUnitsAndStrips() {
        let snapshot = Fixtures.snapshot(unitCount: 3)
        #expect(StripBinding.surfaceUnit(index: 1, firstStrip: 4).resolve(stripCount: 4, in: snapshot) == (12..<16).map { Fixtures.id($0) })
        #expect(StripBinding.surfaceUnit(index: 2, firstStrip: 4).resolve(stripCount: 4, in: snapshot) == (20..<24).map { Fixtures.id($0) })
    }

    @Test func stripsPastTheUnitAreEmpty() {
        let snapshot = Fixtures.snapshot(unitCount: 2)
        let tracks = StripBinding.surfaceUnit(index: 0, firstStrip: 6).resolve(stripCount: 4, in: snapshot)
        #expect(tracks == [Fixtures.id(6), Fixtures.id(7), nil, nil])
    }

    @Test func missingUnitResolvesToEmptyStrips() {
        let snapshot = Fixtures.snapshot(unitCount: 1)
        #expect(StripBinding.surfaceUnit(index: 2, firstStrip: 0).resolve(stripCount: 4, in: snapshot) == [nil, nil, nil, nil])
        #expect(StripBinding.surfaceUnit(index: -1, firstStrip: 0).resolve(stripCount: 2, in: snapshot) == [nil, nil])
    }

    @Test func emptyHardwareStripsStayEmpty() {
        // 10 tracks: the second unit shows tracks 8 and 9, then empty strips.
        let snapshot = Fixtures.snapshot(tracks: 10, unitCount: 2)
        let tracks = StripBinding.surfaceUnit(index: 1, firstStrip: 0).resolve(stripCount: 8, in: snapshot)
        #expect(tracks == [Fixtures.id(8), Fixtures.id(9), nil, nil, nil, nil, nil, nil])
    }

    @Test func withoutSurfacesUnitsFallBackToTheTrackList() {
        let snapshot = Fixtures.snapshot(tracks: 30, unitCount: 0)
        #expect(StripBinding.surfaceUnit(index: 0, firstStrip: 0).resolve(stripCount: 8, in: snapshot) == (0..<8).map { Fixtures.id($0) })
        // WING C1-4 = unit 1 strips 4-7 = tracks 12...15.
        #expect(StripBinding.surfaceUnit(index: 1, firstStrip: 4).resolve(stripCount: 4, in: snapshot) == (12..<16).map { Fixtures.id($0) })
        // Virtual units are 8 strips wide too.
        #expect(StripBinding.surfaceUnit(index: 0, firstStrip: 6).resolve(stripCount: 4, in: snapshot) == [Fixtures.id(6), Fixtures.id(7), nil, nil])
        // Past the end of the list. Index 30 is the main track, then nothing.
        #expect(StripBinding.surfaceUnit(index: 3, firstStrip: 4).resolve(stripCount: 4, in: snapshot) == [Fixtures.id(28), Fixtures.id(29), TrackID(9999), nil])
    }

    @Test func hugeOffsetsAndUnitsResolveToEmptyStripsInsteadOfTrapping() {
        let noSurface = Fixtures.snapshot(tracks: 10, unitCount: 0)
        let oneUnit = Fixtures.snapshot(tracks: 10, unitCount: 1)
        #expect(StripBinding.trackList(offset: Int.max - 1).resolve(stripCount: 8, in: noSurface) == Array(repeating: nil, count: 8))
        #expect(StripBinding.surfaceUnit(index: 2_000_000_000_000_000_000, firstStrip: 0).resolve(stripCount: 8, in: noSurface) == Array(repeating: nil, count: 8))
        #expect(StripBinding.surfaceUnit(index: 0, firstStrip: Int.max).resolve(stripCount: 3, in: noSurface) == [nil, nil, nil])
        #expect(StripBinding.surfaceUnit(index: 0, firstStrip: Int.max).resolve(stripCount: 3, in: oneUnit) == [nil, nil, nil])
    }

    @Test func selectedAndMainShowOneTrack() {
        let snapshot = Fixtures.snapshot(selected: Fixtures.id(3))
        #expect(StripBinding.selectedTrack.resolve(stripCount: 1, in: snapshot) == [Fixtures.id(3)])
        #expect(StripBinding.selectedTrack.resolve(stripCount: 3, in: snapshot) == [Fixtures.id(3), nil, nil])
        #expect(StripBinding.mainTrack.resolve(stripCount: 2, in: snapshot) == [TrackID(9999), nil])

        let nothingSelected = Fixtures.snapshot()
        #expect(StripBinding.selectedTrack.resolve(stripCount: 1, in: nothingSelected) == [nil])
        #expect(StripBinding.mainTrack.resolve(stripCount: 1, in: .empty) == [nil])
    }

    @Test func trackListShowsConsecutiveTracks() {
        let snapshot = Fixtures.snapshot(tracks: 4)
        #expect(StripBinding.trackList(offset: 2).resolve(stripCount: 4, in: snapshot) == [Fixtures.id(2), Fixtures.id(3), TrackID(9999), nil])
        #expect(StripBinding.trackList(offset: -1).resolve(stripCount: 2, in: snapshot) == [nil, Fixtures.id(0)])
    }

    @Test func zeroStripsResolveToNothing() {
        #expect(StripBinding.trackList(offset: 0).resolve(stripCount: 0, in: Fixtures.snapshot()).isEmpty)
        #expect(StripBinding.selectedTrack.resolve(stripCount: -3, in: Fixtures.snapshot()).isEmpty)
    }

    @Test func bindingProperties() {
        #expect(StripBinding.selectedTrack.isSingleTrack)
        #expect(!StripBinding.trackList(offset: 0).isSingleTrack)
        #expect(StripBinding.surfaceUnit(index: 1, firstStrip: 4).maximumStripCount == 4)
        #expect(StripBinding.mainTrack.maximumStripCount == 1)
        #expect(StripBinding.trackList(offset: 3).maximumStripCount == nil)
    }

    @Test(arguments: [
        StripBinding.surfaceUnit(index: 2, firstStrip: 4),
        .selectedTrack,
        .mainTrack,
        .trackList(offset: 16),
    ])
    func bindingRoundTripsThroughJSON(_ binding: StripBinding) throws {
        let data = try JSONEncoder().encode(binding)
        #expect(try JSONDecoder().decode(StripBinding.self, from: data) == binding)
    }

    @Test func bindingJSONShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(StripBinding.surfaceUnit(index: 1, firstStrip: 4)), as: UTF8.self)
        #expect(json == #"{"firstStrip":4,"type":"surfaceUnit","unit":1}"#)
        let decoded = try JSONDecoder().decode(StripBinding.self, from: Data(#"{"type":"trackList"}"#.utf8))
        #expect(decoded == .trackList(offset: 0))
        // An unknown type comes from a newer app version, not from a damaged file.
        #expect(throws: LayoutDocumentError.unknownValue("binding type “hologram”")) {
            try JSONDecoder().decode(StripBinding.self, from: Data(#"{"type":"hologram"}"#.utf8))
        }
    }

    @Test func watchListHoldsOnlyTracksTheDAWDoesNotAlreadyMeter() {
        let snapshot = Fixtures.snapshot(tracks: 32, unitCount: 1, selected: Fixtures.id(20))
        let groups = [
            StripGroup(name: "UF8", binding: .surfaceUnit(index: 0, firstStrip: 0), stripCount: 8, frame: .zero),
            StripGroup(name: "Focus", binding: .selectedTrack, stripCount: 1, frame: .zero),
            StripGroup(name: "Main", binding: .mainTrack, stripCount: 1, frame: .zero),
            // Tracks 6...9: 6 and 7 are on the surface, 8 and 9 are not.
            StripGroup(name: "Context", binding: .trackList(offset: 6), stripCount: 4, frame: .zero),
            StripGroup(name: "Hidden", binding: .trackList(offset: 24), stripCount: 2, frame: .zero, isVisible: false),
        ]
        #expect(groups.watchedTracks(in: snapshot) == [Fixtures.id(8), Fixtures.id(9)])
    }

    @Test func withoutSurfacesTheFallbackTracksAreWatched() {
        let snapshot = Fixtures.snapshot(tracks: 16, unitCount: 0)
        let uf8 = StripGroup(name: "UF8", binding: .surfaceUnit(index: 0, firstStrip: 0), stripCount: 8, frame: .zero)
        #expect([uf8].watchedTracks(in: snapshot) == Set((0..<8).map { Fixtures.id($0) }))
    }
}
