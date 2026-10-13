import CoreGraphics

/// Turns a vertical mouse drag on a meter into a normalized volume.
///
/// `value = start + (upward travel / meter height) × (Shift ? 0.1 : 1.0)`, clamped to 0...1.
/// Nothing happens until the pointer has moved `startThreshold` points vertically, so a click stays a click;
/// the drag is then anchored where it crossed the threshold, so that movement never changes the volume.
/// When Shift is pressed or released mid-drag the start is re-anchored at the current value, so the value
/// never jumps.
///
/// The travel is accumulated per event rather than measured from the press point, so a pointer pinned at
/// the bottom of the screen (where the bridge usually sits) can keep pulling a fader down: pass the
/// event's own movement as `pointerDeltaUp`; it is used for events where the pointer's position did not
/// move vertically (held at the screen edge), and the position change is used otherwise.
public struct VolumeDrag: Hashable, Sendable {
    /// Vertical movement in points before a press becomes a drag.
    public static let startThreshold: CGFloat = 4
    /// Sensitivity multiplier while Shift is held.
    public static let fineScale: Double = 0.1
    /// Vertical position change below which the pointer counts as held at a screen edge.
    static let pinnedTolerance: CGFloat = 0.01

    /// The volume when the drag (or its latest re-anchor) began.
    public private(set) var anchorValue: Double
    /// Upward travel in points since the anchor (or, before dragging, since mouse-down).
    public private(set) var travel: CGFloat = 0
    /// Pointer position at mouse-down.
    public let startPoint: CGPoint
    /// Meter height in points: dragging this far moves the full range (a tenth of it with Shift).
    public let meterHeight: CGFloat
    /// True once the pointer passed the threshold.
    public private(set) var isDragging = false
    /// Latest value (the start value until dragging begins).
    public private(set) var value: Double

    private var lastY: CGFloat
    private var fine = false

    public init(startValue: Double, startPoint: CGPoint, meterHeight: CGFloat) {
        let start = VolumeDrag.clamp(startValue)
        anchorValue = start
        self.startPoint = startPoint
        self.meterHeight = meterHeight
        value = start
        lastY = startPoint.y
    }

    /// The pure drag formula. `upwardDistance` is positive when the pointer moved up.
    public static func value(startValue: Double, upwardDistance: CGFloat, meterHeight: CGFloat, fine: Bool) -> Double {
        guard meterHeight > 0, upwardDistance.isFinite else { return clamp(startValue) }
        let delta = Double(upwardDistance / meterHeight) * (fine ? fineScale : 1)
        return clamp(startValue + delta)
    }

    /// Feeds a pointer position (view points, y up). Returns the new value once dragging, nil below the threshold.
    ///
    /// `pointerDeltaUp` is the device's upward movement for this event (`-NSEvent.deltaY`), which keeps
    /// arriving while the pointer is held at a screen edge; it is used only when the position did not
    /// move vertically, so ordinary drags follow the pointer exactly.
    public mutating func update(to point: CGPoint, fine: Bool, pointerDeltaUp: CGFloat? = nil) -> Double? {
        let moved = point.y - lastY
        lastY = point.y
        var step = moved.isFinite ? moved : 0
        if abs(step) < VolumeDrag.pinnedTolerance, let device = pointerDeltaUp, device.isFinite { step = device }
        travel += step
        if !isDragging {
            guard abs(travel) >= VolumeDrag.startThreshold else { return nil }
            // The threshold only tells a drag from a click: start from here, at the unchanged value.
            isDragging = true
            self.fine = fine
            travel = 0
            return value
        }
        if fine != self.fine {
            anchorValue = value
            travel = step
            self.fine = fine
        }
        value = VolumeDrag.value(startValue: anchorValue, upwardDistance: travel, meterHeight: meterHeight, fine: fine)
        return value
    }

    private static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }
}
