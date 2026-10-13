import BridgeLayout
import CoreGraphics

/// One strip group as it is shown now: on which display, and where.
struct GroupPlacement: Equatable, Sendable {
    var group: StripGroup
    var display: ConnectedDisplay
    /// Index of the group's layout in the active profile's `displays`. Nil when the layout's own display
    /// is not connected and the group is shown on the main display instead (that move is not saved).
    var layoutIndex: Int?

    /// The group's frame in global AppKit coordinates (the panel frame).
    var globalFrame: CGRect { display.globalRect(fromLocal: group.frame) }

    /// True when the group is shown on a stand-in display rather than its own.
    var isFallback: Bool { layoutIndex == nil }
}

/// Where the active profile's groups go on the displays connected now.
struct LayoutPresentation: Equatable, Sendable {
    /// Visible groups on connected displays, in profile order.
    var placements: [GroupPlacement] = []
    /// Things to tell the user in the menu, e.g. "made for a display that isn't connected".
    var notes: [String] = []
    /// The profile with layouts adapted to a display whose mode changed. Save it when non-nil.
    var updatedProfile: LayoutProfile?
}

enum LayoutPresenter {
    /// Matches the profile's display layouts to the connected displays.
    ///
    /// - Each layout goes to its best-matching display (`DisplayMatcher`). If that display now runs at a
    ///   different point size (new resolution or scaling), the layout is adapted and `updatedProfile` set.
    /// - If none of the profile's displays is connected, the layout with the most visible groups is shown
    ///   on the main display (physically sized when both scales are known, but along the bottom and at
    ///   most a quarter of its height; see `DisplayTransfer.standIn`), without saving that move.
    /// - Hidden groups, and groups entirely off their display, are left out.
    static func present(_ profile: LayoutProfile?, on displays: [ConnectedDisplay]) -> LayoutPresentation {
        var result = LayoutPresentation()
        guard let profile, !displays.isEmpty else { return result }
        var updated = profile
        var changed = false

        let assignments = DisplayMatcher.assign(profile.displays.map(\.fingerprint), to: displays.map(\.fingerprint))
        for assignment in assignments {
            let display = displays[assignment.displayIndex]
            var layout = profile.displays[assignment.layoutIndex]
            if !sameSize(layout.fingerprint.pointSize, display.fingerprint.pointSize) {
                layout = layout.adapted(to: display.fingerprint)
                updated.displays[assignment.layoutIndex] = layout
                changed = true
            }
            append(layout.groups, on: display, layoutIndex: assignment.layoutIndex, to: &result)
        }

        let assigned = Set(assignments.map(\.layoutIndex))
        let unassigned = profile.displays.indices.filter { !assigned.contains($0) }
        if assignments.isEmpty, let main = displays.first(where: \.isMain) ?? displays.first,
           let index = unassigned.max(by: { visibleCount(profile.displays[$0]) < visibleCount(profile.displays[$1]) }) {
            let layout = profile.displays[index]
            let moved = DisplayTransfer.move(layout, to: main.fingerprint, targetPointsPerMillimeter: main.pointsPerMillimeter)
            // Along the bottom (as on its own display) and at most a quarter of the screen high, not
            // across the middle of the main display above every window.
            let standIn = DisplayTransfer.standIn(moved.layout, from: layout)
            append(standIn.groups, on: main, layoutIndex: nil, to: &result)
            result.notes.append(
                "“\(profile.name)” was set up for “\(layout.fingerprint.name)”, which isn’t connected. Showing it on “\(main.name)” for now; use Move Bridge to Display to keep it there."
            )
        } else {
            for index in unassigned where visibleCount(profile.displays[index]) > 0 {
                result.notes.append("Display “\(profile.displays[index].fingerprint.name)” of “\(profile.name)” isn’t connected; its meters are hidden.")
            }
        }
        if changed { result.updatedProfile = updated }
        return result
    }

    private static func append(_ groups: [StripGroup], on display: ConnectedDisplay, layoutIndex: Int?, to result: inout LayoutPresentation) {
        for group in groups where group.isVisible {
            guard group.frame.width >= 1, group.frame.height >= 1, group.frame.intersects(display.localBounds) else {
                result.notes.append("“\(group.name)” is outside “\(display.name)”; edit the layout to bring it back.")
                continue
            }
            result.placements.append(GroupPlacement(group: group, display: display, layoutIndex: layoutIndex))
        }
    }

    private static func visibleCount(_ layout: DisplayLayout) -> Int {
        layout.groups.filter(\.isVisible).count
    }

    private static func sameSize(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}
