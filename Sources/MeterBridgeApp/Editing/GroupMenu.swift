import AppKit
import BridgeLayout

/// The right-click menu of a group in edit mode (also under "Selected Group" in the menu-bar menu).
@MainActor
enum GroupMenu {
    /// Surface units offered for binding (a UF8 is 1 unit, the WING in MCU + 2 XT mode is 3).
    static let surfaceUnitCount = 4
    /// Track-list starting points offered directly; "Other…" asks for a track number (1–10000).
    static let trackListOffsets = [0, 8, 16, 24, 32, 40]

    static func items(for placement: GroupPlacement, editor: LayoutEditorController, host: any LayoutEditHost) -> [NSMenuItem] {
        let group = placement.group
        let id = group.id
        let title = LayoutEditorController.title(of: group)
        var items: [NSMenuItem] = [.info("\(title) · \(BindingText.summary(of: group))")]

        items.append(.submenu("Binding", items: bindingItems(for: group, editor: editor, host: host)))
        items.append(.submenu("Strips", items: (1...LayoutEdits.maximumStripCount).map { count in
            MenuActionItem("\(count)", state: count == group.stripCount ? .on : .off) { [weak host] in
                host?.setStripCount(count, ofGroup: id)
            }
        }))
        items.append(MenuActionItem("Rename…") { [weak editor, weak host] in
            guard let editor, let host else { return }
            if let name = editor.textPrompt("Rename Group", "New name for “\(title)”:", group.name) {
                host.renameGroup(id, to: name)
            }
            editor.focusSelected()
        })
        items.append(.submenu("Move to Display", items: host.connectedDisplays.map { display in
            let isCurrent = display.displayID == placement.display.displayID
            let item = MenuActionItem(display.menuTitle, state: isCurrent ? .on : .off, isEnabled: !isCurrent) { [weak editor, weak host] in
                host?.moveGroup(id, to: display)
                editor?.select(id, focus: true)
            }
            if display.pointsPerMillimeter == nil, !isCurrent {
                item.toolTip = "This display doesn’t report a usable physical size, so the group is scaled to it."
            }
            return item
        }))
        items.append(MenuActionItem("Calibrate…") { [weak editor] in editor?.beginCalibration(of: id) })
        items.append(MenuActionItem("Duplicate") { [weak editor, weak host] in
            if let copy = host?.duplicateGroup(id) { editor?.select(copy, focus: true) }
        })
        items.append(MenuActionItem("Delete") { [weak editor] in
            editor?.select(id, focus: false)
            editor?.deleteSelected()
        })
        items.append(.separator())
        items += undoItems(editor: editor, host: host)
        items.append(MenuActionItem("Done Editing") { [weak host] in host?.finishEditing() })
        return items
    }

    /// "Undo …" / "Redo …" for the layout history (disabled when there is nothing to undo or redo).
    static func undoItems(editor: LayoutEditorController?, host: any LayoutEditHost) -> [NSMenuItem] {
        let history = host.layoutHistory
        let undoTitle = history.canUndo && !history.undoActionName.isEmpty ? "Undo \(history.undoActionName)" : "Undo"
        let redoTitle = history.canRedo && !history.redoActionName.isEmpty ? "Redo \(history.redoActionName)" : "Redo"
        return [
            MenuActionItem(undoTitle, key: "z", modifiers: .command, isEnabled: history.canUndo) { [weak editor, weak host] in
                if let editor, editor.isEditing { editor.undo() } else { host?.layoutHistory.undo() }
            },
            MenuActionItem(redoTitle, key: "z", modifiers: [.command, .shift], isEnabled: history.canRedo) { [weak editor, weak host] in
                if let editor, editor.isEditing { editor.redo() } else { host?.layoutHistory.redo() }
            },
        ]
    }

    private static func bindingItems(for group: StripGroup, editor: LayoutEditorController, host: any LayoutEditHost) -> [NSMenuItem] {
        let id = group.id
        func item(_ title: String, _ binding: StripBinding) -> NSMenuItem {
            MenuActionItem(title, state: group.binding == binding ? .on : .off) { [weak host] in
                host?.setBinding(binding, ofGroup: id)
            }
        }
        var items: [NSMenuItem] = (0..<surfaceUnitCount).map { unit in
            let strips = (0..<StripBinding.stripsPerUnit).map { first in
                item("From Strip \(first + 1)", .surfaceUnit(index: unit, firstStrip: first))
            }
            let submenu = NSMenuItem.submenu("Surface Unit \(unit + 1)", items: strips)
            if case let .surfaceUnit(index, _) = group.binding, index == unit { submenu.state = .on }
            return submenu
        }
        items.append(.separator())
        items.append(item("Selected Track", .selectedTrack))
        items.append(item("Main Track", .mainTrack))

        var trackItems = trackListOffsets.map { offset in item("From Track \(offset + 1)", .trackList(offset: offset)) }
        trackItems.append(.separator())
        trackItems.append(MenuActionItem("Other…") { [weak editor, weak host] in
            guard let editor, let host else { return }
            var initial = "1"
            if case let .trackList(offset) = group.binding { initial = "\(offset + 1)" }
            if let text = editor.textPrompt("Track List", "Number of the first track this group shows (1 = the first track in Live):", initial),
               let number = Int(text.trimmingCharacters(in: .whitespaces)),
               (1...StripBinding.offsetRange.upperBound + 1).contains(number) {
                host.setBinding(.trackList(offset: number - 1), ofGroup: id)
            }
            editor.focusSelected()
        })
        let trackList = NSMenuItem.submenu("Track List", items: trackItems)
        if case .trackList = group.binding { trackList.state = .on }
        items.append(trackList)
        return items
    }
}
