import CoreGraphics

/// Frame math for edit mode: keeping groups on their display and resizing them by an edge.
public enum GroupGeometry {
    /// `frame` moved (and, only if larger than `bounds`, shrunk) so it lies entirely inside `bounds`.
    public static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let f = frame.standardized
        let width = min(f.width, bounds.width)
        let height = min(f.height, bounds.height)
        let x = min(max(f.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(f.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// `frame` with one edge moved by `delta` points (positive = right/up), never smaller than `minimumSize`.
    /// The opposite edge stays put.
    public static func resize(_ frame: CGRect, edge: RectEdge, by delta: CGFloat, minimumSize: CGSize) -> CGRect {
        let f = frame.standardized
        var minX = f.minX, maxX = f.maxX, minY = f.minY, maxY = f.maxY
        switch edge {
        case .left: minX = min(minX + delta, maxX - minimumSize.width)
        case .right: maxX = max(maxX + delta, minX + minimumSize.width)
        case .bottom: minY = min(minY + delta, maxY - minimumSize.height)
        case .top: maxY = max(maxY + delta, minY + minimumSize.height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension StripGroup {
    /// Narrowest strip edit mode allows, in points.
    public static let minimumStripWidth: CGFloat = 6
    /// Lowest group edit mode allows, in points.
    public static let minimumHeight: CGFloat = 24

    /// Smallest frame size for this group in edit mode.
    public var minimumSize: CGSize {
        CGSize(width: CGFloat(max(1, stripCount)) * Self.minimumStripWidth, height: Self.minimumHeight)
    }

    /// This group moved onto `bounds` (its display's bounds); shrunk only if larger than the display.
    public func clamped(to bounds: CGRect) -> StripGroup {
        var copy = self
        copy.frame = GroupGeometry.clamp(frame, to: bounds)
        return copy
    }
}
