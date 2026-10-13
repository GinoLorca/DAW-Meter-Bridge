import AppKit
import BridgeLayout
import MeterCore

extension AppController {
    /// Turns edit mode on or off: banks show guides, panels may become key and their events go to the
    /// installed `layoutEditor`. Leaving edit mode saves the layout. Entering it shows the bridge.
    func setEditing(_ editing: Bool) {
        guard editing != isEditing, !isHeadless else { return }
        if editing, !settings.isBridgeVisible { setBridgeVisible(true) }
        isEditing = editing
        FocusHandoff.isHoldingFocus = editing
        panelManager.eventHandler = layoutEditor
        panelManager.setEditing(editing)
        if editing {
            layoutEditor?.beginEditing(host: self)
        } else {
            cancelLayoutGesture()
            layoutEditor?.endEditing(host: self)
            saveLayouts()
            returnFocusToTheDAW()
        }
        keepAwake(for: 0.1)
        onStatusChange?()
    }

    func toggleEditing() {
        setEditing(!isEditing)
    }

    /// A rename or confirm dialog in edit mode activates the app (and keeps it active, so the panels keep
    /// the keyboard); give activation back to the DAW when edit mode ends, unless a window of ours
    /// (Settings, an alert) is still open.
    private func returnFocusToTheDAW() {
        FocusHandoff.giveBackIfIdle()
    }

    // MARK: - Undo and redo

    /// Puts back the layout before the last change.
    func undoLayoutChange() {
        cancelLayoutGesture()
        layoutHistory.undo()
    }

    /// Re-applies the last undone layout change.
    func redoLayoutChange() {
        cancelLayoutGesture()
        layoutHistory.redo()
    }

    /// Makes `restored` the layouts document (undo or redo) and registers the opposite step.
    private func restoreLayoutDocument(_ restored: LayoutDocument, actionName: String) {
        let current = document
        document = restored
        layoutHistory.registerInverse(actionName, current: current) { [weak self] next in
            self?.restoreLayoutDocument(next, actionName: actionName)
        }
        presentLayout()
        scheduleLayoutSave()
        onLayoutRestored?()
    }

    private func recordLayoutChange(_ actionName: String, before: LayoutDocument, coalesceKey: String?) {
        layoutHistory.record(actionName, before: before, coalesceKey: coalesceKey) { [weak self] previous in
            self?.restoreLayoutDocument(previous, actionName: actionName)
        }
    }
}

extension AppController: LayoutEditHost {
    var groupPanels: [GroupPanelController] { panelManager.controllers }
    var connectedDisplays: [ConnectedDisplay] { displayManager.displays }
    var layoutDocument: LayoutDocument { document }
    var activeProfile: LayoutProfile? { document.activeProfile }
    var currentSnapshot: BridgeSnapshot { snapshot }

    var preferredDisplay: ConnectedDisplay? {
        currentBridgeDisplay ?? displayManager.mainDisplay
    }

    func previewGroup(_ group: StripGroup) {
        guard var profile = document.activeProfile, profile.location(ofGroup: group.id) != nil else { return }
        let needsFullLayout = Self.moveStandInLayouts(of: &profile, placements: presentation.placements, only: group.id)
        profile.updateGroup(group)
        document.upsert(profile)

        if !needsFullLayout, group.isVisible,
           let index = presentation.placements.firstIndex(where: { $0.group.id == group.id }),
           group.frame.intersects(presentation.placements[index].display.localBounds) {
            presentation.placements[index].group = group
            panelManager.controller(forGroup: group.id)?.update(presentation.placements[index])
            updateWatchedTracks()
        } else {
            presentLayout()
        }
    }

    func updateActiveProfile(_ profile: LayoutProfile, save: Bool) {
        performLayoutChange("Edit Layout") { document in
            document.upsert(profile)
            if document.activeProfileID != profile.id { document.chooseManually(profile.id) }
        }
        if save { saveLayouts() }
    }

    func finishEditing() {
        setEditing(false)
    }

    func panel(forGroup id: UUID) -> GroupPanelController? {
        panelManager.controller(forGroup: id)
    }

    func beginLayoutGesture() {
        if gestureStartDocument == nil { gestureStartDocument = document }
    }

    func endLayoutGesture(_ actionName: String, coalesceKey: String?) {
        guard let before = gestureStartDocument else { return }
        gestureStartDocument = nil
        guard before != document else { return }
        recordLayoutChange(actionName, before: before, coalesceKey: coalesceKey)
        scheduleLayoutSave()
        onStatusChange?()
    }

    func cancelLayoutGesture() {
        guard let before = gestureStartDocument else { return }
        gestureStartDocument = nil
        guard before != document else { return }
        document = before
        presentLayout()
    }

    @discardableResult
    func performLayoutChange(_ actionName: String, coalesceKey: String?, _ change: (inout LayoutDocument) -> Void) -> Bool {
        cancelLayoutGesture()
        let before = document
        change(&document)
        guard document != before else { return false }
        recordLayoutChange(actionName, before: before, coalesceKey: coalesceKey)
        presentLayout()
        scheduleLayoutSave()
        return true
    }

    func activeProfileMatchingScreen() -> LayoutProfile? {
        guard var profile = document.activeProfile else { return nil }
        Self.moveStandInLayouts(of: &profile, placements: presentation.placements, only: nil)
        return profile
    }

    /// Moves each layout of `profile` that is shown on a stand-in display (its own display isn't
    /// connected) to that display for good, as `LayoutPresenter` showed it, so frames are relative to
    /// the display they are on. With `only`, just the layout holding that group. Returns true if any moved.
    @discardableResult
    static func moveStandInLayouts(of profile: inout LayoutProfile, placements: [GroupPlacement], only groupID: UUID?) -> Bool {
        var moved = Set<Int>()
        for placement in placements where placement.isFallback && (groupID == nil || placement.group.id == groupID) {
            guard let location = profile.location(ofGroup: placement.group.id), !moved.contains(location.display) else { continue }
            let result = DisplayTransfer.move(
                profile.displays[location.display],
                to: placement.display.fingerprint,
                targetPointsPerMillimeter: placement.display.pointsPerMillimeter
            )
            profile.displays[location.display] = result.layout
            moved.insert(location.display)
        }
        return !moved.isEmpty
    }
}
