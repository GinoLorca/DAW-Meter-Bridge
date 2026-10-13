import AppKit

/// Lends keyboard focus to our dialogs and windows and gives it back to the DAW afterwards.
///
/// A menu-bar app has to activate itself to show an alert or the Settings window. Once that closes, the
/// app would otherwise stay active with no window, so Space and other keys go nowhere instead of to Live
/// (clicks on the bridge never activate Live). `NSApp.deactivate()` does not hand activation back on
/// current macOS, so the app that was in front is remembered and activated again.
@MainActor
enum FocusHandoff {
    /// The app that was in front before we activated (never this app).
    private static var previousApp: NSRunningApplication?
    /// True while something of ours needs the keyboard after a dialog closes (edit mode).
    static var isHoldingFocus = false

    /// Activates this app for a dialog or window, remembering the app that had focus.
    static func activate() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        NSApp.activate()
    }

    /// Runs a modal dialog with the app active, then gives focus back (see `giveBackIfIdle`).
    static func runModal<T>(_ dialog: () -> T) -> T {
        activate()
        let result = dialog()
        giveBackIfIdle()
        return result
    }

    /// Gives activation back to the remembered app, unless edit mode holds the focus or another titled
    /// window of ours (other than `closing`) is still open.
    static func giveBackIfIdle(closing: NSWindow? = nil) {
        guard NSApp.isActive, !isHoldingFocus else { return }
        let openWindow = NSApp.windows.contains { window in
            window !== closing && window.isVisible && window.styleMask.contains(.titled)
        }
        guard !openWindow else { return }
        giveBack()
    }

    /// Activates the remembered app (or, failing that, deactivates this one).
    static func giveBack() {
        defer { previousApp = nil }
        guard let previous = previousApp, !previous.isTerminated else {
            NSApp.deactivate()
            return
        }
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }

    /// Someone else (e.g. Finder revealing a folder) takes over; don't hand focus back later.
    static func forget() {
        previousApp = nil
    }
}
