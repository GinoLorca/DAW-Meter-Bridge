import AppKit
import BridgeLayout

/// Lies over a panel's bank in edit mode and shows a resize cursor over the group's edge bands and a hand
/// inside (see `EditMath.handle(at:groupSize:)`). It never takes clicks; they reach the bank and, through
/// it, the layout editor.
final class EditCursorView: NSView {
    /// The group's rect inside the panel (the bank view's frame).
    var groupRect: CGRect = .zero
    /// Set while a drag is in progress so the hand closes.
    var isDragging = false {
        didSet { if isDragging != oldValue { updateCursor(at: lastPoint) } }
    }

    private var lastPoint: CGPoint?

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    override func mouseExited(with event: NSEvent) {
        lastPoint = nil
        if !isDragging { NSCursor.arrow.set() }
    }

    /// The cursor for a point in this view's coordinates.
    func cursor(at point: CGPoint) -> NSCursor {
        let local = CGPoint(x: point.x - groupRect.minX, y: point.y - groupRect.minY)
        switch EditMath.handle(at: local, groupSize: groupRect.size) {
        case .edge(.left), .edge(.right): return .resizeLeftRight
        case .edge(.top), .edge(.bottom): return .resizeUpDown
        case .body: return isDragging ? .closedHand : .openHand
        }
    }

    private func updateCursor(at point: CGPoint?) {
        lastPoint = point
        guard let point else { return }
        cursor(at: point).set()
    }
}
