import Foundation
import MeterCore

/// Advances the shared `MeterStore` once per display frame, however many panels (and display links)
/// draw that frame.
@MainActor
final class FrameClock {
    /// Ticks closer together than this belong to the same frame (panels on one display fire together;
    /// a 120 Hz frame is 8.3 ms).
    static let sameFrameWindow: TimeInterval = 0.004

    private var lastTime: TimeInterval?
    private var lastActive = false

    /// Advances `store` to `time` unless that already happened this frame. Returns whether any meter
    /// is still moving or lit.
    func advance(_ store: MeterStore, to time: TimeInterval) -> Bool {
        if let lastTime, time >= lastTime, time - lastTime < Self.sameFrameWindow {
            return lastActive
        }
        lastTime = time
        lastActive = store.advance(to: time)
        return lastActive
    }

    /// Forgets the last frame (after the store was cleared).
    func reset() {
        lastTime = nil
        lastActive = false
    }
}
