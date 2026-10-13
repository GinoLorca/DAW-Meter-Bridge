import AppKit

/// Calls a frame handler on every refresh of the display a view is on, and idles when told nothing moves.
///
/// The handler returns true while anything is still moving or lit (e.g. `MeterStore.advance(to:)`); on false the
/// link pauses until `wake()` (call it when new meters or state arrive). Times are
/// `ProcessInfo.processInfo.systemUptime`, the clock `MeterStore` uses.
@MainActor
public final class DisplayLinkDriver: NSObject {
    /// Called once per frame with the current time. Return false to pause until `wake()`.
    public typealias FrameHandler = @MainActor (_ time: TimeInterval) -> Bool

    private weak var view: NSView?
    private let onFrame: FrameHandler
    private var link: CADisplayLink?

    /// `view` picks the display (and follows it when its window moves to another screen).
    public init(view: NSView, onFrame: @escaping FrameHandler) {
        self.view = view
        self.onFrame = onFrame
        super.init()
    }

    /// True while the link exists and is not paused.
    public var isRunning: Bool { link.map { !$0.isPaused } ?? false }

    /// Creates the link and starts calling the handler.
    public func start() {
        guard link == nil, let view else { return }
        let newLink = view.displayLink(target: self, selector: #selector(tick(_:)))
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    /// Stops and releases the link (the link retains this driver until then).
    public func stop() {
        link?.invalidate()
        link = nil
    }

    /// Resumes after an idle pause, or starts if not started.
    public func wake() {
        if let link {
            link.isPaused = false
        } else {
            start()
        }
    }

    @objc private func tick(_ sender: CADisplayLink) {
        if !onFrame(ProcessInfo.processInfo.systemUptime) {
            sender.isPaused = true
        }
    }
}
