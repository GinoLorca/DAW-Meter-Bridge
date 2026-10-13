import AppKit
import SwiftUI

/// The settings window (SwiftUI in an `NSWindow`). Opening it activates the app; the bridge panels keep
/// working behind it. Closing it gives the keyboard back to the app that was in front (the DAW).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: NSWindow?

    init(controller: AppController) {
        model = SettingsModel(controller: controller)
        super.init()
    }

    /// Shows the window and brings the app forward.
    func show() {
        model.refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        FocusHandoff.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        FocusHandoff.giveBackIfIdle(closing: closing)
    }

    /// Re-reads settings and the connection state (called when the app's status changes).
    func refresh() {
        guard window?.isVisible == true else { return }
        model.refresh()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DAW Meter Bridge Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        return window
    }
}
