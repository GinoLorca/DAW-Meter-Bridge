import AppKit

/// "Install Live Script…": short instructions, then the script folder in Finder.
@MainActor
enum LiveScriptHelp {
    static func present() {
        let folder = AppPaths.remoteScriptFolder()
        let alert = NSAlert()
        alert.messageText = "Install the MeterBridge script in Ableton Live"
        var steps = """
        1. Copy the MeterBridge folder into ~/Music/Ableton/User Library/Remote Scripts/ \
        (or run scripts/install-live-script.sh from the project).
        2. Restart Live. In Settings › Link, Tempo & MIDI, pick MeterBridge in a free Control Surface slot, with Input and Output set to None.
        3. Remove leftover Mackie Control XT slots you don’t use, so the UF8 banks by 8.
        4. In this app choose Source › Ableton Live.
        """
        if folder == nil {
            steps += "\n\nThe MeterBridge folder wasn’t found next to the app. It is in the project’s AbletonRemoteScript folder."
        }
        alert.informativeText = steps
        alert.addButton(withTitle: folder == nil ? "OK" : "Show in Finder")
        guard let folder else {
            FocusHandoff.runModal { _ = alert.runModal() }
            return
        }
        FocusHandoff.activate()
        alert.runModal()
        // Finder comes forward with the folder; focus goes back to the DAW from there as usual.
        FocusHandoff.forget()
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

/// Shows an informational alert from a menu-bar app (which has to activate itself first, then gives the
/// focus back to the DAW).
@MainActor
enum NoticePresenter {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        FocusHandoff.runModal { _ = alert.runModal() }
    }
}
