import CoreGraphics
import Foundation

/// The outcome of moving a layout's groups to another display.
public struct DisplayTransferResult: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        /// Both displays' points-per-mm were known: groups kept their physical size.
        case physical
        /// A scale was unknown: frames were mapped by the ratio of the display sizes, per axis.
        case proportional
    }

    /// The layout on the target display.
    public var layout: DisplayLayout
    public var mode: Mode
    /// Groups that ended up entirely off the target display (e.g. the UF1 meter when the bar display
    /// only spans the UF8). They are left as they are; the app may hide them or point them out.
    public var offscreenGroupIDs: [UUID]

    public init(layout: DisplayLayout, mode: Mode, offscreenGroupIDs: [UUID]) {
        self.layout = layout
        self.mode = mode
        self.offscreenGroupIDs = offscreenGroupIDs
    }
}

/// "Slide the bridge over": moves groups from one display to another, e.g. from a strip along the
/// bottom of the LG ultrawide to a dedicated bar display. Recalibrate afterwards.
public enum DisplayTransfer {
    /// Moves every group of `layout` to the display `target`.
    ///
    /// When both `layout.pointsPerMillimeter` and `targetPointsPerMillimeter` are known, groups keep
    /// their physical size and spacing, and the anchor keeps its relative position on the display (its
    /// centre at the same fraction of the display's width and height). The whole set is then shifted
    /// onto the display on each axis where it fits; where it doesn't, the anchor is shifted on instead.
    /// Otherwise every frame is mapped proportionally (the same fraction of the display on each axis).
    /// Either way the frames end on the target's device-pixel grid.
    ///
    /// The anchor is the group with `anchorGroupID` if given; otherwise the bounding box of the visible
    /// groups, or, when that box is larger than the target display, the group with the most strips.
    public static func move(
        _ layout: DisplayLayout,
        to target: DisplayFingerprint,
        targetPointsPerMillimeter: Double?,
        anchorGroupID: UUID? = nil
    ) -> DisplayTransferResult {
        let source = layout.fingerprint.pointSize
        let destination = target.pointSize
        var result = layout
        result.fingerprint = target
        result.pointsPerMillimeter = targetPointsPerMillimeter

        let mode: DisplayTransferResult.Mode
        if let from = layout.pointsPerMillimeter, from > 0, let to = targetPointsPerMillimeter, to > 0 {
            mode = .physical
            result.groups = physicalMove(layout.groups, scale: CGFloat(to / from), from: source, to: destination, anchorGroupID: anchorGroupID)
        } else {
            mode = .proportional
            let sx = source.width > 0 ? destination.width / source.width : 1
            let sy = source.height > 0 ? destination.height / source.height : 1
            result.groups = layout.groups.map { group in
                var g = group
                g.frame = CGRect(x: group.frame.minX * sx, y: group.frame.minY * sy, width: group.frame.width * sx, height: group.frame.height * sy)
                return g
            }
        }
        result = result.snappedToPixelGrid()
        let bounds = target.bounds
        let offscreen = result.groups.filter { !$0.frame.intersects(bounds) }.map(\.id)
        return DisplayTransferResult(layout: result, mode: mode, offscreenGroupIDs: offscreen)
    }

    /// Height limit of a stand-in placement, as a fraction of the stand-in display's height.
    public static let standInMaximumHeightFraction: CGFloat = 0.25

    /// Groups of `source` shown for now on a stand-in display (the saved display isn't connected), from
    /// `moved`, the result of `move(source, to: target, ...)`.
    ///
    /// `move` keeps the anchor at the same fraction of the display, which on a tall display puts a bar
    /// layout across the middle of the screen. Here the visible groups keep the source's distance from
    /// the bottom edge (scaled like the groups), are shrunk about their centre when taller than
    /// `standInMaximumHeightFraction` of the target, and are snapped to its pixel grid.
    public static func standIn(_ moved: DisplayLayout, from source: DisplayLayout) -> DisplayLayout {
        let visibleMoved = moved.groups.filter(\.isVisible).map(\.frame)
        let visibleSource = source.groups.filter(\.isVisible).map(\.frame)
        guard !visibleMoved.isEmpty, !visibleSource.isEmpty else { return moved }
        let box = union(visibleMoved)
        let sourceBox = union(visibleSource)
        let target = moved.fingerprint.pointSize
        guard box.height > 0, target.height > 0 else { return moved }

        let shrink = min(1, target.height * standInMaximumHeightFraction / box.height)
        let height = box.height * shrink
        let verticalScale = sourceBox.height > 0 ? box.height / sourceBox.height : 1
        let bottom = min(max(0, sourceBox.minY * verticalScale), max(0, target.height - height))

        var result = moved
        result.groups = moved.groups.map { group in
            var g = group
            let f = group.frame
            g.frame = CGRect(
                x: box.midX + (f.minX - box.midX) * shrink,
                y: bottom + (f.minY - box.minY) * shrink,
                width: f.width * shrink,
                height: f.height * shrink
            )
            return g
        }
        return result.snappedToPixelGrid()
    }

    private static func physicalMove(_ groups: [StripGroup], scale s: CGFloat, from source: CGSize, to destination: CGSize, anchorGroupID: UUID?) -> [StripGroup] {
        guard !groups.isEmpty else { return [] }
        func scaled(_ r: CGRect) -> CGRect { CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s) }

        let visible = groups.filter(\.isVisible)
        let box = union((visible.isEmpty ? groups : visible).map(\.frame))
        let anchor: CGRect
        if let id = anchorGroupID, let group = groups.first(where: { $0.id == id }) {
            anchor = group.frame
        } else if scaled(box).width <= destination.width, scaled(box).height <= destination.height {
            anchor = box
        } else {
            let largest = (visible.isEmpty ? groups : visible).max { a, b in
                a.stripCount != b.stripCount ? a.stripCount < b.stripCount : a.frame.width < b.frame.width
            }!
            anchor = largest.frame
        }

        // Keep the anchor's centre at the same fraction of the display.
        let fx = source.width > 0 ? anchor.midX / source.width : 0.5
        let fy = source.height > 0 ? anchor.midY / source.height : 0.5
        var dx = fx * destination.width - anchor.midX * s
        var dy = fy * destination.height - anchor.midY * s

        // Then nudge the set (or, if it can't fit, the anchor) onto the display, per axis.
        let movedBox = scaled(box).offsetBy(dx: dx, dy: dy)
        let movedAnchor = scaled(anchor).offsetBy(dx: dx, dy: dy)
        let display = CGRect(origin: .zero, size: destination)
        dx += shiftInside(movedBox.minX, movedBox.maxX, display.minX, display.maxX)
            ?? shiftInside(movedAnchor.minX, movedAnchor.maxX, display.minX, display.maxX) ?? 0
        dy += shiftInside(movedBox.minY, movedBox.maxY, display.minY, display.maxY)
            ?? shiftInside(movedAnchor.minY, movedAnchor.maxY, display.minY, display.maxY) ?? 0

        return groups.map { group in
            var g = group
            g.frame = scaled(group.frame).offsetBy(dx: dx, dy: dy)
            return g
        }
    }

    /// The shift that brings [lo, hi] inside [minimum, maximum], or nil if it is longer than that range.
    private static func shiftInside(_ lo: CGFloat, _ hi: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat? {
        guard hi - lo <= maximum - minimum + 1e-9 else { return nil }
        if lo < minimum { return minimum - lo }
        if hi > maximum { return maximum - hi }
        return 0
    }

    private static func union(_ rects: [CGRect]) -> CGRect {
        rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
    }
}

extension LayoutProfile {
    /// Moves every group of the profile onto `target`, leaving the profile with one display layout.
    ///
    /// Each saved display is moved with `DisplayTransfer.move` and the groups are merged; groups already
    /// on the target display (a strong fingerprint match) stay where they are. Returns the merged result.
    @discardableResult
    public mutating func moveAllGroups(to target: DisplayFingerprint, targetPointsPerMillimeter: Double?, anchorGroupID: UUID? = nil) -> DisplayTransferResult {
        var merged = DisplayLayout(fingerprint: target, groups: [], pointsPerMillimeter: targetPointsPerMillimeter)
        var allPhysical = true
        for layout in displays {
            if layout.fingerprint.match(target) >= .vendorModelNameSize {
                merged.groups += layout.groups
                if merged.pointsPerMillimeter == nil { merged.pointsPerMillimeter = layout.pointsPerMillimeter }
                continue
            }
            let moved = DisplayTransfer.move(layout, to: target, targetPointsPerMillimeter: targetPointsPerMillimeter, anchorGroupID: anchorGroupID)
            merged.groups += moved.layout.groups
            allPhysical = allPhysical && moved.mode == .physical
        }
        displays = [merged]
        let bounds = target.bounds
        return DisplayTransferResult(
            layout: merged,
            mode: allPhysical ? .physical : .proportional,
            offscreenGroupIDs: merged.groups.filter { !$0.frame.intersects(bounds) }.map(\.id)
        )
    }
}
