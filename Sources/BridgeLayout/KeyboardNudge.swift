import CoreGraphics

/// An arrow key in edit mode. Up is +y (AppKit coordinates, origin bottom-left).
public enum NudgeDirection: Hashable, Sendable, CaseIterable {
    case left, right, up, down
}

/// Arrow-key nudges in edit mode: one device pixel per press, ten with Option.
public enum KeyboardNudge {
    /// Device pixels per press with Option held.
    public static let largeStepPixels: CGFloat = 10

    /// The offset in points for one press.
    public static func offset(_ direction: NudgeDirection, largeStep: Bool, backingScale: CGFloat) -> CGVector {
        let step = PixelGrid(scale: backingScale).pixel * (largeStep ? largeStepPixels : 1)
        switch direction {
        case .left: return CGVector(dx: -step, dy: 0)
        case .right: return CGVector(dx: step, dy: 0)
        case .up: return CGVector(dx: 0, dy: step)
        case .down: return CGVector(dx: 0, dy: -step)
        }
    }

    /// `frame` moved by one press. The size never changes.
    public static func nudge(_ frame: CGRect, _ direction: NudgeDirection, largeStep: Bool, backingScale: CGFloat) -> CGRect {
        let delta = offset(direction, largeStep: largeStep, backingScale: backingScale)
        return frame.offsetBy(dx: delta.dx, dy: delta.dy)
    }
}
