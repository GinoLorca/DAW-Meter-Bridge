import AppKit
import BridgeLayout
import Carbon.HIToolbox
import MeterCore
import MeterRendering
import SwiftUI

/// Hidden `--demo-edit <dir>`: runs the real app with panels on screen, enters edit mode and drives the
/// layout editor with scripted pointer positions, synthesized mouse and key events and a calibration,
/// checking each result against values computed independently here. Writes report.json and PNGs of the
/// edit-mode look to `<dir>`, then quits with 0 when every check passed.
///
/// It never takes keyboard focus (panels are not made key) and keeps its data in `<dir>/data` unless
/// `--data-dir` says otherwise.
@MainActor
final class EditDemo {
    struct Check: Encodable {
        var name: String
        var passed: Bool
        var expected: String
        var actual: String
    }

    struct Report: Encodable {
        var passed: Bool
        var checks: [Check]
        var display: String
        var backingScale: Double
        var images: [String]
        var finalLayouts: String
    }

    let controller: AppController
    let editor: LayoutEditorController
    let directory: URL
    private var pointer = CGPoint.zero
    private var checks: [Check] = []
    private var images: [String] = []
    private var scriptedText = ""

    init(controller: AppController, editor: LayoutEditorController, directory: URL) {
        self.controller = controller
        self.editor = editor
        self.directory = directory
    }

    func run(completion: @escaping @MainActor (Int32) -> Void) {
        editor.pointerLocation = { [weak self] in self?.pointer ?? .zero }
        editor.takesKeyFocus = false
        editor.textPrompt = { [weak self] _, _, initial in self?.scriptedText ?? initial }
        Task { @MainActor in
            let code = await self.script()
            self.controller.shutdown()
            completion(code)
        }
    }

    // MARK: - Script

    private func script() async -> Int32 {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("demo-edit: cannot create \(directory.path): \(error)\n".utf8))
            return 1
        }
        // A known start: the first-run layouts, no history, bridge shown.
        controller.resetLayouts()
        controller.layoutHistory.removeAll()
        controller.setBridgeVisible(true)
        await pause(0.4)
        let initialDocument = controller.document

        guard let first = editor.placementsForDemo.first ?? controller.presentation.placements.first else {
            record("a group is placed", false, "one group", "none")
            return finish(initial: initialDocument)
        }
        let id = first.group.id
        let display = first.display
        let scale = display.backingScale
        let pixel = 1 / scale
        let firstRun = controller.document.activeProfile?.allGroups ?? []
        record("first-run Bronx profile is the UF8 | UF1 row",
               firstRun.map(\.name) == ["UF8", "UF1"] && firstRun.last?.binding == .selectedTrack && first.group.name == "UF8",
               "UF8, UF1 (selected track)", firstRun.map { "\($0.name) (\($0.binding))" }.joined(separator: ", "))
        await snapshot("01-start-bridge-mode", group: id)

        // Edit mode on.
        controller.setEditing(true)
        await pause(0.3)
        record("edit mode is on", editor.isEditing && controller.isEditing, "true", "\(editor.isEditing)")
        record("the first group is selected", editor.selectedGroupID == id, "\(id)", "\(String(describing: editor.selectedGroupID))")
        let panel = controller.panel(forGroup: id)
        record("panel becomes key-capable", panel?.panel.canBecomeKey == true, "true", "\(String(describing: panel?.panel.canBecomeKey))")
        record("bank shows strip guides", panel?.bankView.isEditing == true, "true", "\(String(describing: panel?.bankView.isEditing))")
        let model = editor.canvasModels[display.displayID]
        record("canvas outlines the selected group with a HUD",
               model?.groups.contains { $0.id == id && $0.isSelected } == true && model?.hud != nil,
               "selected outline + HUD", "\(model?.groups.count ?? 0) group(s), HUD \(model?.hud != nil)")
        await snapshot("02-edit-mode", group: id)

        // 1. Shift-drag: ten moves of (10, 6) points move the group (10, 6) in total.
        var start = frame(id)
        await drag(id, from: center(id), by: CGVector(dx: 100, dy: 60), steps: 10, flags: .shift)
        expectFrame("Shift-drag moves ×0.1 (100, 60 → 10, 6)", id, start.offsetBy(dx: 10, dy: 6))
        expectPanelMatches(id)

        // 2. A fine drag of 0.3 pt lands on the device-pixel grid.
        start = frame(id)
        await drag(id, from: center(id), by: CGVector(dx: 3, dy: 0), steps: 3, flags: .shift)
        expectFrame("fine sub-point drag snaps to device pixels", id,
                    CGRect(origin: CGPoint(x: PixelGrid(scale: scale).snap(start.minX + 0.3), y: start.minY), size: start.size))

        // 3. Plain drag.
        start = frame(id)
        await drag(id, from: center(id), by: CGVector(dx: 150, dy: 40), steps: 5, flags: [])
        expectFrame("plain drag moves 1:1 (150, 40)", id, start.offsetBy(dx: 150, dy: 40))

        // 4. Dragging to 5 pt above the display's bottom snaps to the edge and shows a guide.
        start = frame(id)
        let guides = await drag(id, from: center(id), by: CGVector(dx: 0, dy: -(start.minY - 5)), steps: 4, flags: [])
        expectFrame("drag near the bottom edge snaps to it", id, CGRect(x: start.minX, y: 0, width: start.width, height: start.height))
        record("snap guide at the display edge", guides?.y == 0, "guide y 0", "\(String(describing: guides?.y))")

        // 5. The same with Command held does not snap.
        start = frame(id)
        let noGuides = await drag(id, from: center(id), by: CGVector(dx: 0, dy: 5), steps: 2, flags: .command)
        expectFrame("⌘-drag does not snap", id, start.offsetBy(dx: 0, dy: 5))
        record("no guide with ⌘", noGuides == nil, "none", "\(String(describing: noGuides))")

        // 6. Resizing: right edge with Shift (+50 → +5), left edge plain (-30), top edge with Shift (+100 → +10).
        start = frame(id)
        await drag(id, from: edgePoint(id, .right), by: CGVector(dx: 50, dy: 0), steps: 5, flags: .shift)
        expectFrame("⇧-drag of the right edge resizes ×0.1", id, CGRect(x: start.minX, y: start.minY, width: start.width + 5, height: start.height))
        start = frame(id)
        await drag(id, from: edgePoint(id, .left), by: CGVector(dx: -30, dy: 0), steps: 3, flags: [])
        expectFrame("dragging the left edge resizes", id, CGRect(x: start.minX - 30, y: start.minY, width: start.width + 30, height: start.height))
        start = frame(id)
        await drag(id, from: edgePoint(id, .top), by: CGVector(dx: 0, dy: 100), steps: 4, flags: .shift)
        expectFrame("⇧-drag of the top edge resizes ×0.1", id, CGRect(x: start.minX, y: start.minY, width: start.width, height: start.height + 10))
        await snapshot("03-after-mouse-edits", group: id)

        // 7. Keys: → 1 px, ⌥← 10 px, ⇧→ +1 px wide, ⇧⌥↑ +10 px high, ⇧↓ −1 px high.
        start = frame(id)
        key(kVK_RightArrow)
        expectFrame("→ nudges 1 device pixel", id, start.offsetBy(dx: pixel, dy: 0))
        key(kVK_LeftArrow, [.option])
        expectFrame("⌥← nudges 10 device pixels", id, start.offsetBy(dx: pixel - 10 * pixel, dy: 0))
        let afterNudges = frame(id)
        key(kVK_RightArrow, [.shift])
        key(kVK_UpArrow, [.shift, .option])
        key(kVK_DownArrow, [.shift])
        expectFrame("⇧-arrows resize by device pixels", id,
                    CGRect(x: afterNudges.minX, y: afterNudges.minY, width: afterNudges.width + pixel, height: afterNudges.height + 9 * pixel))
        let afterKeys = frame(id)
        key(kVK_ANSI_Z, [.command])
        expectFrame("⌘Z undoes the key resizes as one step", id, afterNudges)
        key(kVK_ANSI_Z, [.command, .shift])
        expectFrame("⇧⌘Z redoes them", id, afterKeys)

        // 8. Add the UF1 meter: it lands where the UF1 sits next to the UF8 (Bronx row), measured from the UF8.
        let uf8 = group(id)
        let added = controller.addGroups(from: LayoutTemplates.uf1, on: display)
        await pause(0.2)
        if let uf1ID = added.first, let uf1 = controller.document.activeProfile?.group(withID: uf1ID) {
            let scalePerMM = Double(uf8.stripWidth) / SurfaceTemplate.uf8PitchMillimeters
            let expectedCenter = uf8.stripCenterX(at: 0) + CGFloat((431.0 + 45.0 - 84.3) * scalePerMM)
            record("UF1 meter sits 391.7 mm right of UF8 fader 1",
                   abs(uf1.stripCenterX(at: 0) - expectedCenter) < 0.01 && abs(uf1.frame.width - uf8.stripWidth) < 0.01,
                   "centre \(EditDemo.text(expectedCenter)), width \(EditDemo.text(uf8.stripWidth))",
                   "centre \(EditDemo.text(uf1.stripCenterX(at: 0))), width \(EditDemo.text(uf1.frame.width)), visible \(uf1.isVisible)")
            editor.select(id, focus: false)
            key(kVK_Tab)
            // The first-run row already has a UF1 meter at the same spot; either one is "next to the right".
            let uf1IDs = Set(firstRun.filter { $0.name == "UF1" }.map(\.id) + [uf1ID])
            record("Tab selects the next group to the right", editor.selectedGroupID.map(uf1IDs.contains) == true || !uf1.isVisible,
                   uf1IDs.map(\.uuidString).sorted().joined(separator: " or "), "\(String(describing: editor.selectedGroupID))")
            editor.select(id, focus: false)
        } else {
            record("Add Strip Group adds the UF1 meter", false, "1 group", "\(added.count)")
        }

        // 9. Calibration: marker 1 dragged 20.5 pt left; marker 8 dragged 30 pt right, then 40 more with Shift (+4).
        let before = group(id)
        editor.beginCalibration(of: id)
        await pause(0.2)
        if let session = editor.calibration {
            record("calibration starts with markers on strips 1 and 8",
                   session.model.markers == [before.stripCenterX(at: 0), before.stripCenterX(at: before.stripCount - 1)],
                   "\(EditDemo.text(before.stripCenterX(at: 0))), \(EditDemo.text(before.stripCenterX(at: before.stripCount - 1)))",
                   session.model.markers.map(EditDemo.text).joined(separator: ", "))
            let origin = display.frame.origin
            let markerY = origin.y + before.frame.midY
            pointer = CGPoint(x: origin.x + session.model.markers[0], y: markerY)
            session.mouseDown()
            for step in 1...5 {
                pointer.x = origin.x + before.stripCenterX(at: 0) - 20.5 * CGFloat(step) / 5
                session.mouseDragged(fine: false)
            }
            session.mouseUp()
            pointer = CGPoint(x: origin.x + session.model.markers[1], y: markerY)
            session.mouseDown()
            pointer.x += 30
            session.mouseDragged(fine: false)
            for _ in 1...4 {
                pointer.x += 10
                session.mouseDragged(fine: true)
            }
            session.mouseUp()
            let firstX = PixelGrid(scale: scale).snap(before.stripCenterX(at: 0) - 20.5)
            let lastX = PixelGrid(scale: scale).snap(before.stripCenterX(at: before.stripCount - 1) + 34)
            record("markers follow the pointer (⇧ = ×0.1)", session.model.markers == [firstX, lastX],
                   "\(EditDemo.text(firstX)), \(EditDemo.text(lastX))", session.model.markers.map(EditDemo.text).joined(separator: ", "))
            await snapshot("04-calibrating", group: id, calibration: session)
            session.apply()
            await pause(0.2)
            let pitch = (lastX - firstX) / CGFloat(before.stripCount - 1)
            expectFrame("Apply sets the two-point calibrated frame", id,
                        CGRect(x: firstX - pitch / 2, y: before.frame.minY, width: pitch * CGFloat(before.stripCount), height: before.frame.height))
            let calibrated = group(id)
            record("calibrated strip 1 and 8 centres are on the markers",
                   abs(calibrated.stripCenterX(at: 0) - firstX) < 1e-9 && abs(calibrated.stripCenterX(at: calibrated.stripCount - 1) - lastX) < 1e-9,
                   "\(EditDemo.text(firstX)) / \(EditDemo.text(lastX))",
                   "\(EditDemo.text(calibrated.stripCenterX(at: 0))) / \(EditDemo.text(calibrated.stripCenterX(at: calibrated.stripCount - 1)))")
            let storedScale = controller.document.activeProfile.flatMap { profile in
                profile.location(ofGroup: id).flatMap { profile.displays[$0.display].pointsPerMillimeter }
            }
            let expectedScale = Double(pitch) / SurfaceTemplate.uf8PitchMillimeters
            record("calibration stores the display's points per mm", storedScale.map { abs($0 - expectedScale) < 1e-9 } == true,
                   String(format: "%.6f", expectedScale), storedScale.map { String(format: "%.6f", $0) } ?? "nil")
            record("calibration is one undo step", controller.layoutHistory.undoActionName == "Calibrate Group",
                   "Calibrate Group", controller.layoutHistory.undoActionName)
        } else {
            record("calibration starts", false, "a session", "none")
        }
        await snapshot("05-calibrated", group: id)

        // 10. Menu commands on the group: strip count, binding, rename, duplicate, delete.
        let pitchBefore = group(id).stripWidth
        controller.setStripCount(6, ofGroup: id)
        record("Strips ▸ 6 keeps the pitch", group(id).stripCount == 6 && abs(group(id).frame.width - 6 * pitchBefore) < 1e-9,
               "6 strips, width \(EditDemo.text(6 * pitchBefore))", "\(group(id).stripCount) strips, width \(EditDemo.text(group(id).frame.width))")
        controller.setStripCount(8, ofGroup: id)
        controller.setBinding(.trackList(offset: 8), ofGroup: id)
        record("Binding ▸ Track List from 9", group(id).binding == .trackList(offset: 8), "trackList(8)", "\(group(id).binding)")
        controller.setBinding(.surfaceUnit(index: 0, firstStrip: 0), ofGroup: id)
        if let placement = editor.placement(of: id) {
            let items = GroupMenu.items(for: placement, editor: editor, host: controller)
            let titles = items.map(\.title)
            let wanted = ["Binding", "Strips", "Rename…", "Move to Display", "Calibrate…", "Duplicate", "Delete"]
            record("right-click menu has every command", wanted.allSatisfy(titles.contains), wanted.joined(separator: ", "), titles.joined(separator: ", "))
            scriptedText = "UF8 Bronx"
            items.first { $0.title == "Rename…" }.map { invoke($0) }
            record("Rename… renames the group", group(id).name == "UF8 Bronx", "UF8 Bronx", group(id).name)
        }
        let groupCount = controller.document.activeProfile?.allGroups.count ?? 0
        let copy = controller.duplicateGroup(id)
        let copyFrame = copy.flatMap { controller.document.activeProfile?.group(withID: $0)?.frame }
        record("Duplicate adds a non-overlapping copy",
               copy != nil && (controller.document.activeProfile?.allGroups.count ?? 0) == groupCount + 1 && copyFrame.map { !$0.intersects(frame(id)) } == true,
               "\(groupCount + 1) groups", "\(controller.document.activeProfile?.allGroups.count ?? 0) groups, copy at \(String(describing: copyFrame))")
        if let copy {
            editor.select(copy, focus: false)
            key(kVK_Delete)
            record("Delete removes the selected group", controller.document.activeProfile?.group(withID: copy) == nil, "removed", "still there: \(controller.document.activeProfile?.group(withID: copy) != nil)")
            editor.select(id, focus: false)
        }

        // 11. Move to another display (only when one is connected).
        if let other = controller.connectedDisplays.first(where: { $0.displayID != display.displayID }) {
            controller.moveGroup(id, to: other)
            record("Move to Display moves the group", editor.placement(of: id)?.display.displayID == other.displayID, other.name, editor.placement(of: id)?.display.name ?? "nil")
            controller.layoutHistory.undo()
        } else {
            record("Move to Display (skipped: one display connected)", true, "-", "-")
        }

        // 12. Profiles: a new WING profile becomes active; deleting it and undoing brings it back.
        let bronxID = controller.document.activeProfileID
        if let wingID = controller.newProfile(from: LayoutTemplates.wing) {
            await pause(0.2)
            record("New Profile from Template ▸ WING is active with 6 groups",
                   controller.document.activeProfileID == wingID && controller.document.activeProfile?.allGroups.count == 6,
                   "active, 6 groups", "active \(controller.document.activeProfileID == wingID), \(controller.document.activeProfile?.allGroups.count ?? 0) groups")
            record("its panels are shown", controller.groupPanels.count == controller.presentation.placements.count && !controller.groupPanels.isEmpty,
                   "\(controller.presentation.placements.count)", "\(controller.groupPanels.count)")
            controller.renameProfile(wingID, to: "Brooklyn test")
            controller.deleteProfile(wingID)
            record("Delete Profile removes it", controller.document.profile(withID: wingID) == nil, "removed", "present \(controller.document.profile(withID: wingID) != nil)")
            controller.layoutHistory.undo()
            record("undo brings the profile back", controller.document.profile(withID: wingID)?.name == "Brooklyn test", "Brooklyn test", controller.document.profile(withID: wingID)?.name ?? "nil")
            controller.chooseProfile(bronxID)
            record("Layout Profile ▸ switches back (undoable)",
                   controller.document.activeProfileID == bronxID && controller.layoutHistory.undoActionName == "Switch Profile",
                   "Bronx active, Undo Switch Profile",
                   "Bronx active \(controller.document.activeProfileID == bronxID), undo “\(controller.layoutHistory.undoActionName)”")
        }

        let finalDocument = controller.document
        await snapshot("06-final", group: id)

        // 13. Undo everything, then redo everything.
        var undoSteps = 0
        while controller.layoutHistory.canUndo, undoSteps < 500 {
            editor.undo()
            undoSteps += 1
        }
        record("undoing every step restores the first layout", controller.document == initialDocument, "first-run document", "\(undoSteps) steps undone, equal \(controller.document == initialDocument)")
        var redoSteps = 0
        while controller.layoutHistory.canRedo, redoSteps < 500 {
            editor.redo()
            redoSteps += 1
        }
        record("redoing every step restores the last layout", controller.document == finalDocument, "\(undoSteps) steps", "\(redoSteps) steps redone, equal \(controller.document == finalDocument)")

        // 14. Persistence: the debounced save reaches layouts.json.
        await pause(0.5)
        controller.flushPendingSaves()
        let saved = (try? Data(contentsOf: controller.layoutStore.url)).flatMap { try? JSONDecoder().decode(LayoutDocument.self, from: $0) }
        record("layouts.json holds the edited layout", saved == controller.document, "equal", saved == nil ? "unreadable" : "equal \(saved == controller.document)")

        // 15. Settings apply at once and are saved.
        await checkSettings(groupID: id)

        // 16. Leaving edit mode removes the canvases and guides.
        controller.setEditing(false)
        await pause(0.2)
        record("leaving edit mode removes the edit canvases", editor.canvasModels.isEmpty && controller.panel(forGroup: id)?.bankView.isEditing == false,
               "no canvases", "\(editor.canvasModels.count) canvases")
        return finish(initial: initialDocument, display: display)
    }

    // MARK: - Settings

    private func checkSettings(groupID id: UUID) async {
        let window = SettingsWindowController(controller: controller)
        let model = window.model
        model.update { settings in
            settings.style.showNames = false
            settings.style.segmentCount = 30
            settings.ballistics.peakHoldSeconds = 2.5
            settings.mixFocus.muteDim = 0.3
        }
        let bankStyle = controller.panel(forGroup: id)?.bankView.style
        record("settings apply at once (style, ballistics, dimming)",
               bankStyle?.showNames == false && bankStyle?.segmentCount == 30
                   && controller.store.settings.peakHoldSeconds == 2.5 && controller.settings.mixFocus.muteDim == 0.3,
               "names off, 30 segments, hold 2.5 s, mute dim 0.3",
               "names \(String(describing: bankStyle?.showNames)), \(bankStyle?.segmentCount ?? 0) segments, hold \(controller.store.settings.peakHoldSeconds), dim \(controller.settings.mixFocus.muteDim)")
        await pause(0.6)
        let saved = controller.paths.settingsFileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        record("settings are saved (debounced)", saved?.style.showNames == false && saved?.ballistics.peakHoldSeconds == 2.5,
               "saved", saved == nil ? "not saved" : "names \(saved!.style.showNames), hold \(saved!.ballistics.peakHoldSeconds)")
        renderSettings(model)
        model.restoreDefaultMeterSettings()
        record("Restore Default Meter Settings", controller.settings.style == .standard && controller.settings.mixFocus == .standard,
               "defaults", "style default \(controller.settings.style == .standard)")
    }

    /// Renders the settings window's SwiftUI content offscreen to settings.png.
    private func renderSettings(_ model: SettingsModel) {
        let size = CGSize(width: 540, height: 1480)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsView(model: model).frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("settings.png"), options: .atomic)
            images.append("settings.png")
        }
        window.close()
    }

    // MARK: - Driving the editor

    /// Presses at `start` (global), moves by `raw` in `steps` with `flags`, and releases.
    /// Returns the snap guides seen on the last step.
    @discardableResult
    private func drag(_ id: UUID, from start: CGPoint, by raw: CGVector, steps: Int, flags: NSEvent.ModifierFlags) async -> (x: CGFloat?, y: CGFloat?)? {
        guard let panel = controller.panel(forGroup: id) else { return nil }
        pointer = start
        editor.groupPanel(panel, mouseDown: mouseEvent(.leftMouseDown, flags: [], panel: panel))
        for step in 1...max(1, steps) {
            pointer = CGPoint(x: start.x + raw.dx * CGFloat(step) / CGFloat(steps), y: start.y + raw.dy * CGFloat(step) / CGFloat(steps))
            guard let current = controller.panel(forGroup: id) else { break }
            editor.groupPanel(current, mouseDragged: mouseEvent(.leftMouseDragged, flags: flags, panel: current))
        }
        let guides = editor.snapGuides.map { (x: $0.x, y: $0.y) }
        await pause(0.05)
        if let current = controller.panel(forGroup: id) {
            editor.groupPanel(current, mouseUp: mouseEvent(.leftMouseUp, flags: flags, panel: current))
        }
        await pause(0.05)
        return guides
    }

    private func key(_ code: Int, _ flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)
        ) else { return }
        _ = editor.handleKey(event)
    }

    private func mouseEvent(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags, panel: GroupPanelController) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
        )!
    }

    private func invoke(_ item: NSMenuItem) {
        guard let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private func group(_ id: UUID) -> StripGroup {
        editor.placement(of: id)?.group ?? controller.document.activeProfile?.group(withID: id)
            ?? StripGroup(name: "missing", binding: .mainTrack, stripCount: 1, frame: .zero)
    }

    private func frame(_ id: UUID) -> CGRect { group(id).frame }

    private func center(_ id: UUID) -> CGPoint {
        guard let placement = editor.placement(of: id) else { return .zero }
        return CGPoint(x: placement.globalFrame.midX, y: placement.globalFrame.midY)
    }

    /// A point 3 pt inside an edge of the group, in global coordinates.
    private func edgePoint(_ id: UUID, _ edge: RectEdge) -> CGPoint {
        guard let placement = editor.placement(of: id) else { return .zero }
        let f = placement.globalFrame
        switch edge {
        case .left: return CGPoint(x: f.minX + 3, y: f.midY)
        case .right: return CGPoint(x: f.maxX - 3, y: f.midY)
        case .bottom: return CGPoint(x: f.midX, y: f.minY + 3)
        case .top: return CGPoint(x: f.midX, y: f.maxY - 3)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    // MARK: - Checks

    private func record(_ name: String, _ passed: Bool, _ expected: String, _ actual: String) {
        checks.append(Check(name: name, passed: passed, expected: expected, actual: actual))
        print("\(passed ? "PASS" : "FAIL")  \(name)\(passed ? "" : "  expected \(expected), got \(actual)")")
    }

    private func expectFrame(_ name: String, _ id: UUID, _ expected: CGRect) {
        let actual = frame(id)
        let close = abs(actual.minX - expected.minX) < 1e-6 && abs(actual.minY - expected.minY) < 1e-6
            && abs(actual.width - expected.width) < 1e-6 && abs(actual.height - expected.height) < 1e-6
        record(name, close, Self.text(expected), Self.text(actual))
    }

    /// The panel covers the group rounded outward to whole points and the bank sits at the exact frame.
    private func expectPanelMatches(_ id: UUID) {
        guard let controller = controller.panel(forGroup: id) else {
            record("panel follows the group", false, "a panel", "none")
            return
        }
        let global = controller.placement.globalFrame
        let expectedPanel = NSIntegralRectWithOptions(global, .alignAllEdgesOutward)
        let bankOrigin = CGPoint(x: global.minX - expectedPanel.minX, y: global.minY - expectedPanel.minY)
        record("panel window follows the group (whole points, bank at the exact frame)",
               controller.panel.frame == expectedPanel && controller.bankView.frame.origin == bankOrigin && controller.bankView.frame.size == global.size,
               "\(Self.text(expectedPanel)), bank at \(Self.text(bankOrigin.x)),\(Self.text(bankOrigin.y))",
               "\(Self.text(controller.panel.frame)), bank at \(Self.text(controller.bankView.frame.minX)),\(Self.text(controller.bankView.frame.minY))")
    }

    private func finish(initial: LayoutDocument, display: ConnectedDisplay? = nil) -> Int32 {
        let passed = !checks.isEmpty && checks.allSatisfy(\.passed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let report = Report(
            passed: passed,
            checks: checks,
            display: display?.menuTitle ?? "-",
            backingScale: Double(display?.backingScale ?? 0),
            images: images,
            finalLayouts: controller.layoutStore.url.path
        )
        do {
            try encoder.encode(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("demo-edit: cannot write report: \(error)\n".utf8))
            return 1
        }
        let failed = checks.filter { !$0.passed }.count
        print("demo-edit: \(checks.count - failed)/\(checks.count) checks passed. Report and images in \(directory.path)")
        return passed ? 0 : 1
    }

    static func text(_ value: CGFloat) -> String { LayoutEditorController.number(value, digits: 3) }

    static func text(_ rect: CGRect) -> String {
        "x \(text(rect.minX)) y \(text(rect.minY)) w \(text(rect.width)) h \(text(rect.height))"
    }

    // MARK: - Snapshots

    /// Renders what edit mode shows around a group: the bank as drawn now, the canvas on top (outline, tab,
    /// handles, HUD) and, while calibrating, the markers. The desktop behind is drawn dark grey.
    private func snapshot(_ name: String, group id: UUID, calibration: CalibrationSession? = nil) async {
        await pause(0.1)
        guard let placement = controller.presentation.placements.first(where: { $0.group.id == id }) else { return }
        let display = placement.display
        let scale = display.backingScale
        var region = placement.group.frame.insetBy(dx: -24, dy: -24)
        if let model = editor.canvasModels[display.displayID] {
            let layout = EditCanvasLayout(model: model, bounds: display.localBounds)
            for rect in layout.regions(of: model, bounds: display.localBounds) where rect.width < display.localBounds.width {
                region = region.union(rect.insetBy(dx: -8, dy: -8))
            }
        }
        if let calibration { region = region.union(calibration.band) }
        region = region.intersection(display.localBounds).integral
        guard region.width > 0, region.height > 0,
              let context = CGContext(
                data: nil, width: Int(region.width * scale), height: Int(region.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 0.18, alpha: 1))
        context.fill(CGRect(origin: .zero, size: region.size))

        for other in controller.presentation.placements where other.display.displayID == display.displayID && other.group.frame.intersects(region) {
            guard let bank = controller.panel(forGroup: other.group.id)?.bankView.renderImage() else { continue }
            context.draw(bank, in: other.group.frame.offsetBy(dx: -region.minX, dy: -region.minY))
        }
        if let canvas = editor.canvas(for: display.displayID)?.canvasView {
            draw(canvas, rect: region, into: context, at: .zero)
        }
        if let view = calibration?.panel?.calibrationView {
            let band = calibration!.band
            draw(view, rect: view.bounds, into: context, at: CGPoint(x: band.minX - region.minX, y: band.minY - region.minY))
        }
        guard let image = context.makeImage(), let png = BankView.pngData(from: image, scale: scale) else { return }
        let fileName = "\(name).png"
        do {
            try png.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            images.append(fileName)
        } catch {
            FileHandle.standardError.write(Data("demo-edit: cannot write \(fileName): \(error)\n".utf8))
        }
    }

    /// Draws `rect` of an AppKit view into `context` with its lower-left corner at `origin`.
    private func draw(_ view: NSView, rect: CGRect, into context: CGContext, at origin: CGPoint) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        guard let image = rep.cgImage else { return }
        context.draw(image, in: CGRect(origin: origin, size: rect.size))
    }
}

extension LayoutEditorController {
    /// Placements in the editor's left-to-right order (for `--demo-edit`).
    var placementsForDemo: [GroupPlacement] { orderedPlacements }
}
