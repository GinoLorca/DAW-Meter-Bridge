import Foundation

/// Latest meter readings plus their ballistics, per track.
/// Sources push readings in with `ingest`; the renderer calls `advance` once per display frame and reads `state(for:)`.
@MainActor
public final class MeterStore {
    public var settings: BallisticsSettings
    public var calibration: MeterCalibration

    private var states: [TrackID: StripMeterState] = [:]
    private var lastAdvance: TimeInterval?
    /// Readings older than this are treated as silence (the DAW stopped sending a track).
    public var staleAfter: TimeInterval = 0.5

    public init(settings: BallisticsSettings = .standard, calibration: MeterCalibration = .uncalibrated) {
        self.settings = settings
        self.calibration = calibration
    }

    public func ingest(_ levels: [MeterLevel], at time: TimeInterval) {
        for level in levels {
            var state = states[level.id] ?? StripMeterState()
            state.left.ingest(level.left, at: time, clipValue: calibration.clipValue, settings: settings)
            state.right.ingest(level.right, at: time, clipValue: calibration.clipValue, settings: settings)
            state.lastUpdate = time
            states[level.id] = state
        }
    }

    /// Advances all ballistics to `time`. Returns true while any meter is still moving or lit,
    /// so the display link can idle when everything is silent.
    @discardableResult
    public func advance(to time: TimeInterval) -> Bool {
        let dt = lastAdvance.map { min(max(time - $0, 0), 0.25) } ?? 0
        lastAdvance = time
        var anyActive = false
        for (id, var state) in states {
            if time - state.lastUpdate > staleAfter {
                state.left.target = 0
                state.right.target = 0
            }
            let leftActive = state.left.advance(by: dt, to: time, settings: settings)
            let rightActive = state.right.advance(by: dt, to: time, settings: settings)
            anyActive = anyActive || leftActive || rightActive
            states[id] = state
        }
        return anyActive
    }

    public func state(for id: TrackID?) -> StripMeterState {
        guard let id else { return .silent }
        return states[id] ?? .silent
    }

    public func resetPeaks(for id: TrackID) {
        states[id]?.left.resetPeaks()
        states[id]?.right.resetPeaks()
    }

    public func resetAllPeaks() {
        for id in states.keys { resetPeaks(for: id) }
    }

    /// Drops tracks that no longer exist.
    public func retain(only ids: Set<TrackID>) {
        states = states.filter { ids.contains($0.key) }
    }

    public func removeAll() {
        states.removeAll()
        lastAdvance = nil
    }
}
