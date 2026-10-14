import BridgeControl
import BridgeLayout
import Foundation

// The Main meter switch and the commands of the control protocol and the URL scheme (docs/CONTROL.md).
extension AppController {
    // MARK: - Main meter

    /// Whether the active profile has a visible Main meter group (whether or not the bridge is shown).
    var isMainMeterVisible: Bool {
        document.activeProfile?.isMainMeterVisible ?? false
    }

    /// Shows or hides the active profile's Main meter: every group bound to the main track. Showing it
    /// when there is none adds one at the right edge of the display holding the profile's first visible
    /// group, lined up with that group (`LayoutProfile.addMainMeter`). Hiding keeps its place. One undo
    /// step, saved shortly after; independent of Show/Hide Bridge.
    func setMainMeterVisible(_ visible: Bool) {
        finishLayoutGesture()
        guard var profile = document.activeProfile, profile.isMainMeterVisible != visible else { return }
        let display = displayManager.mainDisplay ?? Self.standInDisplay
        let fallback = DefaultLayouts.mainMeterFallback(on: display, bottomInset: isHeadless ? 0 : display.bottomDockInset)
        guard profile.setMainMeterVisible(visible, fallback: fallback) else { return }
        performLayoutChange(visible ? "Show Main Meter" : "Hide Main Meter") { $0.upsert(profile) }
    }

    func toggleMainMeter() {
        setMainMeterVisible(!isMainMeterVisible)
    }

    /// Ends an edit-mode drag that is still in progress as its own undo step, so a change from outside
    /// (a Stream Deck key or a URL arriving mid-drag) neither cancels it nor folds it into its own step.
    private func finishLayoutGesture() {
        if gestureStartDocument != nil { layoutEditor?.finishGesture() }
    }

    // MARK: - Control commands

    /// The state `ctl.state` reports.
    var controlState: ControlState {
        ControlState(
            bridge: isBridgeVisible,
            main: isMainMeterVisible,
            edit: isEditing,
            source: sourceKind.rawValue,
            connected: sourceKind == .simulator || snapshot.connection.isConnected,
            app: AppInfo.version
        )
    }

    /// Applies a command from the control protocol or a `dawmeterbridge://` URL. Finishes synchronously,
    /// so `controlState` reflects it on return. A drag in edit mode is finished first (its own undo step).
    func perform(_ command: ControlCommand) {
        finishLayoutGesture()
        let value = command.newValue(in: controlState)
        switch command.target {
        case .bridge:
            if value != isBridgeVisible { setBridgeVisible(value) }
        case .main:
            setMainMeterVisible(value)
        case .edit:
            setEditing(value)
        }
    }
}

/// The app's version: the bundle's when it runs from the .app, else the version scripts/build-app.sh stamps.
enum AppInfo {
    /// Keep in step with `version` in scripts/build-app.sh.
    static let fallbackVersion = "0.2.0"

    static let version: String = {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return bundled.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackVersion
    }()
}
