import AppKit
import BridgeLayout
import MeterCore
import MeterRendering
import MeterSources

/// Owns the app's state and wires the modules together: the meter source, the meter store, the layout
/// document, the displays and the panels.
///
/// Extensions: `+Source` (switching sources, source callbacks), `+Layout` (loading, profiles, placing
/// panels, moving to another display), `+Interaction` (bank gestures to DAW commands), `+Editing`
/// (edit mode and the `LayoutEditHost` the edit-mode UI uses).
@MainActor
final class AppController {
    let options: LaunchOptions
    /// Snapshot mode: no panels, menu or hotkeys, and nothing is saved.
    let isHeadless: Bool
    let paths: AppPaths

    // Settings
    let settingsStore: SettingsStore
    var settings: AppSettings

    // Meters and DAW state
    let store: MeterStore
    let frameClock = FrameClock()
    var sourceKind: SourceKind
    /// The running source (nil before `start()`).
    var source: (any MeterSource)?
    var simulator: SimulatedSource?
    var live: LiveSource?
    /// Latest DAW state from the source.
    var snapshot = BridgeSnapshot.empty
    /// Bumped on every snapshot change, so panels re-resolve their tracks only when needed.
    var revision = 0
    /// Last `watch` set sent to the source.
    var lastWatched: Set<TrackID>?

    // Layout
    let layoutStore: LayoutStore
    var document = LayoutDocument.empty
    /// False when layouts.json exists but could not be read: never overwrite it then.
    var canSaveLayouts: Bool
    /// Problems found while loading or saving layouts, shown in the menu.
    var layoutMessages: [String] = []
    /// Other problems to show in the menu, e.g. a hotkey that could not be registered.
    var appMessages: [String] = []
    /// Where the active profile's groups are shown now.
    var presentation = LayoutPresentation()
    /// Undo and redo of every layout change.
    let layoutHistory = LayoutHistory()
    /// The document as it was when the current edit gesture began (a drag, a nudge); see `beginLayoutGesture()`.
    var gestureStartDocument: LayoutDocument?
    /// Debounced writes of layouts.json and the settings.
    var pendingLayoutSave: Task<Void, Never>?
    var pendingSettingsSave: Task<Void, Never>?
    /// Notices MIDI surfaces coming and going (CoreMIDI setup changes), to re-pick the profile.
    var surfaceWatcher: SurfaceWatcher?
    /// Surface families seen on MIDI ports at the last check.
    var surfaces: Set<SurfaceHint> = []
    let displayManager: DisplayManager

    // Panels and modes
    lazy var panelManager = PanelManager(
        renderer: self,
        bankDelegate: self,
        style: settings.style,
        calibration: store.calibration
    )
    /// Keeps display links running until this time (after gestures, so drag overlays settle).
    var keepAwakeUntil: TimeInterval = 0
    var isEditing = false
    /// The edit-mode UI; nil shows only the banks' guides in edit mode.
    var layoutEditor: (any LayoutEditor)?
    /// Called when anything the menu-bar icon or menu shows may have changed.
    var onStatusChange: (() -> Void)?
    /// Called with a message to show the user (e.g. after moving the bridge to another display).
    var onNotice: ((_ title: String, _ message: String) -> Void)?
    /// Called after undo or redo put back an earlier layout document.
    var onLayoutRestored: (() -> Void)?

    init(options: LaunchOptions) {
        self.options = options
        isHeadless = options.snapshotDirectory != nil
        paths = AppPaths(dataDirectory: options.dataDirectory)
        settingsStore = SettingsStore(paths: paths)
        settingsStore.isWritable = !isHeadless
        settings = settingsStore.load()
        store = MeterStore(settings: settings.ballistics)
        sourceKind = options.source ?? settings.source ?? .simulator
        layoutStore = LayoutStore(url: paths.layoutsURL)
        canSaveLayouts = !isHeadless
        displayManager = DisplayManager()
        loadLayouts()
    }

    /// Picks the profile, places the panels and starts the source. Panels are shown unless the bridge
    /// was hidden when the app last ran.
    func start() {
        if !isHeadless {
            displayManager.onChange = { [weak self] _ in self?.displaysChanged() }
            displayManager.start()
            let watcher = SurfaceWatcher { [weak self] in self?.surfacesMayHaveChanged() }
            watcher.start()
            surfaceWatcher = watcher
        }
        surfaces = SurfaceDetector.connectedSurfaces()
        selectProfileAndPresent()
        activateSource(sourceKind)
        if !isHeadless {
            panelManager.setVisible(settings.isBridgeVisible)
        }
    }

    /// Stops the source and display tracking before quitting.
    func shutdown() {
        if isEditing { setEditing(false) }
        source?.delegate = nil
        source?.stop()
        displayManager.stop()
        surfaceWatcher?.stop()
        surfaceWatcher = nil
        panelManager.closeAll()
        flushPendingSaves()
    }

    // MARK: - Visibility

    var isBridgeVisible: Bool { settings.isBridgeVisible }

    /// Shows or hides every panel; the choice is remembered across launches.
    func setBridgeVisible(_ visible: Bool) {
        if !visible, isEditing { setEditing(false) }
        settings.isBridgeVisible = visible
        saveSettings()
        if !isHeadless { panelManager.setVisible(visible) }
        onStatusChange?()
    }

    func toggleBridgeVisible() {
        setBridgeVisible(!settings.isBridgeVisible)
    }

    /// Clears peak hold, clip LEDs and readouts on every meter.
    func resetAllPeaks() {
        store.resetAllPeaks()
        keepAwake(for: 0.1)
    }

    // MARK: - Frames

    /// Keeps display links running for at least `seconds` and wakes idle ones.
    func keepAwake(for seconds: TimeInterval) {
        keepAwakeUntil = max(keepAwakeUntil, ProcessInfo.processInfo.systemUptime + seconds)
        panelManager.wakeAll()
    }

    func saveSettings() {
        pendingSettingsSave?.cancel()
        pendingSettingsSave = nil
        settingsStore.save(settings)
    }

    /// Saves the settings shortly, coalescing quick changes (a slider being dragged).
    func scheduleSettingsSave(after delay: Duration = .milliseconds(400)) {
        pendingSettingsSave?.cancel()
        pendingSettingsSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveSettings()
        }
    }

    /// Writes any debounced layout or settings save now (before quitting).
    func flushPendingSaves() {
        if pendingLayoutSave != nil { saveLayouts() }
        if pendingSettingsSave != nil { saveSettings() }
    }

    /// Replaces the settings and applies them at once: meter style, ballistics and mix focus show on the
    /// next frame. Saved shortly after (debounced).
    func applySettings(_ newSettings: AppSettings) {
        let old = settings
        guard newSettings != old else { return }
        settings = newSettings
        if old.style != newSettings.style, !isHeadless { panelManager.setStyle(newSettings.style) }
        if old.ballistics != newSettings.ballistics { store.settings = newSettings.ballistics }
        if old.simulatorUnitCount != newSettings.simulatorUnitCount { simulator?.setUnitCount(newSettings.simulatorUnitCount) }
        if old.liveMeterCalibration != newSettings.liveMeterCalibration { applyMeterCalibration() }
        keepAwake(for: 0.3)
        scheduleSettingsSave()
        onStatusChange?()
    }
}

extension AppController: GroupPanelRenderer {
    func renderFrame(for panel: GroupPanelController, at time: TimeInterval) -> Bool {
        let active = frameClock.advance(store, to: time)
        panel.render(snapshot: snapshot, revision: revision, store: store, mixFocus: settings.mixFocus)
        return active || time < keepAwakeUntil
    }
}
