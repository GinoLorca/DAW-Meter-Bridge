import AppKit
import Carbon.HIToolbox

/// Starts the controller and the menu-bar UI, or runs `--snapshot` and quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: LaunchOptions
    private(set) var controller: AppController?
    private var statusMenu: StatusMenuController?
    private var hotKeys: [GlobalHotKey] = []
    private var exporter: SnapshotExporter?
    private var settingsWindow: SettingsWindowController?
    private var demo: EditDemo?
    /// One running copy per data folder (see `InstanceLock`); nil for `--snapshot` runs.
    private var instanceLock: InstanceLock?
    private var secondLaunchObserver: NSObjectProtocol?
    /// The control protocol for the Stream Deck plugin (docs/CONTROL.md); menu-bar runs only.
    private var controlService: ControlService?
    /// `dawmeterbridge://` URLs; menu-bar runs only.
    private var urlHandler: URLCommandHandler?

    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    /// Registers for `dawmeterbridge://` URLs before launching finishes, so a URL that launches the app
    /// is applied too (once the controller has started). Headless runs ignore URLs.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard options.snapshotDirectory == nil, options.demoEditDirectory == nil else { return }
        let handler = URLCommandHandler()
        handler.install()
        urlHandler = handler
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything loads or writes layouts.json: a second copy on the same data folder quits.
        if options.snapshotDirectory == nil, !takeInstanceLock() {
            exit(0)
        }
        let controller = AppController(options: options)
        self.controller = controller
        let editor = LayoutEditorController()
        controller.layoutEditor = editor
        controller.onLayoutRestored = { [weak editor] in editor?.refresh() }

        if let directory = options.snapshotDirectory {
            let exporter = SnapshotExporter(controller: controller, directory: directory, wait: options.snapshotWait)
            self.exporter = exporter
            exporter.run { code in
                exit(code)
            }
            return
        }

        if let directory = options.demoEditDirectory {
            let demo = EditDemo(controller: controller, editor: editor, directory: directory)
            self.demo = demo
            controller.onNotice = { title, message in print("Notice: \(title): \(message)") }
            controller.start()
            demo.run { code in
                exit(code)
            }
            return
        }

        let statusMenu = StatusMenuController(controller: controller)
        self.statusMenu = statusMenu
        let settingsWindow = SettingsWindowController(controller: controller)
        self.settingsWindow = settingsWindow
        statusMenu.openSettings = { [weak settingsWindow] in settingsWindow?.show() }
        let controlService = ControlService(controller: controller, port: options.controlPort)
        self.controlService = controlService
        controller.onStatusChange = { [weak statusMenu, weak settingsWindow, weak controlService] in
            statusMenu?.updateIcon()
            settingsWindow?.refresh()
            controlService?.stateMayHaveChanged()
        }
        controller.onNotice = { title, message in NoticePresenter.show(title: title, message: message) }
        NSApp.mainMenu = Self.makeMainMenu()
        controller.start()
        statusMenu.updateIcon()
        registerHotKeys(for: controller)
        secondLaunchObserver = instanceLock?.observeSecondLaunches { [weak self] in self?.showForSecondLaunch() }
        controlService.start()
        urlHandler?.perform = { [weak controller] command in controller?.perform(command) }
    }

    /// Takes the data folder's instance lock. Returns false when another copy of the app holds it; that
    /// copy is asked to show itself.
    private func takeInstanceLock() -> Bool {
        let folder = AppPaths(dataDirectory: options.dataDirectory).layoutsURL.deletingLastPathComponent()
        switch InstanceLock.acquire(in: folder) {
        case let .acquired(lock):
            instanceLock = lock
            return true
        case let .heldElsewhere(url):
            FileHandle.standardError.write(Data(
                "DAW Meter Bridge is already running with the layouts in \(folder.path); showing it instead. Use --data-dir <dir> to run another copy with separate layouts.\n".utf8
            ))
            InstanceLock.notifyRunningInstance(lockURL: url)
            return false
        case let .unavailable(url, code):
            appLog.error("Could not lock \(url.path, privacy: .public) (errno \(code)); not guarding against a second copy")
            return true
        }
    }

    /// Another launch on the same data folder asked us to show ourselves: show the bridge and open the menu.
    private func showForSecondLaunch() {
        guard let controller else { return }
        if !controller.isBridgeVisible { controller.setBridgeVisible(true) }
        statusMenu?.reveal()
    }

    /// The app never shows a menu bar (accessory app), but AppKit routes standard key equivalents through
    /// the main menu: without it ⌘V/⌘C/⌘A/⌘Z do nothing in text prompts and ⌘W/⌘Q nothing in Settings.
    /// Edit-mode keys are handled before this (GroupHostView.performKeyEquivalent).
    static func makeMainMenu() -> NSMenu {
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            return holder
        }
        let main = NSMenu(title: "Main")
        main.addItem(submenu("DAW Meter Bridge", [
            item("Quit DAW Meter Bridge", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        return main
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let secondLaunchObserver { DistributedNotificationCenter.default().removeObserver(secondLaunchObserver) }
        controlService?.stop()
        urlHandler?.uninstall()
        hotKeys.forEach { $0.unregister() }
        hotKeys = []
        controller?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌃⌥⌘M shows/hides the bridge, ⌃⌥⌘E toggles edit mode. A hotkey that can't be registered is
    /// reported in the menu, whose items still work. macOS doesn't tell us when another app or a system
    /// shortcut uses the same combination non-exclusively, so such a conflict goes unreported.
    private func registerHotKeys(for controller: AppController) {
        let modifiers = StatusMenuController.hotKeyModifiers
        let bindings: [(Int, String, @MainActor () -> Void)] = [
            (kVK_ANSI_M, "⌃⌥⌘M (Show/Hide Bridge)", { [weak controller] in controller?.toggleBridgeVisible() }),
            (kVK_ANSI_E, "⌃⌥⌘E (Edit Layout)", { [weak controller] in controller?.toggleEditing() }),
        ]
        for (keyCode, name, action) in bindings {
            if let hotKey = GlobalHotKey(keyCode: keyCode, modifiers: modifiers, action: action) {
                hotKeys.append(hotKey)
            } else {
                controller.appMessages.append("The hotkey \(name) couldn’t be registered (another app may hold it); use the menu instead.")
            }
        }
    }
}
