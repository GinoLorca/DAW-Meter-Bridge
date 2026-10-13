import MeterCore
import Testing

/// Lookup, replacement and derived state of `BridgeSnapshot`.
@Suite struct BridgeSnapshotTests {
    private let tracks = [
        makeTrack(10, index: 0, name: "Kick"),
        makeTrack(20, index: 1, name: "Bass"),
        makeTrack(30, index: 2, name: "Reverb", kind: .returnTrack, isArmed: nil),
        makeTrack(40, index: 3, name: "Main", kind: .main, isArmed: nil),
    ]

    @Test func emptySnapshotHasNothing() {
        let empty = BridgeSnapshot.empty
        #expect(empty.tracks.isEmpty)
        #expect(empty.selected == nil)
        #expect(empty.units.isEmpty)
        #expect(empty.connection == .idle)
        #expect(empty.warnings.isEmpty)
        #expect(empty.volumeCurve == nil)
        #expect(empty.mainTrack == nil)
        #expect(!empty.anySoloed)
        #expect(empty.track(TrackID(10)) == nil)
    }

    @Test func looksUpTracksByID() {
        let snapshot = BridgeSnapshot(tracks: tracks)
        for track in tracks {
            #expect(snapshot.track(track.id) == track)
            #expect(snapshot.contains(track.id))
        }
    }

    @Test func lookupOfNilOrUnknownIDIsNil() {
        let snapshot = BridgeSnapshot(tracks: tracks)
        #expect(snapshot.track(nil) == nil)
        #expect(snapshot.track(TrackID(99)) == nil)
        #expect(!snapshot.contains(TrackID(99)))
    }

    @Test func keepsDAWOrder() {
        let snapshot = BridgeSnapshot(tracks: tracks)
        #expect(snapshot.tracks.map(\.id) == tracks.map(\.id))
    }

    @Test func setTracksReplacesListAndReindexes() {
        var snapshot = BridgeSnapshot(tracks: tracks)
        let reordered = [
            makeTrack(30, index: 0, name: "Reverb", kind: .returnTrack, isArmed: nil),
            makeTrack(50, index: 1, name: "Keys"),
            makeTrack(10, index: 2, name: "Kick (moved)"),
        ]
        snapshot.setTracks(reordered)

        #expect(snapshot.tracks == reordered)
        #expect(snapshot.track(TrackID(10))?.name == "Kick (moved)")
        #expect(snapshot.track(TrackID(30))?.index == 0)
        #expect(snapshot.track(TrackID(50))?.name == "Keys")
        #expect(snapshot.track(TrackID(20)) == nil)
        #expect(!snapshot.contains(TrackID(40)))
        #expect(snapshot.mainTrack == nil)
    }

    @Test func setTracksToEmptyClearsLookup() {
        var snapshot = BridgeSnapshot(tracks: tracks)
        snapshot.setTracks([])
        #expect(snapshot.tracks.isEmpty)
        #expect(snapshot.track(TrackID(10)) == nil)
    }

    @Test func setTracksMatchesBuildingFromScratch() {
        var snapshot = BridgeSnapshot(tracks: [makeTrack(1)])
        snapshot.setTracks(tracks)
        #expect(snapshot == BridgeSnapshot(tracks: tracks))
    }

    @Test func updateTrackReplacesKnownRecordInPlace() {
        var snapshot = BridgeSnapshot(tracks: tracks)
        var bass = tracks[1]
        bass.isMuted = true
        bass.volume = 0.5
        bass.volumeText = "-14.0 dB"

        let updated = snapshot.updateTrack(bass)
        #expect(updated)
        #expect(snapshot.track(bass.id) == bass)
        #expect(snapshot.tracks[1] == bass)
        #expect(snapshot.tracks.map(\.id) == tracks.map(\.id))
        #expect(snapshot.track(TrackID(10)) == tracks[0])
    }

    @Test func updateTrackWithUnknownIDIsIgnored() {
        var snapshot = BridgeSnapshot(tracks: tracks, selected: TrackID(20))
        let before = snapshot
        let updated = snapshot.updateTrack(makeTrack(99, name: "Stranger"))
        #expect(!updated)
        #expect(snapshot == before)
        #expect(snapshot.track(TrackID(99)) == nil)
    }

    @Test func updateTrackOnEmptySnapshotIsIgnored() {
        var snapshot = BridgeSnapshot.empty
        let updated = snapshot.updateTrack(makeTrack(1))
        #expect(!updated)
        #expect(snapshot.tracks.isEmpty)
    }

    @Test func anySoloedFollowsTrackState() {
        var snapshot = BridgeSnapshot(tracks: tracks)
        #expect(!snapshot.anySoloed)

        var reverb = tracks[2]
        reverb.isSoloed = true
        snapshot.updateTrack(reverb)
        #expect(snapshot.anySoloed)

        reverb.isSoloed = false
        snapshot.updateTrack(reverb)
        #expect(!snapshot.anySoloed)
    }

    @Test func mainTrackIsTheMainKind() {
        let snapshot = BridgeSnapshot(tracks: tracks)
        #expect(snapshot.mainTrack?.id == TrackID(40))
        #expect(snapshot.mainTrack?.kind == .main)
    }

    @Test func mainTrackIsNilWithoutOne() {
        let snapshot = BridgeSnapshot(tracks: Array(tracks.prefix(3)))
        #expect(snapshot.mainTrack == nil)
    }

    @Test func initializerKeepsAllFields() {
        let unit = SurfaceUnit(slot: 1, scriptName: "MackieControl", role: .main, strips: [TrackID(10), nil])
        let snapshot = BridgeSnapshot(
            tracks: tracks,
            selected: TrackID(20),
            units: [unit],
            connection: .connected,
            warnings: ["surface introspection failed"],
            volumeCurve: .liveApproximation
        )
        #expect(snapshot.selected == TrackID(20))
        #expect(snapshot.units == [unit])
        #expect(snapshot.connection.isConnected)
        #expect(snapshot.warnings == ["surface introspection failed"])
        #expect(snapshot.volumeCurve == .liveApproximation)
    }
}

@Suite struct ConnectionStateTests {
    @Test(arguments: [
        (ConnectionState.idle, false),
        (.connecting, false),
        (.connected, true),
        (.disconnected(reason: "no heartbeat for 3 s"), false),
    ])
    func isConnectedOnlyWhenConnected(state: ConnectionState, expected: Bool) {
        #expect(state.isConnected == expected)
    }
}

@Suite struct SurfaceUnitTests {
    @Test func roleRawValuesMatchProtocol() {
        #expect(SurfaceUnit.Role.main.rawValue == "main")
        #expect(SurfaceUnit.Role.extender.rawValue == "xt")
        #expect(SurfaceUnit.Role(rawValue: "xt") == .extender)
    }

    @Test func keepsStripsInOrderIncludingEmptyOnes() {
        let strips: [TrackID?] = [TrackID(1), TrackID(2), nil, TrackID(4), nil, nil, nil, TrackID(8)]
        let unit = SurfaceUnit(slot: 4, scriptName: "MackieControlXT", role: .extender, strips: strips)
        #expect(unit.slot == 4)
        #expect(unit.scriptName == "MackieControlXT")
        #expect(unit.role == .extender)
        #expect(unit.strips == strips)
    }
}
