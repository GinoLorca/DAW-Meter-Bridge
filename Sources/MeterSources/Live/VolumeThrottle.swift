import Foundation
import MeterCore

/// Limits volume commands per track during a drag: at most one per `minInterval`, the latest
/// value wins, and the final value is always sent (by a deferred flush).
struct VolumeThrottle: Sendable {
    enum Decision: Hashable, Sendable {
        /// Send this value now.
        case sendNow
        /// Hold the value; call ``VolumeThrottle/flush(_:at:)`` at this time.
        case flushAt(TimeInterval)
        /// A flush is already scheduled; it will send this newer value.
        case coalesced
    }

    let minInterval: TimeInterval
    private var lastSent: [TrackID: TimeInterval] = [:]
    private var pending: [TrackID: Double] = [:]

    init(maxPerSecond: Double) {
        minInterval = maxPerSecond > 0 ? 1 / maxPerSecond : 0
    }

    mutating func submit(_ value: Double, for id: TrackID, at time: TimeInterval) -> Decision {
        if pending[id] != nil {
            pending[id] = value
            return .coalesced
        }
        if let last = lastSent[id], time - last < minInterval {
            pending[id] = value
            return .flushAt(last + minInterval)
        }
        lastSent[id] = time
        return .sendNow
    }

    /// The value to send for a scheduled flush, or nil if there is none.
    mutating func flush(_ id: TrackID, at time: TimeInterval) -> Double? {
        guard let value = pending.removeValue(forKey: id) else { return nil }
        lastSent[id] = time
        return value
    }

    mutating func reset() {
        lastSent.removeAll()
        pending.removeAll()
    }
}
