import AppKit

/// Small modal dialogs for edit mode and the menus. A menu-bar app has to activate itself to show them,
/// which takes keyboard focus from the DAW until the dialog closes (`FocusHandoff` gives it back).
@MainActor
enum TextPrompt {
    /// Asks for a line of text. Returns nil when cancelled.
    static func run(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return FocusHandoff.runModal { alert.runModal() } == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Asks to confirm a destructive action. Returns true for `confirmTitle`.
    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let confirm = alert.addButton(withTitle: confirmTitle)
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return FocusHandoff.runModal { alert.runModal() } == .alertFirstButtonReturn
    }
}
