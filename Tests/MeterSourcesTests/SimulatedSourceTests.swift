import Foundation
import MeterCore
@testable import MeterSources
import Testing

@Suite("SimulatedSource")
@MainActor
struct SimulatedSourceTests {
    func track(_ source: SimulatedSource, _ name: String) throws -> TrackInfo {
        try #require(source.snapshot.tracks.first { $0.name == name }, "no track \(name)")
    }

    // MARK: Session

    @Test func sessionLooksLikeALiveSet() throws {
        let source = SimulatedSource()
        let tracks = source.snapshot.tracks
        #expect(tracks.count == 35)
        #expect(tracks.filter { $0.kind != .returnTrack && $0.kind != .main }.count == 32)
        #expect(tracks.filter { $0.kind == .returnTrack }.map(\.name) == ["A Reverb", "B Delay"])
        #expect(tracks.last?.kind == .main)
        #expect(tracks.last?.name == "Main")
        #expect(tracks.map(\.index) == Array(0..<35))
        #expect(Set(tracks.map(\.id)).count == 35)
        #expect(tracks.allSatisfy { $0.id.rawValue > Int64(UInt32.max) })
        for name in ["Kick", "Snare", "Hats", "Bass", "Lead Vox", "BGV L", "Pad", "Keys", "Gtr L", "FX Riser"] {
            _ = try track(source, name)
        }
        #expect(tracks.allSatisfy { $0.color != nil })
        // Live's arm rules: only audio and MIDI tracks can be armed.
        for track in tracks {
            #expect((track.isArmed != nil) == (track.kind == .audio || track.kind == .midi))
        }
        #expect(Set(tracks.map(\.kind)) == Set(TrackKind.allCases))
        let curve = try #require(source.snapshot.volumeCurve)
        #expect(tracks.allSatisfy { $0.volumeText == curve.text(atNormalized: $0.volume) })
        #expect(source.snapshot.connection == .idle)
        #expect(source.snapshot.selected == (try track(source, "Lead Vox")).id)
        #expect(source.displayName == "Simulator")
    }

    // MARK: Commands

    @Test func soloIsExclusiveByDefaultAndAdditiveOnRequest() throws {
        let source = SimulatedSource()
        let kick = try track(source, "Kick").id
        let bass = try track(source, "Bass").id
        let keys = try track(source, "Keys").id
        let reverb = try track(source, "A Reverb").id

        source.send(.setSolo(kick, true, exclusive: nil))
        source.send(.setSolo(bass, true, exclusive: nil))
        #expect(try track(source, "Kick").isSoloed == false)
        #expect(try track(source, "Bass").isSoloed == true)

        source.send(.setSolo(keys, true, exclusive: false))
        #expect(try track(source, "Bass").isSoloed && track(source, "Keys").isSoloed)

        source.send(.setSolo(reverb, true, exclusive: false))
        source.send(.setSolo(kick, true, exclusive: true))
        let soloed = source.snapshot.tracks.filter(\.isSoloed).map(\.name)
        #expect(soloed == ["Kick"]) // exclusive also clears returns

        source.send(.setSolo(kick, false, exclusive: nil))
        #expect(!source.snapshot.anySoloed)
        #expect(source.snapshot.tracks.allSatisfy { !$0.isMutedViaSolo })
    }

    @Test func mutedViaSoloFollowsLiveRules() throws {
        let source = SimulatedSource()
        source.send(.setSolo(try track(source, "Kick").id, true, exclusive: nil))
        #expect(try track(source, "Kick").isMutedViaSolo == false)
        #expect(try track(source, "Drums").isMutedViaSolo == false) // the soloed track's group
        #expect(try track(source, "Snare").isMutedViaSolo == true) // a sibling
        #expect(try track(source, "Bass").isMutedViaSolo == true)
        #expect(try track(source, "A Reverb").isMutedViaSolo == false) // returns: never
        #expect(try track(source, "Main").isMutedViaSolo == false)

        source.send(.setSolo(try track(source, "Vox").id, true, exclusive: nil))
        #expect(try track(source, "Lead Vox").isMutedViaSolo == false) // children of a soloed group
        #expect(try track(source, "BGV R").isMutedViaSolo == false)
        #expect(try track(source, "Kick").isMutedViaSolo == true)
        #expect(try track(source, "Drums").isMutedViaSolo == true)

        source.send(.setSolo(try track(source, "B Delay").id, true, exclusive: nil))
        #expect(try track(source, "B Delay").isMutedViaSolo == false)
        #expect(try track(source, "A Reverb").isMutedViaSolo == false)
        #expect(try track(source, "Lead Vox").isMutedViaSolo == true)
    }

    @Test func mainCannotBeMutedOrSoloedAndArmOnlyWhereLiveAllowsIt() throws {
        let source = SimulatedSource()
        let main = try track(source, "Main").id
        source.send(.setMute(main, true))
        source.send(.setSolo(main, true, exclusive: nil))
        #expect(try track(source, "Main").isMuted == false)
        #expect(try track(source, "Main").isSoloed == false)

        for name in ["Drums", "A Reverb", "Main"] {
            source.send(.setArm(try track(source, name).id, true))
            #expect(try track(source, name).isArmed == nil)
        }
        source.send(.setArm(try track(source, "Lead Vox").id, true))
        source.send(.setArm(try track(source, "Keys").id, true))
        #expect(try track(source, "Lead Vox").isArmed == true)
        #expect(try track(source, "Keys").isArmed == true)

        source.send(.setMute(try track(source, "A Reverb").id, true))
        #expect(try track(source, "A Reverb").isMuted)
    }

    @Test func selectAndVolume() throws {
        let source = SimulatedSource()
        let pad = try track(source, "Pad").id
        source.send(.select(pad))
        #expect(source.snapshot.selected == pad)
        source.send(.select(TrackID(1))) // unknown: ignored
        #expect(source.snapshot.selected == pad)

        source.send(.setVolume(pad, 0.85))
        #expect(try track(source, "Pad").volumeText == "0.0 dB")
        source.send(.setVolume(pad, 1.4))
        #expect(try track(source, "Pad").volume == 1)
        #expect(try track(source, "Pad").volumeText == "6.0 dB")
        source.send(.setVolume(pad, -1))
        #expect(try track(source, "Pad").volumeText == "-inf dB")
        source.send(.setVolume(pad, .nan))
        #expect(try track(source, "Pad").volume == 0)
        source.send(.setVolume(pad, 0.7))
        #expect(try track(source, "Pad").volumeText == VolumeCurve.liveApproximation.text(atNormalized: 0.7))
        // The end of a drag sets the volume the same way.
        source.send(.endVolumeDrag(pad, 0.85))
        #expect(try track(source, "Pad").volume == 0.85)
        #expect(try track(source, "Pad").volumeText == "0.0 dB")
    }

    @Test func commandsNotifyTheDelegate() throws {
        let source = SimulatedSource()
        let delegate = RecordingDelegate()
        source.delegate = delegate
        source.send(.setMute(try track(source, "Kick").id, true))
        #expect(delegate.snapshots.count == 1)
        #expect(delegate.lastSnapshot?.track(try track(source, "Kick").id)?.isMuted == true)
        source.send(.setMute(try track(source, "Kick").id, true)) // no change, no update
        #expect(delegate.snapshots.count == 1)
    }

    // MARK: Virtual surface

    @Test func bankingStepsByAllStripsLikeMackieControl() throws {
        let source = SimulatedSource(unitCount: 1)
        let visible = source.snapshot.tracks.filter { $0.kind != .returnTrack && $0.kind != .main }.map(\.id)
        #expect(source.snapshot.units.count == 1)
        #expect(source.snapshot.units[0].strips == Array(visible[0..<8]))
        #expect(source.snapshot.units[0].role == .main)
        #expect(source.snapshot.units[0].scriptName == "MackieControl")
        source.bankRight()
        #expect(source.bankOffset == 8)
        #expect(source.snapshot.units[0].strips == Array(visible[8..<16]))
        source.bankRight()
        source.bankRight()
        #expect(source.bankOffset == 24)
        source.bankRight() // 32 would pass the last track
        #expect(source.bankOffset == 24)
        source.bankLeft()
        #expect(source.bankOffset == 16)

        source.setUnitCount(3) // WING: MCU + 2 XT
        #expect(source.unitCount == 3)
        let units = source.snapshot.units
        #expect(units.map(\.slot) == [1, 2, 3])
        #expect(units.map(\.role) == [.main, .extender, .extender])
        #expect(units.map(\.scriptName) == ["MackieControl", "MackieControlXT", "MackieControlXT"])
        #expect(units.flatMap(\.strips) == Array(visible[16..<32]) + Array(repeating: nil, count: 8))
        source.bankLeft()
        #expect(source.bankOffset == 0)
        source.bankRight()
        #expect(source.bankOffset == 24)
        #expect(source.snapshot.units[0].strips == Array(visible[24..<32]))
        #expect(source.snapshot.units[1].strips.allSatisfy { $0 == nil })
        source.bankRight()
        #expect(source.bankOffset == 24)

        source.setUnitCount(0)
        #expect(source.unitCount == 1)
        source.setUnitCount(99)
        #expect(source.unitCount == 7)
    }

    // MARK: Meters

    @Test func sameSeedSameMeters() {
        let a = SimulatedSource(seed: 7)
        let b = SimulatedSource(seed: 7)
        for _ in 0..<60 {
            #expect(a.advance(by: 1.0 / 30) == b.advance(by: 1.0 / 30))
        }
    }

    @Test func meteredTracksAreStripsSelectionMainAndWatched() throws {
        let source = SimulatedSource()
        let delegate = RecordingDelegate()
        source.delegate = delegate
        let strips = Set(source.snapshot.units.flatMap(\.strips).compactMap { $0 })
        let main = try track(source, "Main").id
        let vox = try track(source, "Lead Vox").id
        #expect(Set(source.advance(by: 0.03).map(\.id)) == strips.union([main, vox]))
        #expect(delegate.meterBatches.count == 1)

        let pad = try track(source, "Pad").id
        source.setWatchedTracks([pad])
        #expect(source.advance(by: 0.03).map(\.id).contains(pad))
        source.setWatchedTracks([])
        // A track that leaves the set is sent once more with zeros, then dropped.
        let leaving = source.advance(by: 0.03)
        #expect(leaving.contains(MeterLevel(id: pad, left: 0, right: 0)))
        #expect(!source.advance(by: 0.03).map(\.id).contains(pad))

        source.metersAllTracks = true
        #expect(source.advance(by: 0.03).count == 35)
    }

    /// Levels of one track over `seconds` at 30 Hz.
    func levels(_ source: SimulatedSource, _ name: String, seconds: Double) throws -> [Float] {
        source.metersAllTracks = true
        let id = try track(source, name).id
        return (0..<Int(seconds * 30)).map { _ in
            let level = source.advance(by: 1.0 / 30).first { $0.id == id }
            return max(level?.left ?? 0, level?.right ?? 0)
        }
    }

    @Test func startsAtTheChorusEntrySoEveryDrumOnTheFirstBankMoves() throws {
        let source = SimulatedSource(tempo: 120)
        #expect(source.beatPosition == SimulatedSource.chorusEntryBeat)
        #expect(SimulatedMusic.section(ofBar: Int(SimulatedSource.chorusEntryBeat / 4) + 1) == .chorus)
        let firstBank = source.snapshot.units[0].strips.compactMap { $0 }
        let names = try firstBank.map { id in try #require(source.snapshot.track(id)).name }
        #expect(names == ["Drums", "Kick", "Snare", "Clap", "Hats", "Open Hat", "Toms", "Overheads"])
        // Within the first second (the tom fill, the chorus downbeat, its first off-beat and backbeat)
        // every one of them moves.
        var peaks: [TrackID: Float] = [:]
        for _ in 0..<33 {
            for level in source.advance(by: 1.0 / 30) where firstBank.contains(level.id) {
                peaks[level.id] = max(peaks[level.id] ?? 0, level.left, level.right)
            }
        }
        for (id, name) in zip(firstBank, names) {
            #expect((peaks[id] ?? 0) > 0.3, "\(name) is silent in the first 1.1 s: \(peaks[id] ?? 0)")
        }
        // The intro start is still available.
        #expect(SimulatedSource(startBeat: 0).beatPosition == 0)
    }

    @Test func kickPulsesOnTheBeat() throws {
        let source = SimulatedSource(tempo: 120, startBeat: 0)
        source.metersAllTracks = true
        let kick = try track(source, "Kick").id
        // Jump into the verse (bar 4) and sample on and between beats.
        source.advance(by: 16 * 0.5)
        var onBeat: [Float] = []
        var between: [Float] = []
        for _ in 0..<16 {
            onBeat.append(source.advance(by: 0.01).first { $0.id == kick }?.left ?? 0)
            between.append(source.advance(by: 0.24).first { $0.id == kick }?.left ?? 0)
            source.advance(by: 0.25)
        }
        #expect(onBeat.allSatisfy { $0 > 0.6 })
        #expect(between.allSatisfy { $0 < 0.25 })
    }

    @Test func tempoSetsTheBeatRate() {
        let source = SimulatedSource(tempo: 60)
        let start = source.beatPosition
        source.advance(by: 2)
        #expect(abs(source.beatPosition - start - 2) < 1e-9)
        source.setTempo(180)
        source.advance(by: 1)
        #expect(abs(source.beatPosition - start - 5) < 1e-9)
        source.setTempo(1000)
        #expect(source.tempo == 240)
    }

    @Test func mutedAndSoloMutedTracksAreSilentButReturnsKeepSounding() throws {
        let source = SimulatedSource(startBeat: 0)
        source.send(.setMute(try track(source, "Pad").id, true))
        #expect(try levels(source, "Pad", seconds: 4).allSatisfy { $0 == 0 })

        source.send(.setSolo(try track(source, "Lead Vox").id, true, exclusive: nil))
        source.advance(by: 32 * 0.5) // into the chorus
        let reverb = try levels(source, "A Reverb", seconds: 4)
        let delay = try levels(source, "B Delay", seconds: 4)
        let vox = try levels(source, "Lead Vox", seconds: 4)
        let kick = try levels(source, "Kick", seconds: 4)
        #expect(kick.allSatisfy { $0 == 0 })
        #expect(vox.contains { $0 > 0.3 })
        #expect(reverb.contains { $0 > 0.1 })
        #expect(delay.contains { $0 > 0.1 })
        #expect(try levels(source, "Main", seconds: 2).contains { $0 > 0.1 })
    }

    @Test func metersArePostFader() throws {
        let loud = SimulatedSource(seed: 3)
        let quiet = SimulatedSource(seed: 3)
        let silent = SimulatedSource(seed: 3)
        quiet.send(.setVolume(try track(quiet, "Bass").id, 0.55)) // about -12 dB
        silent.send(.setVolume(try track(silent, "Bass").id, 0))
        for source in [loud, quiet, silent] { source.advance(by: 10) }
        let a = try levels(loud, "Bass", seconds: 4)
        let b = try levels(quiet, "Bass", seconds: 4)
        let c = try levels(silent, "Bass", seconds: 4)
        #expect(a.max()! > 0.5)
        #expect(c.allSatisfy { $0 == 0 })
        let gain = pow(10, (VolumeCurve.liveApproximation.decibels(atNormalized: 0.55)! - VolumeCurve.liveApproximation.decibels(atNormalized: 0.84)!) / 20)
        for (loudLevel, quietLevel) in zip(a, b) where loudLevel > 0.05 {
            #expect(abs(Double(quietLevel) - Double(loudLevel) * gain) < 0.002)
        }
    }

    // MARK: Lifecycle

    @Test func startRunsATimerOnTheMainRunLoop() async throws {
        let source = SimulatedSource()
        let delegate = RecordingDelegate()
        source.delegate = delegate
        source.start()
        #expect(source.isRunning)
        #expect(source.snapshot.connection == .connected)
        #expect(await waitUntil(timeout: 10) { delegate.meterBatches.count >= 3 })
        source.stop()
        #expect(!source.isRunning)
        #expect(source.snapshot.connection == .idle)
        let count = delegate.meterBatches.count
        try? await Task.sleep(for: .milliseconds(100))
        #expect(delegate.meterBatches.count == count)
    }
}
