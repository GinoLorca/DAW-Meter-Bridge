import BridgeLayout
import CoreGraphics
import Foundation

// Group commands of edit mode and the menus, built on `performProfileChange`: each is one undo step,
// re-places the panels and is saved shortly after. Frames are display-local, as the panels show them.
extension LayoutEditHost {
    /// Adds the groups of `template` to the active profile on `display` (default: the bridge's display).
    /// Returns the new groups' ids (none without an active profile).
    @discardableResult
    func addGroups(from template: LayoutTemplate, on display: ConnectedDisplay? = nil) -> [UUID] {
        guard let target = display ?? preferredDisplay, activeProfile != nil else { return [] }
        var added: [UUID] = []
        performProfileChange("Add \(template.title)") { profile in
            let index = layoutIndex(of: target, in: profile)
            let (groups, scale) = LayoutTemplates.groups(template, on: target, existing: index.map { profile.displays[$0] })
            guard !groups.isEmpty else { return false }
            profile.addGroups(groups, on: target.fingerprint, layoutIndex: index, pointsPerMillimeter: scale)
            added = groups.map(\.id)
            return true
        }
        return added
    }

    func renameGroup(_ id: UUID, to name: String) {
        performProfileChange("Rename Group") { $0.renameGroup(id, to: name) }
    }

    func setBinding(_ binding: StripBinding, ofGroup id: UUID) {
        performProfileChange("Change Binding") { $0.setBinding(binding, ofGroup: id) }
    }

    func setStripCount(_ count: Int, ofGroup id: UUID) {
        performProfileChange("Change Strip Count") { $0.setStripCount(count, ofGroup: id) }
    }

    @discardableResult
    func duplicateGroup(_ id: UUID) -> UUID? {
        var copy: UUID?
        performProfileChange("Duplicate Group") { profile in
            copy = profile.duplicateGroup(id)
            return copy != nil
        }
        return copy
    }

    func deleteGroup(_ id: UUID) {
        performProfileChange("Delete Group") { $0.removeGroup(id) != nil }
    }

    /// Moves one group to `display`, keeping physical size when both scales are known.
    func moveGroup(_ id: UUID, to display: ConnectedDisplay) {
        performProfileChange("Move Group to \(display.name)") { profile in
            profile.moveGroup(
                id,
                to: display.fingerprint,
                layoutIndex: layoutIndex(of: display, in: profile),
                targetPointsPerMillimeter: display.pointsPerMillimeter
            )
        }
    }

    /// Applies a two-point calibration (display-local strip centres) to a group.
    @discardableResult
    func calibrateGroup(_ id: UUID, firstCenterX: CGFloat, lastCenterX: CGFloat) -> Bool {
        performProfileChange("Calibrate Group") { $0.calibrateGroup(id, firstCenterX: firstCenterX, lastCenterX: lastCenterX) }
    }

    /// Shows a hidden group again, moved onto its display if it was off it.
    func showGroup(_ id: UUID) {
        performProfileChange("Show Group") { profile in
            profile.modifyGroup(id) { group, bounds in
                group.isVisible = true
                if !group.frame.intersects(bounds) { group.frame = GroupGeometry.clamp(group.frame, to: bounds) }
            }
        }
    }

    /// Groups of the active profile that are hidden, or off a display that shows the others, for
    /// "Show Hidden Group".
    var hiddenGroups: [StripGroup] {
        guard let profile = activeProfile else { return [] }
        let placements = groupPanels.map(\.placement)
        let shown = Set(placements.map(\.group.id))
        let shownLayouts = Set(placements.compactMap { profile.location(ofGroup: $0.group.id)?.display })
        return profile.displays.enumerated().flatMap { index, layout in
            layout.groups.filter { !shown.contains($0.id) && (!$0.isVisible || shownLayouts.contains(index)) }
        }
    }

    /// The index of the profile's layout shown on `display`, as the presenter matched it (so new groups
    /// join the groups already on screen there), else the best fingerprint match.
    func layoutIndex(of display: ConnectedDisplay, in profile: LayoutProfile) -> Int? {
        for placement in groupPanels.map(\.placement) where placement.display.displayID == display.displayID {
            if let location = profile.location(ofGroup: placement.group.id) { return location.display }
        }
        return profile.layoutIndex(for: display.fingerprint)
    }
}
