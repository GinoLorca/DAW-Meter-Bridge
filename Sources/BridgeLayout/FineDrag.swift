import CoreGraphics

/// Accumulates one axis of a drag, scaling motion by `fineFactor` while fine mode (Shift) is held.
///
/// Motion is accumulated as deltas, so pressing or releasing Shift mid-drag never makes the value
/// jump, and fine motion smaller than a point is kept rather than lost to rounding. Use it directly
/// for volume drags; `FineDrag` wraps two of these for moving and resizing groups.
public struct FineDragAxis: Hashable, Sendable {
    /// Multiplier applied while fine mode is on (Shift = ×0.1).
    public var fineFactor: Double
    /// Total scaled motion since the drag began.
    public private(set) var value: Double = 0

    public init(fineFactor: Double = FineDrag.defaultFineFactor) {
        self.fineFactor = fineFactor
    }

    /// Adds raw pointer motion and returns the new total.
    @discardableResult
    public mutating func add(_ rawDelta: Double, fine: Bool) -> Double {
        value += fine ? rawDelta * fineFactor : rawDelta
        return value
    }

    public mutating func reset() {
        value = 0
    }
}

/// A two-dimensional move/resize drag with Shift-for-fine and device-pixel snapping.
///
/// Feed pointer locations (`drag(to:fine:)`) or deltas (`add(_:fine:)`). `translation` keeps the exact
/// sub-point total; `apply(to:)` gives the dragged position rounded to whole device pixels, so a group
/// lands on crisp pixel boundaries while slow fine drags still advance one device pixel at a time.
public struct FineDrag: Hashable, Sendable {
    /// Shift = ×0.1.
    public static let defaultFineFactor = 0.1

    /// Device-pixel grid of the display being edited.
    public var grid: PixelGrid
    private var x: FineDragAxis
    private var y: FineDragAxis
    /// Last pointer location fed to `drag(to:fine:)`.
    public private(set) var lastLocation: CGPoint?

    /// - Parameters:
    ///   - backingScale: device pixels per point of the display being edited.
    ///   - start: pointer location at mouse-down, if `drag(to:fine:)` will be used.
    public init(backingScale: CGFloat, fineFactor: Double = FineDrag.defaultFineFactor, start: CGPoint? = nil) {
        grid = PixelGrid(scale: backingScale)
        x = FineDragAxis(fineFactor: fineFactor)
        y = FineDragAxis(fineFactor: fineFactor)
        lastLocation = start
    }

    /// Exact accumulated motion in points (not snapped).
    public var translation: CGVector { CGVector(dx: x.value, dy: y.value) }

    /// Accumulated motion rounded to whole device pixels.
    public var snappedTranslation: CGVector { grid.snap(translation) }

    /// Restarts the drag at `location` with no accumulated motion.
    public mutating func begin(at location: CGPoint) {
        x.reset()
        y.reset()
        lastLocation = location
    }

    /// Adds the motion from the last location to `location`. The first call after `init` without a
    /// start location only records the location. Returns the exact total translation.
    @discardableResult
    public mutating func drag(to location: CGPoint, fine: Bool) -> CGVector {
        defer { lastLocation = location }
        guard let last = lastLocation else { return translation }
        return add(CGVector(dx: location.x - last.x, dy: location.y - last.y), fine: fine)
    }

    /// Adds raw pointer motion (e.g. `NSEvent.deltaX`, with y flipped to point up). Returns the exact total.
    @discardableResult
    public mutating func add(_ rawDelta: CGVector, fine: Bool) -> CGVector {
        x.add(Double(rawDelta.dx), fine: fine)
        y.add(Double(rawDelta.dy), fine: fine)
        return translation
    }

    /// `origin` moved by the accumulated translation, rounded to whole device pixels.
    public func apply(to origin: CGPoint) -> CGPoint {
        grid.snap(CGPoint(x: origin.x + translation.dx, y: origin.y + translation.dy))
    }

    /// `frame` moved by the accumulated translation, its origin rounded to whole device pixels and its size kept.
    public func moved(_ frame: CGRect) -> CGRect {
        CGRect(origin: apply(to: frame.origin), size: frame.size)
    }
}
