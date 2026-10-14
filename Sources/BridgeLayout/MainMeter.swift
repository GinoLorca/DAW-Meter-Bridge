import CoreGraphics
import Foundation

/// The Main meter: a one-strip group bound to the main track, along the right edge of the bridge's
/// display ("Show Main Meter", docs/CONTROL.md `main`). It isn't over a fader, so it has no physical pitch.
///
/// A profile's Main meter is every group bound to `.mainTrack`. Showing it makes those groups visible
/// again where they were; when there is none, one is created next to the profile's first visible group.
/// Hiding it keeps the groups (`isVisible == false`), so it comes back where the user left it.
public enum MainMeter {
    /// Name of a new Main meter group.
    public static let name = "Main"
    /// A new Main meter is this many strip pitches of the group it lines up with wide.
    public static let widthInPitches: CGFloat = 1.5
    /// Width when there is no group to take a pitch from.
    public static let fallbackWidth: CGFloat = 90
    /// Narrowest a new Main meter is made to fit beside a group at the display's right edge.
    public static let minimumWidth: CGFloat = 40
    /// Space between the meter and the display's right edge, and between it and a neighbouring group.
    public static let margin: CGFloat = 8

    /// The frame of a new Main meter on a display with `bounds` (display-local points).
    ///
    /// It lines up with `reference` (same bottom and height) or, without one, uses `fallbackY` and
    /// `fallbackHeight`. It is `widthInPitches` of the reference's strip pitch wide (`fallbackWidth`
    /// without one, never more than a quarter of the display) and `margin` points left of the display's
    /// right edge. When `others` (frames of the other visible groups on the display) leave less room
    /// at that height, it narrows to the free space down to `minimumWidth`, else it goes just above
    /// them. Snapped to the device-pixel grid of `backingScale`.
    public static func frame(
        alignedWith reference: StripGroup?,
        others: [CGRect],
        in bounds: CGRect,
        backingScale: CGFloat,
        fallbackY: CGFloat = 0,
        fallbackHeight: CGFloat = 200
    ) -> CGRect {
        let grid = PixelGrid(scale: backingScale)
        let height = max(StripGroup.minimumHeight, min(reference?.frame.height ?? fallbackHeight, bounds.height))
        var y = reference?.frame.minY ?? fallbackY
        let maxWidth = max(minimumWidth, bounds.width / 4)
        var width = min(reference.map { $0.stripWidth * widthInPitches } ?? fallbackWidth, maxWidth)
        width = max(width, min(minimumWidth, bounds.width - 2 * margin))
        let right = bounds.maxX - margin

        func overlapping(_ minY: CGFloat, _ width: CGFloat) -> [CGRect] {
            let slot = CGRect(x: right - width, y: minY, width: width, height: height)
            return others.filter { $0.intersects(slot) }
        }
        let blockers = overlapping(y, width)
        if !blockers.isEmpty {
            let free = right - (blockers.map(\.maxX).max() ?? right) - margin
            if free >= min(width, minimumWidth) {
                width = min(width, free)
            } else if let top = blockers.map(\.maxY).max(), top + margin + height <= bounds.maxY,
                      overlapping(top + margin, width).isEmpty {
                y = top + margin
            }
        }
        let frame = grid.snap(CGRect(x: right - width, y: y, width: width, height: height))
        return GroupGeometry.clamp(frame, to: bounds)
    }
}

/// Where a new Main meter goes in a profile with no group to line it up with.
public struct MainMeterFallback: Hashable, Sendable {
    /// The display (usually the main display).
    public var display: DisplayFingerprint
    /// Bottom of the meter, display-local points.
    public var y: CGFloat
    public var height: CGFloat

    public init(display: DisplayFingerprint, y: CGFloat, height: CGFloat) {
        self.display = display
        self.y = y
        self.height = height
    }
}

extension StripGroup {
    /// True for a group bound to the main track (a Main meter).
    public var isMainMeter: Bool { binding == .mainTrack }
}

extension LayoutProfile {
    /// The groups bound to the main track, in profile order.
    public var mainMeterGroups: [StripGroup] { allGroups.filter(\.isMainMeter) }

    /// Whether the profile has a Main meter (shown or hidden).
    public var hasMainMeter: Bool { allGroups.contains(where: \.isMainMeter) }

    /// Whether a Main meter group is visible and at least partly on its display (whether or not the
    /// bridge is shown). One left entirely off its display is drawn nowhere, so it doesn't count; showing
    /// the Main meter then brings it back.
    public var isMainMeterVisible: Bool {
        displays.contains { layout in
            layout.groups.contains { $0.isMainMeter && $0.isVisible && $0.frame.intersects(layout.bounds) }
        }
    }

    /// Shows or hides the Main meter. Showing makes every Main meter group visible (moved back onto its
    /// display if it is entirely off it), or adds one (`addMainMeter`) when there is none. Hiding hides
    /// them all and keeps their frames. Returns false when nothing changed.
    @discardableResult
    public mutating func setMainMeterVisible(_ visible: Bool, fallback: MainMeterFallback? = nil) -> Bool {
        if visible, !hasMainMeter {
            return addMainMeter(fallback: fallback) != nil
        }
        var changed = false
        for d in displays.indices {
            let bounds = displays[d].bounds
            for g in displays[d].groups.indices where displays[d].groups[g].isMainMeter {
                var group = displays[d].groups[g]
                group.isVisible = visible
                if visible, !group.frame.intersects(bounds) {
                    group.frame = GroupGeometry.clamp(group.frame, to: bounds)
                }
                if group != displays[d].groups[g] {
                    displays[d].groups[g] = group
                    changed = true
                }
            }
        }
        return changed
    }

    /// Adds a visible Main meter (see `MainMeter.frame`) on the display of the profile's first visible
    /// group, lined up with it. Without a visible group it lines up with the first group; without any
    /// group it goes on `fallback`'s display at its height. Returns the new group's id, or nil when the
    /// profile has no group and there is no fallback.
    @discardableResult
    public mutating func addMainMeter(fallback: MainMeterFallback? = nil) -> UUID? {
        let candidates = displays.indices.flatMap { d in
            displays[d].groups.indices.map { (display: d, group: displays[d].groups[$0]) }
        }.filter { !$0.group.isMainMeter }
        let reference = candidates.first { $0.group.isVisible } ?? candidates.first

        let layoutIndex: Int
        if let reference {
            layoutIndex = reference.display
        } else if let fallback {
            if let index = displayIndex(matching: fallback.display) {
                layoutIndex = index
            } else {
                displays.append(DisplayLayout(fingerprint: fallback.display))
                layoutIndex = displays.count - 1
            }
        } else {
            return nil
        }

        let layout = displays[layoutIndex]
        let frame = MainMeter.frame(
            alignedWith: reference?.group,
            others: layout.groups.filter(\.isVisible).map(\.frame),
            in: layout.bounds,
            backingScale: layout.fingerprint.backingScale,
            fallbackY: fallback?.y ?? 0,
            fallbackHeight: fallback?.height ?? 200
        )
        let group = StripGroup(
            name: Self.uniqueGroupName(MainMeter.name, existing: allGroups.map(\.name)),
            binding: .mainTrack,
            stripCount: 1,
            frame: frame,
            isVisible: true
        )
        displays[layoutIndex].groups.append(group)
        return group.id
    }

    /// Puts every Main meter group back at the right edge of its display, lined up with the first visible
    /// other group there (`MainMeter.frame`), keeping its visibility. Used after the whole bridge moved to
    /// another display, where the Main meter's old offset from the other groups would leave it off the
    /// display or away from the edge. A layout without another visible group keeps the meter's own height
    /// and vertical position. Returns false when nothing changed.
    @discardableResult
    public mutating func reanchorMainMeters() -> Bool {
        var changed = false
        for d in displays.indices {
            let layout = displays[d]
            let reference = layout.groups.first { $0.isVisible && !$0.isMainMeter }
            var others = layout.groups.filter { $0.isVisible && !$0.isMainMeter }.map(\.frame)
            for g in layout.groups.indices where layout.groups[g].isMainMeter {
                let group = layout.groups[g]
                let frame = MainMeter.frame(
                    alignedWith: reference,
                    others: others,
                    in: layout.bounds,
                    backingScale: layout.fingerprint.backingScale,
                    fallbackY: group.frame.minY,
                    fallbackHeight: group.frame.height
                )
                // A second Main meter goes beside (or above) the first rather than on top of it.
                if group.isVisible { others.append(frame) }
                if frame != group.frame {
                    displays[d].groups[g].frame = frame
                    changed = true
                }
            }
        }
        return changed
    }

    /// `base`, or `base 2`, `base 3`… so it differs from `existing`.
    static func uniqueGroupName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

extension LayoutDocument {
    /// Adds a visible Main meter to every profile that has none (`LayoutProfile.addMainMeter`).
    /// Returns how many profiles got one.
    @discardableResult
    public mutating func addMainMetersWhereMissing(fallback: MainMeterFallback? = nil) -> Int {
        var added = 0
        for index in profiles.indices where !profiles[index].hasMainMeter {
            if profiles[index].addMainMeter(fallback: fallback) != nil { added += 1 }
        }
        return added
    }
}
