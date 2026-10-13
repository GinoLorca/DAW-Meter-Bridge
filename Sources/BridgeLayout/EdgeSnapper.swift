import CoreGraphics

/// A side of a rectangle in AppKit coordinates: `bottom` is minY, `top` is maxY.
public enum RectEdge: Hashable, Sendable, CaseIterable {
    case left, right, bottom, top

    public var isHorizontal: Bool { self == .left || self == .right }
}

/// A frame after snapping, with the guide lines to draw where an edge snapped.
public struct SnapResult: Hashable, Sendable {
    public var frame: CGRect
    /// Display-local x of a vertical guide, when a left/right edge snapped.
    public var guideX: CGFloat?
    /// Display-local y of a horizontal guide, when a bottom/top edge snapped.
    public var guideY: CGFloat?

    public init(frame: CGRect, guideX: CGFloat? = nil, guideY: CGFloat? = nil) {
        self.frame = frame
        self.guideX = guideX
        self.guideY = guideY
    }

    public var didSnap: Bool { guideX != nil || guideY != nil }
}

/// Snaps a group being moved or resized to the display's edges and to other groups' edges.
///
/// Each axis snaps independently to the nearest target within `threshold` points. Snapping is off
/// while Command is held: pass that as `disabled`.
public struct EdgeSnapper: Hashable, Sendable {
    public static let defaultThreshold: CGFloat = 8

    /// Snap distance in points.
    public var threshold: CGFloat

    public init(threshold: CGFloat = EdgeSnapper.defaultThreshold) {
        self.threshold = threshold
    }

    /// Snaps a moved frame: any of its edges can meet a display edge, or meet/align with another group's edge.
    /// The size never changes.
    public func snapMove(_ frame: CGRect, display: CGRect, others: [CGRect], disabled: Bool) -> SnapResult {
        guard !disabled else { return SnapResult(frame: frame) }
        let targets = Targets(display: display, others: others)
        var result = SnapResult(frame: frame)
        if let hit = nearest(edges: [frame.minX, frame.maxX], targets: targets.x) {
            result.frame.origin.x += hit.offset
            result.guideX = hit.target
        }
        if let hit = nearest(edges: [frame.minY, frame.maxY], targets: targets.y) {
            result.frame.origin.y += hit.offset
            result.guideY = hit.target
        }
        return result
    }

    /// Snaps the edge being dragged during a resize; the opposite edge stays put.
    /// A snap that would collapse the frame is ignored.
    public func snapResize(_ frame: CGRect, edge: RectEdge, display: CGRect, others: [CGRect], disabled: Bool) -> SnapResult {
        guard !disabled else { return SnapResult(frame: frame) }
        let targets = Targets(display: display, others: others)
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        var result = SnapResult(frame: frame)
        switch edge {
        case .left:
            if let hit = nearest(edges: [minX], targets: targets.x), hit.target < maxX { minX = hit.target; result.guideX = hit.target }
        case .right:
            if let hit = nearest(edges: [maxX], targets: targets.x), hit.target > minX { maxX = hit.target; result.guideX = hit.target }
        case .bottom:
            if let hit = nearest(edges: [minY], targets: targets.y), hit.target < maxY { minY = hit.target; result.guideY = hit.target }
        case .top:
            if let hit = nearest(edges: [maxY], targets: targets.y), hit.target > minY { maxY = hit.target; result.guideY = hit.target }
        }
        result.frame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return result
    }

    private struct Targets {
        var x: [CGFloat]
        var y: [CGFloat]

        init(display: CGRect, others: [CGRect]) {
            x = [display.minX, display.maxX] + others.flatMap { [$0.minX, $0.maxX] }
            y = [display.minY, display.maxY] + others.flatMap { [$0.minY, $0.maxY] }
        }
    }

    /// The smallest move (within the threshold) that puts one of `edges` on one of `targets`.
    private func nearest(edges: [CGFloat], targets: [CGFloat]) -> (offset: CGFloat, target: CGFloat)? {
        var best: (offset: CGFloat, target: CGFloat)?
        for edge in edges {
            for target in targets {
                let offset = target - edge
                if abs(offset) <= threshold, abs(offset) < abs(best?.offset ?? .infinity) {
                    best = (offset, target)
                }
            }
        }
        return best
    }
}
