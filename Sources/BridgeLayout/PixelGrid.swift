import CoreGraphics

/// Rounds point values to whole device pixels for a backing scale factor (1 or 2 on today's displays).
public struct PixelGrid: Hashable, Sendable {
    /// Device pixels per point; values below a tiny positive number are treated as 1.
    public var scale: CGFloat

    public init(scale: CGFloat) {
        self.scale = scale > 0.01 ? scale : 1
    }

    /// One device pixel, in points.
    public var pixel: CGFloat { 1 / scale }

    /// `value` rounded to the nearest device pixel.
    public func snap(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    public func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: snap(point.x), y: snap(point.y))
    }

    public func snap(_ vector: CGVector) -> CGVector {
        CGVector(dx: snap(vector.dx), dy: snap(vector.dy))
    }

    /// The rect with each edge rounded to the nearest device pixel.
    public func snap(_ rect: CGRect) -> CGRect {
        let r = rect.standardized
        let minX = snap(r.minX), minY = snap(r.minY)
        return CGRect(x: minX, y: minY, width: snap(r.maxX) - minX, height: snap(r.maxY) - minY)
    }
}
