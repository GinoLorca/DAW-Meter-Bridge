import AppKit
import BridgeLayout
import MeterCore

/// The menu-bar icon and its menu. The menu is rebuilt each time it opens, so it always shows the
/// current source status and warnings.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    /// ⌃⌥⌘, shown next to the items that have global hotkeys.
    static let hotKeyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private weak var controller: AppController?
    /// Opens the settings window ("Settings…").
    var openSettings: (() -> Void)?

    init(controller: AppController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    /// Refreshes the icon (a miniature meter bridge: lit while shown, at rest while the DAW isn't
    /// connected, dimmed and unlit while hidden) and its tooltip.
    func updateIcon() {
        guard let controller, let button = statusItem.button else { return }
        let state: MenuBarIcon.State
        if !controller.isBridgeVisible {
            state = .hidden
        } else {
            state = controller.snapshot.connection.isConnected ? .shown : .waiting
        }
        button.image = MenuBarIcon.image(for: state)
        button.title = ""
        let visibility = controller.isBridgeVisible ? "shown" : "hidden"
        button.toolTip = "DAW Meter Bridge (\(visibility))\n\(controller.sourceStatusLine)"
    }

    /// Opens the menu, as if the icon was clicked (a second launch asked this copy to show itself).
    func reveal() {
        Task { @MainActor [weak self] in self?.statusItem.button?.performClick(nil) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller else { return }
        buildItems(for: controller).forEach(menu.addItem)
    }

    private func buildItems(for controller: AppController) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        items.append(.info(controller.sourceStatusLine))
        for warning in controller.statusWarnings {
            items.append(.info(warning, symbol: "exclamationmark.triangle"))
        }
        items.append(.separator())

        items.append(MenuActionItem(
            controller.isBridgeVisible ? "Hide Bridge" : "Show Bridge",
            key: "m", modifiers: Self.hotKeyModifiers
        ) { [weak controller] in controller?.toggleBridgeVisible() })
        let mainItem = MenuActionItem(
            "Show Main Meter",
            state: controller.isMainMeterVisible ? .on : .off,
            isEnabled: controller.activeProfile != nil
        ) { [weak controller] in controller?.toggleMainMeter() }
        mainItem.toolTip = "The Main track’s meter at the right edge of the bridge display. Stream Deck and URLs: dawmeterbridge://main/toggle"
        items.append(mainItem)
        items.append(MenuActionItem(
            "Edit Layout", key: "e", modifiers: Self.hotKeyModifiers,
            state: controller.isEditing ? .on : .off
        ) { [weak controller] in controller?.toggleEditing() })
        if controller.isEditing, let editor = controller.layoutEditor {
            items += editor.menuItems(host: controller)
        }
        if controller.layoutHistory.canUndo || controller.layoutHistory.canRedo {
            items += GroupMenu.undoItems(editor: controller.layoutEditor as? LayoutEditorController, host: controller)
        }
        items.append(.separator())

        items.append(.submenu("Source", items: sourceItems(for: controller)))
        if let simulator = controller.activeSimulator {
            items.append(.submenu("Simulator", items: [
                MenuActionItem("Bank Left") { [weak simulator] in simulator?.bankLeft() },
                MenuActionItem("Bank Right") { [weak simulator] in simulator?.bankRight() },
                .separator(),
                MenuActionItem("1 Unit (SSL UF8)", state: simulator.unitCount == 1 ? .on : .off) { [weak controller] in
                    controller?.setSimulatorUnitCount(1)
                },
                MenuActionItem("3 Units (Behringer WING)", state: simulator.unitCount == 3 ? .on : .off) { [weak controller] in
                    controller?.setSimulatorUnitCount(3)
                },
            ]))
        }
        items.append(.submenu("Layout Profile", items: profileItems(for: controller)))
        items.append(.submenu("Add Strip Group", items: addGroupItems(for: controller)))
        items.append(.submenu("Move Bridge to Display", items: displayItems(for: controller)))
        items.append(MenuActionItem("Reset Peaks") { [weak controller] in controller?.resetAllPeaks() })
        items.append(.separator())

        items.append(MenuActionItem("Settings…", key: ",", modifiers: .command) { [weak self] in self?.openSettings?() })
        items.append(MenuActionItem("Install Live Script…") { LiveScriptHelp.present() })
        items.append(.separator())
        items.append(MenuActionItem("Quit DAW Meter Bridge", key: "q", modifiers: .command) {
            NSApp.terminate(nil)
        })
        return items
    }

    private func sourceItems(for controller: AppController) -> [NSMenuItem] {
        var items: [NSMenuItem] = SourceKind.allCases.map { kind in
            MenuActionItem(kind.title, state: controller.sourceKind == kind ? .on : .off) { [weak controller] in
                guard let controller, controller.sourceKind != kind else { return }
                controller.activateSource(kind)
            }
        }
        items.append(.separator())
        items.append(.info(controller.sourceStatusLine))
        for warning in controller.snapshot.warnings {
            items.append(.info(warning, symbol: "exclamationmark.triangle"))
        }
        return items
    }

    private func profileItems(for controller: AppController) -> [NSMenuItem] {
        let document = controller.document
        let automatic = document.selectionMode == .automatic
        var items: [NSMenuItem] = [
            // "(off)" makes it visible that a hand-picked or new profile stopped automatic switching.
            MenuActionItem(automatic ? "Automatic" : "Automatic (off)", state: automatic ? .on : .off) { [weak controller] in
                controller?.chooseProfile(nil)
            },
            .separator(),
        ]
        for profile in document.profiles {
            let isActive = profile.id == document.activeProfileID
            let state: NSControl.StateValue = isActive ? (automatic ? .mixed : .on) : .off
            items.append(MenuActionItem(profile.name, state: state) { [weak controller] in
                controller?.chooseProfile(profile.id)
            })
        }
        items.append(.separator())
        items.append(.submenu("New Profile from Template", items: LayoutTemplates.profileTemplates.map { template in
            MenuActionItem(template.title) { [weak controller] in controller?.newProfile(from: template) }
        }))
        if let active = document.activeProfile {
            items.append(MenuActionItem("Rename “\(active.name)”…") { [weak controller] in
                guard let controller else { return }
                if let name = TextPrompt.run(title: "Rename Profile", message: "New name for “\(active.name)”:", initial: active.name) {
                    controller.renameProfile(active.id, to: name)
                }
            })
            items.append(MenuActionItem("Delete “\(active.name)”…", isEnabled: document.profiles.count > 1) { [weak controller] in
                guard let controller else { return }
                let confirmed = TextPrompt.confirm(
                    title: "Delete the profile “\(active.name)”?",
                    message: "Its meter groups on every display are removed. You can undo this from the menu (Undo Delete Profile).",
                    confirmTitle: "Delete"
                )
                if confirmed { controller.deleteProfile(active.id) }
            })
        }
        items.append(.separator())
        items.append(.info("Automatic picks the profile for the connected displays and surfaces (SSL / WING MIDI ports)."))
        return items
    }

    private func addGroupItems(for controller: AppController) -> [NSMenuItem] {
        var items: [NSMenuItem] = LayoutTemplates.all.map { template in
            MenuActionItem(template.title) { [weak controller] in
                guard let controller else { return }
                let added: [UUID]
                if controller.activeProfile == nil {
                    added = controller.newProfile(from: template).flatMap { controller.document.profile(withID: $0)?.allGroups.map(\.id) } ?? []
                } else {
                    added = controller.addGroups(from: template)
                }
                if let first = added.first {
                    if !controller.isEditing { controller.setEditing(true) }
                    (controller.layoutEditor as? LayoutEditorController)?.select(first, focus: true)
                }
            }
        }
        items.append(.separator())
        items.append(.info("Adds to “\(controller.activeProfile?.name ?? "a new profile")” and opens Edit Layout."))
        return items
    }

    private func displayItems(for controller: AppController) -> [NSMenuItem] {
        let current = controller.currentBridgeDisplay?.displayID
        var items: [NSMenuItem] = controller.connectedDisplays.map { display in
            let item = MenuActionItem(display.menuTitle, state: display.displayID == current ? .on : .off) { [weak controller] in
                controller?.moveBridge(to: display)
            }
            if display.pointsPerMillimeter == nil {
                item.toolTip = "This display doesn’t report a usable physical size, so the meters will be scaled to it."
            }
            return item
        }
        items.append(.separator())
        items.append(.info("Moves every meter group, keeping physical size when known."))
        return items
    }
}
