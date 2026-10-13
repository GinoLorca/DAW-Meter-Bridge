import AppKit
import BridgeLayout
import Carbon.HIToolbox
import MeterCore

/// The edit-mode UI: selection, moving and resizing groups with the mouse (Shift = fine, Command = no
/// snapping) and the keyboard, the right-click menu, two-point calibration, the outlines/HUD canvas and
/// undo. Installed on `AppController.layoutEditor`; the shell turns edit mode on and off.
@MainActor
final class LayoutEditorController: LayoutEditor {
    /// A mouse drag on a group: moving it, or one of its edges.
    struct Gesture {
        var groupID: UUID
        var handle: EditHandle
        /// The group's frame at mouse-down (display-local).
        var startFrame: CGRect
        var drag: FineDrag
        var modifiers: NSEvent.ModifierFlags
    }

    private(set) weak var host: (any LayoutEditHost)?
    /// The group that keys, the HUD and the menus act on. Kept across edit sessions.
    private(set) var selectedGroupID: UUID?
    private(set) var gesture: Gesture?
    private(set) var calibration: CalibrationSession?
    /// Guides of the last snap, per display.
    private(set) var snapGuides: (displayID: CGDirectDisplayID, x: CGFloat?, y: CGFloat?)?
    private var canvases: [CGDirectDisplayID: EditCanvasPanel] = [:]
    private var cursorViews: [UUID: EditCursorView] = [:]

    /// The pointer in global AppKit coordinates. `NSEvent.mouseLocation` keeps drags steady while the
    /// panel under the pointer moves; `--demo-edit` replaces it with scripted positions.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
    /// Whether selecting a group makes its panel key (so arrow keys reach it). Off in `--demo-edit`.
    var takesKeyFocus = true
    /// Asks for a line of text (rename, track offset); nil = cancelled. Replaced in `--demo-edit`.
    var textPrompt: (_ title: String, _ message: String, _ initial: String) -> String? = { title, message, initial in
        TextPrompt.run(title: title, message: message, initial: initial)
    }

    var isEditing: Bool { host != nil }

    // MARK: - LayoutEditor

    func beginEditing(host: any LayoutEditHost) {
        self.host = host
        if selectedGroupID.flatMap(placement(of:)) == nil {
            selectedGroupID = orderedPlacements.first?.group.id
        }
        refresh()
        focusSelected()
    }

    func panelsDidChange(host: any LayoutEditHost) {
        refresh()
    }

    func endEditing(host: any LayoutEditHost) {
        if let calibration { finishCalibration(calibration, apply: false) }
        gesture = nil
        snapGuides = nil
        canvases.values.forEach { $0.orderOut(nil) }
        canvases.values.forEach { $0.close() }
        canvases = [:]
        cursorViews.values.forEach { $0.removeFromSuperview() }
        cursorViews = [:]
        self.host = nil
        NSCursor.arrow.set()
    }

    func menuItems(host: any LayoutEditHost) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let id = selectedGroupID, let placement = placement(of: id) {
            let group = placement.group
            items.append(.info("Selected: \(Self.title(of: group)), \(BindingText.describe(group.binding, stripCount: group.stripCount))"))
            items.append(MenuActionItem("Calibrate “\(Self.title(of: group))”…") { [weak self] in self?.beginCalibration(of: id) })
            items.append(.submenu("Selected Group", items: GroupMenu.items(for: placement, editor: self, host: host)))
        }
        let hidden = host.hiddenGroups
        if !hidden.isEmpty {
            items.append(.submenu("Show Hidden Group", items: hidden.map { group in
                MenuActionItem(Self.title(of: group)) { [weak self, weak host] in
                    host?.showGroup(group.id)
                    self?.select(group.id, focus: true)
                }
            }))
        }
        return items
    }

    // MARK: - Mouse

    func groupPanel(_ panel: GroupPanelController, mouseDown event: NSEvent) {
        guard let host, calibration == nil else { return }
        if gesture != nil { finishGesture() }
        select(panel.groupID, focus: true)
        let pointer = pointerLocation()
        let frame = panel.group.frame
        let local = CGPoint(
            x: pointer.x - panel.display.frame.minX - frame.minX,
            y: pointer.y - panel.display.frame.minY - frame.minY
        )
        host.beginLayoutGesture()
        gesture = Gesture(
            groupID: panel.groupID,
            handle: EditMath.handle(at: local, groupSize: frame.size),
            startFrame: frame,
            drag: FineDrag(backingScale: panel.display.backingScale, start: pointer),
            modifiers: event.modifierFlags
        )
        cursorViews[panel.groupID]?.isDragging = true
    }

    func groupPanel(_ panel: GroupPanelController, mouseDragged event: NSEvent) {
        guard var current = gesture else { return }
        current.drag.drag(to: pointerLocation(), fine: event.modifierFlags.contains(.shift))
        current.modifiers = event.modifierFlags
        gesture = current
        applyGesture()
    }

    func groupPanel(_ panel: GroupPanelController, mouseUp event: NSEvent) {
        finishGesture()
    }

    func groupPanel(_ panel: GroupPanelController, rightMouseDown event: NSEvent) {
        guard let host, calibration == nil, gesture == nil else { return }
        select(panel.groupID, focus: true)
        let menu = NSMenu()
        menu.autoenablesItems = false
        GroupMenu.items(for: panel.placement, editor: self, host: host).forEach(menu.addItem)
        NSMenu.popUpContextMenu(menu, with: event, for: panel.hostView)
    }

    func groupPanel(_ panel: GroupPanelController, flagsChanged event: NSEvent) {
        guard var current = gesture else { return }
        current.modifiers = event.modifierFlags
        gesture = current
        applyGesture()
    }

    func groupPanel(_ panel: GroupPanelController, keyDown event: NSEvent) -> Bool {
        handleKey(event)
    }

    /// Moves or resizes the dragged group to where the gesture says now.
    private func applyGesture() {
        guard let host, let current = gesture, let placement = placement(of: current.groupID) else { return }
        let fine = current.modifiers.contains(.shift)
        let snapping = !current.modifiers.contains(.command)
        let display = placement.display
        let others = otherFrames(on: display, excluding: current.groupID)
        let result: SnapResult
        switch current.handle {
        case .body:
            result = EditMath.moved(
                current.startFrame, by: current.drag.translation, scale: display.backingScale,
                display: display.localBounds, others: others, fine: fine, snapping: snapping
            )
        case let .edge(edge):
            result = EditMath.resized(
                current.startFrame, edge: edge, by: current.drag.translation, minimumSize: placement.group.minimumSize,
                scale: display.backingScale, display: display.localBounds, others: others, fine: fine, snapping: snapping
            )
        }
        if result.frame != placement.group.frame {
            var group = placement.group
            group.frame = result.frame
            host.previewGroup(group)
        }
        snapGuides = result.didSnap ? (display.displayID, result.guideX, result.guideY) : nil
        refreshCanvases()
    }

    /// Ends a drag as one undo step.
    func finishGesture() {
        guard let finished = gesture else { return }
        gesture = nil
        snapGuides = nil
        cursorViews[finished.groupID]?.isDragging = false
        host?.endLayoutGesture(finished.handle == .body ? "Move Group" : "Resize Group", coalesceKey: nil)
        refreshCanvases()
    }

    /// Puts the dragged group back where the drag started.
    func cancelGesture() {
        guard let cancelled = gesture else { return }
        gesture = nil
        snapGuides = nil
        cursorViews[cancelled.groupID]?.isDragging = false
        host?.cancelLayoutGesture()
        refresh()
    }

    // MARK: - Keys

    /// Edit-mode keys: arrows nudge (⌥ ×10), ⇧-arrows resize, Tab cycles, Delete removes, ⌘Z/⇧⌘Z undo and
    /// redo, Esc cancels a drag or leaves edit mode. Returns false for keys it doesn't use.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let host else { return false }
        if let calibration { return calibration.handleKey(event) }
        let flags = event.modifierFlags.intersection([.shift, .option, .command, .control])
        switch Int(event.keyCode) {
        case kVK_ANSI_Z where flags.contains(.command):
            if flags.contains(.shift) { redo() } else { undo() }
            return true
        case kVK_Escape:
            if gesture != nil { cancelGesture() } else { host.finishEditing() }
            return true
        case kVK_Tab:
            selectNext(backwards: flags.contains(.shift))
            return true
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelected()
            return true
        case kVK_LeftArrow: return arrow(.left, flags: flags)
        case kVK_RightArrow: return arrow(.right, flags: flags)
        case kVK_UpArrow: return arrow(.up, flags: flags)
        case kVK_DownArrow: return arrow(.down, flags: flags)
        default:
            return false
        }
    }

    /// One arrow press on the selected group: a 1-pixel nudge (⌥: 10), or with ⇧ a 1-pixel resize.
    /// Presses in a row join into one undo step.
    private func arrow(_ direction: NudgeDirection, flags: NSEvent.ModifierFlags) -> Bool {
        guard !flags.contains(.command), !flags.contains(.control) else { return false }
        guard gesture == nil, let host, let id = selectedGroupID, let placement = placement(of: id) else { return true }
        let display = placement.display
        var group = placement.group
        let action: String
        if flags.contains(.shift) {
            group.frame = EditMath.keyResized(
                group.frame, direction, largeStep: flags.contains(.option), scale: display.backingScale,
                minimumSize: group.minimumSize, display: display.localBounds
            )
            action = "Resize Group"
        } else {
            group.frame = EditMath.nudged(group.frame, direction, largeStep: flags.contains(.option), scale: display.backingScale, display: display.localBounds)
            action = "Nudge Group"
        }
        guard group.frame != placement.group.frame else { return true }
        host.beginLayoutGesture()
        host.previewGroup(group)
        host.endLayoutGesture(action, coalesceKey: "\(action)-\(id)")
        refreshCanvases()
        return true
    }

    func undo() {
        cancelGesture()
        host?.cancelLayoutGesture()
        host?.layoutHistory.undo()
        refresh()
    }

    func redo() {
        cancelGesture()
        host?.cancelLayoutGesture()
        host?.layoutHistory.redo()
        refresh()
    }

    // MARK: - Selection

    /// Placements left to right, by display (main first).
    var orderedPlacements: [GroupPlacement] {
        guard let host else { return [] }
        let order = Dictionary(uniqueKeysWithValues: host.connectedDisplays.enumerated().map { ($1.displayID, $0) })
        return host.groupPanels.map(\.placement).sorted { a, b in
            let da = order[a.display.displayID] ?? Int.max, db = order[b.display.displayID] ?? Int.max
            if da != db { return da < db }
            if a.group.frame.minX != b.group.frame.minX { return a.group.frame.minX < b.group.frame.minX }
            return a.group.frame.minY < b.group.frame.minY
        }
    }

    func placement(of id: UUID) -> GroupPlacement? {
        host?.groupPanels.first { $0.groupID == id }?.placement
    }

    /// Selects a group; `focus` makes its panel key so arrow keys reach it.
    func select(_ id: UUID?, focus: Bool) {
        if id != selectedGroupID {
            host?.layoutHistory.breakCoalescing()
            selectedGroupID = id
        }
        refreshCanvases()
        if focus { focusSelected() }
    }

    func selectNext(backwards: Bool) {
        let ordered = orderedPlacements
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.group.id == selectedGroupID }
        let next: Int
        if let index {
            next = (index + (backwards ? ordered.count - 1 : 1)) % ordered.count
        } else {
            next = backwards ? ordered.count - 1 : 0
        }
        select(ordered[next].group.id, focus: true)
    }

    /// Removes the selected group (undoable) and selects its neighbour.
    func deleteSelected() {
        guard let host, let id = selectedGroupID else { return }
        let ordered = orderedPlacements
        var neighbour: UUID?
        if let index = ordered.firstIndex(where: { $0.group.id == id }) {
            neighbour = index + 1 < ordered.count ? ordered[index + 1].group.id : (index > 0 ? ordered[index - 1].group.id : nil)
        }
        host.deleteGroup(id)
        select(neighbour, focus: true)
    }

    /// Makes the selected group's panel key, so keys reach the editor.
    func focusSelected() {
        guard takesKeyFocus, calibration == nil, let id = selectedGroupID, let controller = host?.panel(forGroup: id) else { return }
        controller.panel.makeKey()
        controller.panel.makeFirstResponder(controller.hostView)
    }

    // MARK: - Calibration

    /// Shows the calibration markers over a group.
    func beginCalibration(of id: UUID) {
        guard isEditing, calibration == nil, let placement = placement(of: id) else { return }
        cancelGesture()
        select(id, focus: false)
        let session = CalibrationSession(group: placement.group, display: placement.display) { [weak self] in
            self?.pointerLocation() ?? NSEvent.mouseLocation
        }
        session.onFinish = { [weak self] session, apply in self?.finishCalibration(session, apply: apply) }
        calibration = session
        session.show(makeKey: takesKeyFocus)
        refreshCanvases()
    }

    /// Ends a calibration; `apply` sets the group's frame from the markers (one undo step).
    func finishCalibration(_ session: CalibrationSession, apply: Bool) {
        guard calibration === session else { return }
        calibration = nil
        session.close()
        if apply {
            host?.calibrateGroup(session.groupID, firstCenterX: session.model.firstCenterX, lastCenterX: session.model.lastCenterX)
        }
        refresh()
        focusSelected()
    }

    // MARK: - Drawing

    /// Re-syncs canvases, cursor views and the selection with the panels on screen.
    func refresh() {
        guard let host else { return }
        let placements = host.groupPanels.map(\.placement)
        if let id = selectedGroupID, !placements.contains(where: { $0.group.id == id }) {
            selectedGroupID = orderedPlacements.first?.group.id
        }
        if let calibration, !placements.contains(where: { $0.group.id == calibration.groupID }) {
            finishCalibration(calibration, apply: false)
            return
        }
        syncCanvases(placements: placements, displays: host.connectedDisplays)
        syncCursorViews(host.groupPanels)
    }

    /// Redraws the canvases from the current placements (cheap; done on every drag step).
    func refreshCanvases() {
        guard let host else { return }
        let placements = host.groupPanels.map(\.placement)
        for (displayID, canvas) in canvases {
            guard let display = host.connectedDisplays.first(where: { $0.displayID == displayID }) else { continue }
            canvas.canvasView.setModel(canvasModel(for: display, placements: placements))
        }
        for (id, view) in cursorViews {
            if let controller = host.panel(forGroup: id) { view.groupRect = controller.bankView.frame }
        }
    }

    private func syncCanvases(placements: [GroupPlacement], displays: [ConnectedDisplay]) {
        var needed: [CGDirectDisplayID: ConnectedDisplay] = [:]
        for placement in placements { needed[placement.display.displayID] = placement.display }
        if placements.isEmpty, let main = displays.first { needed[main.displayID] = main }
        for (id, canvas) in canvases where needed[id] == nil {
            canvas.orderOut(nil)
            canvas.close()
            canvases[id] = nil
        }
        for (id, display) in needed {
            let frame = displays.first { $0.displayID == id }?.frame ?? display.frame
            if let canvas = canvases[id] {
                canvas.cover(frame)
            } else {
                let canvas = EditCanvasPanel(frame: frame)
                canvases[id] = canvas
                canvas.orderFrontRegardless()
            }
        }
        refreshCanvases()
    }

    private func syncCursorViews(_ controllers: [GroupPanelController]) {
        var kept: [UUID: EditCursorView] = [:]
        for controller in controllers {
            let view = cursorViews[controller.groupID] ?? EditCursorView(frame: controller.hostView.bounds)
            if view.superview !== controller.hostView {
                view.removeFromSuperview()
                controller.hostView.addSubview(view, positioned: .above, relativeTo: controller.bankView)
            }
            view.frame = controller.hostView.bounds
            view.autoresizingMask = [.width, .height]
            view.groupRect = controller.bankView.frame
            kept[controller.groupID] = view
        }
        for (id, view) in cursorViews where kept[id] !== view { view.removeFromSuperview() }
        cursorViews = kept
    }

    /// What `display`'s canvas shows.
    func canvasModel(for display: ConnectedDisplay, placements: [GroupPlacement]) -> EditCanvasModel {
        var model = EditCanvasModel()
        let onDisplay = placements.filter { $0.display.displayID == display.displayID }
        model.groups = onDisplay.map { placement in
            EditCanvasModel.Group(
                id: placement.group.id,
                frame: placement.group.frame,
                title: Self.title(of: placement.group),
                detail: BindingText.summary(of: placement.group),
                isSelected: placement.group.id == selectedGroupID,
                showsTab: calibration?.groupID != placement.group.id
            )
        }
        if let guides = snapGuides, guides.displayID == display.displayID {
            model.guideX = guides.x
            model.guideY = guides.y
        }
        if calibration == nil, let id = selectedGroupID, let selected = onDisplay.first(where: { $0.group.id == id }) {
            model.hud = hud(for: selected)
        }
        if placements.isEmpty {
            let name = host?.activeProfile?.name ?? "this profile"
            model.message = "“\(name)” has no meter groups. Add one from the menu bar: Add Strip Group."
        }
        return model
    }

    /// The HUD for the selected group: its frame in points and pixels, its pitch, and the shortcuts.
    func hud(for placement: GroupPlacement) -> EditCanvasModel.HUD {
        let group = placement.group
        let frame = group.frame
        let scale = placement.display.backingScale
        var lines = [
            "Points  x \(Self.number(frame.minX))  y \(Self.number(frame.minY))  w \(Self.number(frame.width))  h \(Self.number(frame.height))",
            "Pixels  x \(Self.number(frame.minX * scale))  y \(Self.number(frame.minY * scale))  w \(Self.number(frame.width * scale))  h \(Self.number(frame.height * scale))  @\(Self.number(scale))x",
        ]
        var pitch = "Pitch   \(Self.number(group.stripWidth, digits: 2)) pt"
        if let scalePerMM = pointsPerMillimeter(for: placement) {
            pitch += String(format: " = %.2f mm at %.3f pt/mm", Double(group.stripWidth) / scalePerMM, scalePerMM)
        }
        lines.append(pitch)
        if placement.isFallback {
            lines.append("Shown on this display because its own display isn’t connected; edits keep it here.")
        }
        let hints = [
            "Drag: move · drag an edge: resize · ⇧ fine ×0.1 · ⌘ no snapping",
            "←→↑↓ 1 px · ⌥ 10 px · ⇧+arrows: width/height · Tab: next group",
            "⌫ delete · ⌘Z undo · ⇧⌘Z redo · right-click: options · Esc: done",
        ]
        return EditCanvasModel.HUD(
            anchor: frame,
            title: "\(Self.title(of: group)) · \(BindingText.describe(group.binding, stripCount: group.stripCount))",
            lines: lines,
            hints: hints
        )
    }

    /// The display scale used for millimetres: the layout's (from a template or calibration), else EDID.
    private func pointsPerMillimeter(for placement: GroupPlacement) -> Double? {
        if let profile = host?.activeProfile, let location = profile.location(ofGroup: placement.group.id),
           let scale = profile.displays[location.display].pointsPerMillimeter, !placement.isFallback {
            return scale
        }
        return placement.display.pointsPerMillimeter
    }

    private func otherFrames(on display: ConnectedDisplay, excluding id: UUID) -> [CGRect] {
        (host?.groupPanels ?? [])
            .map(\.placement)
            .filter { $0.display.displayID == display.displayID && $0.group.id != id }
            .map(\.group.frame)
    }

    // MARK: - Text

    static func title(of group: StripGroup) -> String {
        group.name.isEmpty ? "Untitled group" : group.name
    }

    /// A value with up to `digits` decimals and no trailing zeros ("841.5", "0", "112.19").
    nonisolated static func number(_ value: CGFloat, digits: Int = 2) -> String {
        var text = String(format: "%.\(digits)f", Double(value))
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// Canvas models of every display, for `--demo-edit` snapshots.
    var canvasModels: [CGDirectDisplayID: EditCanvasModel] {
        canvases.mapValues(\.canvasView.model)
    }

    /// The canvas window of a display, for `--demo-edit` snapshots.
    func canvas(for displayID: CGDirectDisplayID) -> EditCanvasPanel? {
        canvases[displayID]
    }
}
