import Foundation
import MeterCore
import Testing

private let kick = TrackID(1)
private let bass = TrackID(2)
private let keys = TrackID(3)

private extension MeterStore {
    func ingest(_ id: TrackID, _ left: Float, _ right: Float? = nil, at time: TimeInterval) {
        ingest([MeterLevel(id: id, left: left, right: right ?? left)], at: time)
    }

    /// Runs the display link at 60 fps from `start` until `advance` reports idle or `limit` passes.
    /// Returns the time of the first idle frame, or nil if it never went idle.
    func runUntilIdle(from start: TimeInterval, limit: TimeInterval) -> TimeInterval? {
        var time = start
        while time < limit {
            time += 1.0 / 60
            if !advance(to: time) { return time }
        }
        return nil
    }
}

/// Per-track readings plus ballistics, driven by an injected clock.
@MainActor
@Suite struct MeterStoreTests {
    @Test func unknownOrNilTrackIsSilent() {
        let store = MeterStore()
        #expect(store.state(for: kick) == .silent)
        #expect(store.state(for: nil) == .silent)
    }

    @Test func ingestKeepsChannelsAndArrivalTime() {
        let store = MeterStore()
        store.ingest([MeterLevel(id: kick, left: 0.3, right: 0.6)], at: 12.5)
        let state = store.state(for: kick)
        #expect(state.left.bar == 0.3)
        #expect(state.right.bar == 0.6)
        #expect(state.lastUpdate == 12.5)
        #expect(state.maxSinceReset == 0.6)
    }

    @Test func ingestKeepsTracksApart() {
        let store = MeterStore()
        store.ingest(
            [MeterLevel(id: kick, left: 0.3, right: 0.3), MeterLevel(id: bass, left: 0.8, right: 0.7)],
            at: 0
        )
        #expect(store.state(for: kick).left.bar == 0.3)
        #expect(store.state(for: bass).left.bar == 0.8)
        #expect(store.state(for: bass).right.bar == 0.7)
        #expect(store.state(for: keys) == .silent)
    }

    @Test func clipUsesTheStoreCalibration() {
        let store = MeterStore(calibration: MeterCalibration(clipValue: 0.9))
        store.ingest([MeterLevel(id: kick, left: 0.92, right: 0.5)], at: 0)
        let state = store.state(for: kick)
        #expect(state.left.clipped)
        #expect(!state.right.clipped)
        #expect(state.clipped)
    }

    @Test func advanceWithNoTracksIsIdle() {
        let store = MeterStore()
        #expect(!store.advance(to: 0))
        #expect(!store.advance(to: 1))
    }

    @Test func barFallsAtSettingsRate() {
        let store = MeterStore(settings: BallisticsSettings(barFallPerSecond: 3))
        store.ingest(kick, 1.0, at: 0)
        store.ingest(kick, 0.0, at: 0)
        store.advance(to: 0)
        store.advance(to: 0.1)
        #expect(isClose(store.state(for: kick).left.bar, 0.7))
        #expect(isClose(store.state(for: kick).right.bar, 0.7))
    }

    @Test func settingsChangesApplyOnTheNextFrame() {
        let store = MeterStore()
        store.ingest(kick, 1.0, at: 0)
        store.ingest(kick, 0.0, at: 0)
        store.advance(to: 0)
        store.settings.barFallPerSecond = 3
        store.advance(to: 0.1)
        #expect(isClose(store.state(for: kick).left.bar, 0.7))
    }

    @Test func firstFrameDoesNotMove() {
        let store = MeterStore()
        store.ingest(kick, 1.0, at: 0)
        store.ingest(kick, 0.0, at: 0)
        store.advance(to: 0.2)
        #expect(store.state(for: kick).left.bar == 1.0)
        store.advance(to: 0.3)
        #expect(isClose(store.state(for: kick).left.bar, 0.85))
    }

    @Test func longGapsAreClampedToAQuarterSecond() {
        let store = MeterStore()
        store.ingest(kick, 1.0, at: 0)
        store.ingest(kick, 0.0, at: 0)
        store.advance(to: 0)
        // 0.4 s since the last frame, but the step is clamped to 0.25 s: 1 - 1.5 * 0.25.
        store.advance(to: 0.4)
        #expect(isClose(store.state(for: kick).left.bar, 0.625))
    }

    @Test func timeGoingBackwardsMovesNothing() {
        let store = MeterStore()
        store.ingest(kick, 1.0, at: 0)
        store.ingest(kick, 0.0, at: 0)
        store.advance(to: 0)
        store.advance(to: 0.1)
        let before = store.state(for: kick)
        store.advance(to: 0.05)
        #expect(store.state(for: kick) == before)
    }

    @Test func freshReadingsHoldTheirLevel() {
        let store = MeterStore()
        store.ingest(kick, 0.8, at: 0)
        store.advance(to: 0)
        store.advance(to: 0.25)
        store.advance(to: 0.45)
        let state = store.state(for: kick)
        #expect(state.left.target == 0.8)
        #expect(state.left.bar == 0.8)
    }

    @Test func staleReadingsFallTowardSilence() {
        let store = MeterStore()
        store.ingest(kick, 0.8, at: 0)
        store.advance(to: 0)
        store.advance(to: 0.45)
        // 0.65 s after the last reading (> staleAfter 0.5): target drops to 0, bar falls 1.5 * 0.2.
        store.advance(to: 0.65)
        let state = store.state(for: kick)
        #expect(state.left.target == 0)
        #expect(state.right.target == 0)
        #expect(isClose(state.left.bar, 0.5))
        #expect(state.left.peak == 0.8)
    }

    @Test func staleAfterIsConfigurable() {
        let store = MeterStore()
        store.staleAfter = 2
        store.ingest(kick, 0.8, at: 0)
        store.advance(to: 0)
        store.advance(to: 0.25)
        store.advance(to: 0.5)
        store.advance(to: 0.75)
        store.advance(to: 1.0)
        #expect(store.state(for: kick).left.bar == 0.8)
        store.advance(to: 2.25)
        #expect(store.state(for: kick).left.target == 0)
    }

    @Test func staleTrackDecaysToSilenceAndTheStoreGoesIdle() throws {
        let store = MeterStore()
        store.ingest(kick, 0.8, at: 0)
        #expect(store.advance(to: 0))

        // Peak holds to 1.5 s, then falls 0.8 at 0.4/s: idle at about 3.5 s.
        let idleAt = try #require(store.runUntilIdle(from: 0, limit: 10))
        #expect(idleAt > 3.4 && idleAt < 3.6)

        let state = store.state(for: kick)
        let floor = store.settings.silenceFloor
        #expect(state.left.bar == 0 && state.right.bar == 0)
        #expect(state.left.peak <= floor && state.right.peak <= floor)
        #expect(state.left.target == 0 && state.right.target == 0)
        #expect(!store.advance(to: idleAt + 1))
    }

    @Test func steadySignalKeepsTheStoreActive() {
        let store = MeterStore()
        var time = 0.0
        store.advance(to: time)
        for _ in 0..<120 {
            time += 1.0 / 60
            store.ingest(kick, 0.5, at: time)
            #expect(store.advance(to: time))
        }
    }

    @Test func silentReadingsKeepTheStoreIdle() {
        let store = MeterStore()
        store.ingest(kick, 0, at: 0)
        store.ingest(bass, 0, at: 0)
        #expect(!store.advance(to: 0))
        #expect(!store.advance(to: 1.0 / 60))
    }

    @Test func oneActiveTrackKeepsTheStoreActive() {
        let store = MeterStore()
        store.ingest(kick, 0, at: 0)
        store.ingest(bass, 0, 0.3, at: 0)
        #expect(store.advance(to: 0))
    }

    @Test func retainDropsOtherTracks() {
        let store = MeterStore()
        store.ingest([
            MeterLevel(id: kick, left: 0.5, right: 0.5),
            MeterLevel(id: bass, left: 0.6, right: 0.6),
            MeterLevel(id: keys, left: 0.7, right: 0.7),
        ], at: 0)
        store.retain(only: [kick, keys])
        #expect(store.state(for: kick).left.bar == 0.5)
        #expect(store.state(for: bass) == .silent)
        #expect(store.state(for: keys).left.bar == 0.7)
    }

    @Test func retainNothingDropsEverything() {
        let store = MeterStore()
        store.ingest(kick, 0.5, at: 0)
        store.retain(only: [])
        #expect(store.state(for: kick) == .silent)
        #expect(!store.advance(to: 0))
    }

    @Test func resetPeaksAffectsOnlyThatTrack() {
        let store = MeterStore()
        store.ingest(kick, 1.0, at: 0)
        store.ingest(bass, 1.0, at: 0)
        store.ingest(kick, 0.2, at: 0.1)
        store.ingest(bass, 0.2, at: 0.1)

        store.resetPeaks(for: kick)
        #expect(!store.state(for: kick).clipped)
        #expect(store.state(for: kick).maxSinceReset == 0.2)
        #expect(store.state(for: bass).clipped)
        #expect(store.state(for: bass).maxSinceReset == 1.0)

        store.resetPeaks(for: keys)
        #expect(store.state(for: keys) == .silent)
    }

    @Test func resetAllPeaksClearsEveryTrack() {
        let store = MeterStore()
        store.ingest(kick, 1.0, at: 0)
        store.ingest(bass, 1.0, 0.4, at: 0)
        store.resetAllPeaks()
        #expect(!store.state(for: kick).clipped)
        #expect(!store.state(for: bass).clipped)
        #expect(store.state(for: bass).right.maxSinceReset == 0.4)
    }

    @Test func removeAllDropsTracksAndRestartsTheClock() {
        let store = MeterStore()
        store.ingest(kick, 0.5, at: 0)
        store.advance(to: 0)
        store.advance(to: 0.1)

        store.removeAll()
        #expect(store.state(for: kick) == .silent)

        // The first frame after removeAll has no previous frame, so it must not move.
        store.ingest(kick, 1.0, at: 5)
        store.ingest(kick, 0.0, at: 5)
        store.advance(to: 5.1)
        #expect(store.state(for: kick).left.bar == 1.0)
    }
}
