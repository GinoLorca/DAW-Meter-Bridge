import BridgeLayout
import CoreGraphics
import Foundation

// Edits of a profile's groups used by edit mode and the menus. Pure value changes: the caller records
// them for undo, re-places the panels and saves (see `LayoutEditHost.performProfileChange`).
extension LayoutProfile {
    /// Changes the group with `id` in place. `body` also gets the bounds of the group's display.
    /// Returns false if there is no such group or `body` changed nothing.
    @discardableResult
    mutating func modifyGroup(_ id: UUID, _ body: (inout StripGroup, _ displayBounds: CGRect) -> Void) -> Bool {
        guard let location = location(ofGroup: id) else { return false }
        let layout = displays[location.display]
        var group = layout.groups[location.group]
        let before = group
        body(&group, layout.bounds)
        guard group != before else { return false }
        displays[location.display].groups[location.group] = group
        return true
    }

    /// Renames a group (blank names are refused).
    @discardableResult
    mutating func renameGroup(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return modifyGroup(id) { group, _ in group.name = trimmed }
    }

    /// Rebinds a group. A single-track binding (selected/main) makes it one strip wide, and a surface
    /// binding that starts mid-unit drops strips the unit doesn't have; the pitch is kept either way.
    @discardableResult
    mutating func setBinding(_ binding: StripBinding, ofGroup id: UUID) -> Bool {
        modifyGroup(id) { group, bounds in
            group.binding = binding
            if let maximum = binding.maximumStripCount, maximum >= 1, group.stripCount > maximum {
                group.frame = EditMath.frame(group.frame, stripCount: group.stripCount, changedTo: maximum, display: bounds)
                group.stripCount = maximum
            }
        }
    }

    /// Sets the number of strips, keeping the pitch (see `EditMath.frame(_:stripCount:changedTo:display:)`).
    @discardableResult
    mutating func setStripCount(_ count: Int, ofGroup id: UUID) -> Bool {
        let count = min(max(count, 1), LayoutEdits.maximumStripCount)
        return modifyGroup(id) { group, bounds in
            guard group.stripCount != count else { return }
            group.frame = EditMath.frame(group.frame, stripCount: group.stripCount, changedTo: count, display: bounds)
            group.stripCount = count
        }
    }

    /// Two-point calibration: strip 1's centre on `firstCenterX` and the last strip's on `lastCenterX`
    /// (display-local). A group of 2+ strips with a known physical pitch also sets its display's
    /// points-per-mm, so a later move to another display keeps physical size.
    @discardableResult
    mutating func calibrateGroup(_ id: UUID, firstCenterX: CGFloat, lastCenterX: CGFloat) -> Bool {
        guard let location = location(ofGroup: id) else { return false }
        let group = displays[location.display].groups[location.group]
        guard let calibrated = group.calibrated(firstCenterX: firstCenterX, lastCenterX: lastCenterX) else { return false }
        displays[location.display].groups[location.group] = calibrated
        if calibrated.stripCount >= 2, let scale = calibrated.measuredPointsPerMillimeter {
            displays[location.display].pointsPerMillimeter = scale
        }
        return true
    }

    /// Removes a group and returns it. A display layout left without groups is dropped.
    @discardableResult
    mutating func removeGroup(_ id: UUID) -> StripGroup? {
        guard let location = location(ofGroup: id) else { return nil }
        let removed = displays[location.display].groups.remove(at: location.group)
        if displays[location.display].groups.isEmpty { displays.remove(at: location.display) }
        return removed
    }

    /// Adds a copy of a group (new id, "… copy" name) in a free spot next to it. Returns the copy's id.
    @discardableResult
    mutating func duplicateGroup(_ id: UUID) -> UUID? {
        guard let location = location(ofGroup: id) else { return nil }
        let layout = displays[location.display]
        let original = layout.groups[location.group]
        var copy = original
        copy.id = UUID()
        copy.name = EditMath.uniqueName("\(original.name) copy", existing: allGroups.map(\.name))
        copy.isVisible = true
        copy.frame = EditMath.duplicateFrame(
            of: original.frame,
            display: layout.bounds,
            others: layout.groups.filter { $0.id != id && $0.isVisible }.map(\.frame)
        )
        displays[location.display].groups.insert(copy, at: location.group + 1)
        return copy.id
    }

    /// Adds groups to the layout at `layoutIndex`, or else the layout of `display` (created if the profile
    /// has none for that display). Names are made unique within the profile.
    mutating func addGroups(_ groups: [StripGroup], on display: DisplayFingerprint, layoutIndex hint: Int? = nil, pointsPerMillimeter: Double?) {
        var names = allGroups.map(\.name)
        let renamed = groups.map { group -> StripGroup in
            var g = group
            g.name = EditMath.uniqueName(group.name, existing: names)
            names.append(g.name)
            return g
        }
        if let index = hint.flatMap({ displays.indices.contains($0) ? $0 : nil }) ?? layoutIndex(for: display) {
            displays[index].groups += renamed
            if displays[index].pointsPerMillimeter == nil { displays[index].pointsPerMillimeter = pointsPerMillimeter }
        } else {
            displays.append(DisplayLayout(fingerprint: display, groups: renamed, pointsPerMillimeter: pointsPerMillimeter))
        }
    }

    /// Moves one group to another display, keeping its physical size when both displays' scales are known
    /// (else scaled proportionally) and its relative position, then puts it fully on that display.
    /// `layoutIndex` names the target display's layout when the caller knows it (else it is looked up or
    /// created). Returns false if the group is already there.
    @discardableResult
    mutating func moveGroup(_ id: UUID, to target: DisplayFingerprint, layoutIndex hint: Int? = nil, targetPointsPerMillimeter: Double?) -> Bool {
        guard let location = location(ofGroup: id) else { return false }
        let validHint = hint.flatMap { displays.indices.contains($0) ? $0 : nil }
        let targetIndex = validHint ?? layoutIndex(for: target)
        if targetIndex == location.display { return false }
        let source = displays[location.display]
        let single = DisplayLayout(
            fingerprint: source.fingerprint,
            groups: [source.groups[location.group]],
            pointsPerMillimeter: source.pointsPerMillimeter
        )
        let moved = DisplayTransfer.move(single, to: target, targetPointsPerMillimeter: targetPointsPerMillimeter)
        guard var group = moved.layout.groups.first else { return false }
        group.frame = GroupGeometry.clamp(group.frame, to: target.bounds)
        group.isVisible = true

        displays[location.display].groups.remove(at: location.group)
        var index = targetIndex
        if displays[location.display].groups.isEmpty {
            displays.remove(at: location.display)
            if let i = index, i > location.display { index = i - 1 }
        }
        if let index {
            displays[index].groups.append(group)
            if displays[index].pointsPerMillimeter == nil { displays[index].pointsPerMillimeter = targetPointsPerMillimeter }
        } else {
            displays.append(DisplayLayout(fingerprint: target, groups: [group], pointsPerMillimeter: targetPointsPerMillimeter))
        }
        return true
    }

    /// The layout for a connected display: the best fingerprint match of at least vendor+model+name+size
    /// (or, failing that, the same name and point size), so a group is never added to a look-alike's layout.
    func layoutIndex(for display: DisplayFingerprint) -> Int? {
        var best: (index: Int, match: DisplayMatch)?
        for (index, layout) in displays.enumerated() {
            let match = layout.fingerprint.match(display)
            let samePanel = match >= .vendorModelNameSize
                || (match == .name && layout.fingerprint.pointSize == display.pointSize)
            if samePanel, match > (best?.match ?? .none) { best = (index, match) }
        }
        return best?.index
    }
}

extension LayoutDocument {
    /// `base`, or `base 2`, `base 3`… so no two profiles share a name.
    func uniqueProfileName(_ base: String) -> String {
        EditMath.uniqueName(base, existing: profiles.map(\.name))
    }

    /// Renames a profile (blank names are refused).
    @discardableResult
    mutating func renameProfile(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var profile = profile(withID: id), profile.name != trimmed else { return false }
        profile.name = trimmed
        upsert(profile)
        return true
    }

    /// Adds a profile and makes it the active one (chosen manually, so it stays until Automatic is picked).
    mutating func addProfile(_ profile: LayoutProfile) {
        upsert(profile)
        chooseManually(profile.id)
    }
}

/// Limits of edit mode.
enum LayoutEdits {
    /// Most strips a group can have from the menu (one UF8 plus an extender's worth).
    static let maximumStripCount = 16
}
