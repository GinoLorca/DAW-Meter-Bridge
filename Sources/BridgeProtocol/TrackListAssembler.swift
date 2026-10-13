import Foundation

/// Collects the parts of chunked `tracks` messages into complete lists.
///
/// Rules (docs/PROTOCOL.md): the list is replaced only when every part of a generation has
/// arrived; an incomplete generation is discarded after ``timeout`` seconds or as soon as a
/// newer generation starts. Parts may arrive in any order. Once a generation completes or is
/// discarded, late parts of it and of older generations are ignored. Call ``reset()`` when the
/// script's session changes, because a new script instance starts its generations again.
public struct TrackListAssembler: Sendable {
    /// Seconds after its first part arrived that an incomplete generation is discarded.
    public var timeout: TimeInterval

    /// Generation of the last complete list returned by ``add(_:at:)``.
    public private(set) var completedGeneration: Int?

    private var pending: Pending?
    /// Parts of generations at or below this are stale.
    private var floorGeneration: Int?

    private struct Pending: Sendable {
        var generation: Int
        var parts: Int
        var startedAt: TimeInterval
        var received: [Int: [WireTrack]]
    }

    /// An assembler that discards incomplete generations after `timeout` seconds (1 s in the protocol).
    public init(timeout: TimeInterval = 1) {
        self.timeout = timeout
    }

    /// Generation currently being collected, if any.
    public var pendingGeneration: Int? { pending?.generation }

    /// Adds one part received at `time` (any monotonic clock, in seconds).
    /// Returns the complete ordered list when this part completes its generation, otherwise `nil`.
    public mutating func add(_ message: TracksMessage, at time: TimeInterval) -> [WireTrack]? {
        expire(at: time)
        guard message.parts >= 1, message.part >= 0, message.part < message.parts else { return nil }
        if let floorGeneration, message.gen <= floorGeneration { return nil }

        if let current = pending {
            if message.gen < current.generation { return nil }
            if message.gen > current.generation {
                discardPending()
            } else if message.parts != current.parts {
                // Inconsistent part count within one generation: keep what we have, ignore this part.
                return nil
            }
        }
        if pending == nil {
            pending = Pending(generation: message.gen, parts: message.parts, startedAt: time, received: [:])
        }
        pending?.received[message.part] = message.items

        guard let complete = pending, complete.received.count == complete.parts else { return nil }
        let list = (0..<complete.parts).flatMap { complete.received[$0] ?? [] }
        pending = nil
        completedGeneration = complete.generation
        floorGeneration = complete.generation
        return list
    }

    /// Discards the incomplete generation if it is older than ``timeout`` at `time`.
    /// Returns true if one was discarded.
    @discardableResult
    public mutating func expire(at time: TimeInterval) -> Bool {
        guard let current = pending, time - current.startedAt > timeout else { return false }
        discardPending()
        return true
    }

    /// Forgets everything, e.g. when the script's session changes.
    public mutating func reset() {
        pending = nil
        floorGeneration = nil
        completedGeneration = nil
    }

    private mutating func discardPending() {
        guard let current = pending else { return }
        floorGeneration = max(floorGeneration ?? current.generation, current.generation)
        pending = nil
    }
}
