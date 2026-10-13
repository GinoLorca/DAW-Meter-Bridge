import BridgeLayout
import CoreGraphics
import Foundation

/// The part of a group a press lands on in edit mode.
enum EditHandle: Hashable, Sendable {
    /// Inside: dragging moves the group.
    case body
    /// Within `EditMath.handleThickness` of an edge: dragging moves that edge.
    case edge(RectEdge)
}

/// Frame math of edit mode, in display-local points (origin at the display's bottom-left).
///
/// Moves and resizes start from the frame at mouse-down plus the drag's accumulated translation
/// (`FineDrag`, so Shift is ×0.1 without jumps), land on whole device pixels, snap to the display's and
/// other groups' edges (Command held = no snapping) and never push a group further off its display than
/// it already was.
enum EditMath {
    /// Width of the edge band that resizes instead of moving, in points.
    static let handleThickness: CGFloat = 8

    /// Snap distance: the usual 8 pt, or ×0.1 with Shift so fine moves can stop just short of an edge.
    static func snapThreshold(fine: Bool) -> CGFloat {
        fine ? EdgeSnapper.defaultThreshold * CGFloat(FineDrag.defaultFineFactor) : EdgeSnapper.defaultThreshold
    }

    /// What a press at `point` (group-local, origin bottom-left) grabs. Edge bands shrink on small groups
    /// so the middle can always be grabbed; corners pick the nearer edge.
    static func handle(at point: CGPoint, groupSize size: CGSize) -> EditHandle {
        let band = min(handleThickness, size.width / 4, size.height / 4)
        let distances: [(RectEdge, CGFloat)] = [
            (.left, point.x), (.right, size.width - point.x),
            (.bottom, point.y), (.top, size.height - point.y),
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= band else { return .body }
        return .edge(nearest.0)
    }

    /// `start` moved by `translation`: origin on whole device pixels, snapped, and kept on the display.
    static func moved(
        _ start: CGRect,
        by translation: CGVector,
        scale: CGFloat,
        display: CGRect,
        others: [CGRect],
        fine: Bool,
        snapping: Bool
    ) -> SnapResult {
        let grid = PixelGrid(scale: scale)
        let origin = grid.snap(CGPoint(x: start.minX + translation.dx, y: start.minY + translation.dy))
        let candidate = CGRect(origin: origin, size: start.size)
        var result = EdgeSnapper(threshold: snapThreshold(fine: fine))
            .snapMove(candidate, display: display, others: others, disabled: !snapping)
        result.frame = keepOnDisplay(result.frame, display: display, start: start)
        return dropStaleGuides(result)
    }

    /// `start` with `edge` dragged by `translation` (its x for left/right, its y for bottom/top): the edge on
    /// whole device pixels, snapped, inside the display, and never smaller than `minimumSize`.
    static func resized(
        _ start: CGRect,
        edge: RectEdge,
        by translation: CGVector,
        minimumSize: CGSize,
        scale: CGFloat,
        display: CGRect,
        others: [CGRect],
        fine: Bool,
        snapping: Bool
    ) -> SnapResult {
        let grid = PixelGrid(scale: scale)
        let delta = edge.isHorizontal ? translation.dx : translation.dy
        let startEdge = position(of: edge, in: start)
        let pixelDelta = grid.snap(startEdge + delta) - startEdge
        let candidate = GroupGeometry.resize(start, edge: edge, by: pixelDelta, minimumSize: minimumSize)
        var result = EdgeSnapper(threshold: snapThreshold(fine: fine))
            .snapResize(candidate, edge: edge, display: display, others: others, disabled: !snapping)
        result.frame = limit(edge, of: result.frame, start: start, display: display, minimumSize: minimumSize)
        return dropStaleGuides(result)
    }

    /// One arrow-key press: a 1-pixel (⌥: 10-pixel) nudge, kept on the display.
    static func nudged(_ frame: CGRect, _ direction: NudgeDirection, largeStep: Bool, scale: CGFloat, display: CGRect) -> CGRect {
        let moved = KeyboardNudge.nudge(frame, direction, largeStep: largeStep, backingScale: scale)
        return keepOnDisplay(moved, display: display, start: frame)
    }

    /// One Shift-arrow press: → and ↑ grow the width and height by 1 pixel (⌥: 10), ← and ↓ shrink them.
    /// The left and bottom edges stay put.
    static func keyResized(
        _ frame: CGRect,
        _ direction: NudgeDirection,
        largeStep: Bool,
        scale: CGFloat,
        minimumSize: CGSize,
        display: CGRect
    ) -> CGRect {
        let step = PixelGrid(scale: scale).pixel * (largeStep ? KeyboardNudge.largeStepPixels : 1)
        let (edge, delta): (RectEdge, CGFloat)
        switch direction {
        case .right: (edge, delta) = (.right, step)
        case .left: (edge, delta) = (.right, -step)
        case .up: (edge, delta) = (.top, step)
        case .down: (edge, delta) = (.top, -step)
        }
        let resized = GroupGeometry.resize(frame, edge: edge, by: delta, minimumSize: minimumSize)
        return limit(edge, of: resized, start: frame, display: display, minimumSize: minimumSize)
    }

    /// Keeps the size and moves `frame` back onto `display` on each axis, but never further than needed:
    /// a group that `start` already had partly off the display (a calibration can do that) may stay where
    /// it was on that axis, it just can't go further out.
    static func keepOnDisplay(_ frame: CGRect, display: CGRect, start: CGRect) -> CGRect {
        func axis(_ value: CGFloat, length: CGFloat, startValue: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            let a = lower, b = upper - length
            let low = min(min(a, b), startValue)
            let high = max(max(a, b), startValue)
            return min(max(value, low), high)
        }
        return CGRect(
            x: axis(frame.minX, length: frame.width, startValue: start.minX, lower: display.minX, upper: display.maxX),
            y: axis(frame.minY, length: frame.height, startValue: start.minY, lower: display.minY, upper: display.maxY),
            width: frame.width,
            height: frame.height
        )
    }

    /// The group's frame for a new strip count: the pitch (strip width) is kept, so each strip still sits
    /// over one fader, and the right edge moves. Shifted left, then narrowed, only when it would not fit.
    static func frame(_ frame: CGRect, stripCount oldCount: Int, changedTo newCount: Int, display: CGRect) -> CGRect {
        let pitch = frame.width / CGFloat(max(1, oldCount))
        var result = CGRect(x: frame.minX, y: frame.minY, width: pitch * CGFloat(max(1, newCount)), height: frame.height)
        if result.width > display.width {
            result.size.width = display.width
            result.origin.x = display.minX
        } else if result.maxX > display.maxX, frame.maxX <= display.maxX {
            result.origin.x = max(display.minX, display.maxX - result.width)
        }
        return result
    }

    /// A free spot for a copy of `frame`: right of it, above, left or below (first that fits on the display
    /// without covering another group), else offset up and right.
    static func duplicateFrame(of frame: CGRect, display: CGRect, others: [CGRect], gap: CGFloat = 8) -> CGRect {
        let candidates = [
            frame.offsetBy(dx: frame.width + gap, dy: 0),
            frame.offsetBy(dx: 0, dy: frame.height + gap),
            frame.offsetBy(dx: -frame.width - gap, dy: 0),
            frame.offsetBy(dx: 0, dy: -frame.height - gap),
        ]
        let occupied = others + [frame]
        if let free = candidates.first(where: { display.contains($0) && !occupied.contains(where: $0.intersects) }) {
            return free
        }
        return keepOnDisplay(frame.offsetBy(dx: 24, dy: 24), display: display, start: display)
    }

    /// Moves a set of new frames up above the existing groups they would cover, when the set still fits on
    /// the display that way; otherwise returns them unchanged.
    static func stackedAbove(_ frames: [CGRect], existing: [CGRect], display: CGRect, gap: CGFloat = 8) -> [CGRect] {
        guard let lowest = frames.map(\.minY).min() else { return frames }
        let covered = existing.filter { old in frames.contains { $0.intersects(old) } }
        guard let top = covered.map(\.maxY).max() else { return frames }
        let dy = top + gap - lowest
        let moved = frames.map { $0.offsetBy(dx: 0, dy: dy) }
        guard let highest = moved.map(\.maxY).max(), highest <= display.maxY else { return frames }
        return moved
    }

    /// `base`, or `base 2`, `base 3`… so it differs from every name in `existing`.
    static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: - Helpers

    static func position(of edge: RectEdge, in rect: CGRect) -> CGFloat {
        switch edge {
        case .left: return rect.minX
        case .right: return rect.maxX
        case .bottom: return rect.minY
        case .top: return rect.maxY
        }
    }

    /// Keeps the moving `edge` inside the display (or where `start` already had it, if that was outside),
    /// then re-applies the minimum size against the fixed edge.
    private static func limit(_ edge: RectEdge, of frame: CGRect, start: CGRect, display: CGRect, minimumSize: CGSize) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        switch edge {
        case .left:
            minX = max(minX, min(display.minX, start.minX))
            minX = min(minX, maxX - minimumSize.width)
        case .right:
            maxX = min(maxX, max(display.maxX, start.maxX))
            maxX = max(maxX, minX + minimumSize.width)
        case .bottom:
            minY = max(minY, min(display.minY, start.minY))
            minY = min(minY, maxY - minimumSize.height)
        case .top:
            maxY = min(maxY, max(display.maxY, start.maxY))
            maxY = max(maxY, minY + minimumSize.height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Clears guides that no longer touch an edge after the frame was kept on the display.
    private static func dropStaleGuides(_ result: SnapResult) -> SnapResult {
        var r = result
        if let x = r.guideX, abs(x - r.frame.minX) > 0.01, abs(x - r.frame.maxX) > 0.01 { r.guideX = nil }
        if let y = r.guideY, abs(y - r.frame.minY) > 0.01, abs(y - r.frame.maxY) > 0.01 { r.guideY = nil }
        return r
    }
}
