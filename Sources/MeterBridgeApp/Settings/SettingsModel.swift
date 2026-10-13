import AppKit
import MeterCore
import MeterSources
import Observation
import SwiftUI

/// What the settings window shows about the Ableton Live connection.
struct LiveConnectionInfo: Equatable {
    var activeSource: String
    var statusLine: String
    var listenPort: UInt16
    var scriptPort: UInt16
    var boundPort: UInt16?
    var liveVersion: String?
    var scriptVersion: String?
    var meterRate: Int?
    var warnings: [String]
}

/// The settings window's state. Every change is applied at once through `AppController.applySettings`
/// (meters update on the next frame) and saved shortly after.
@MainActor
@Observable
final class SettingsModel {
    private(set) var settings: AppSettings
    private(set) var connection: LiveConnectionInfo
    private(set) var layoutsPath: String
    private(set) var settingsLocation: String

    @ObservationIgnored private weak var controller: AppController?

    init(controller: AppController) {
        self.controller = controller
        settings = controller.settings
        connection = Self.connectionInfo(of: controller)
        layoutsPath = controller.layoutStore.url.path
        settingsLocation = controller.paths.settingsFileURL?.path ?? "the app’s preferences (UserDefaults, key \(SettingsStore.defaultsKey))"
    }

    /// Re-reads the settings and connection state from the controller.
    func refresh() {
        guard let controller else { return }
        if settings != controller.settings { settings = controller.settings }
        let info = Self.connectionInfo(of: controller)
        if info != connection { connection = info }
    }

    /// Changes the settings and applies them.
    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        controller?.applySettings(next)
    }

    /// A binding to one setting.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.update { $0[keyPath: keyPath] = value } }
        )
    }

    /// A binding to a `Float` setting as a `Double`, for sliders.
    func doubleBinding(_ keyPath: WritableKeyPath<AppSettings, Float> & Sendable) -> Binding<Double> {
        Binding(
            get: { Double(self.settings[keyPath: keyPath]) },
            set: { value in self.update { $0[keyPath: keyPath] = Float(value) } }
        )
    }

    /// Puts the meter look, ballistics and dimming back to their defaults (source and layout untouched).
    func restoreDefaultMeterSettings() {
        update { settings in
            settings.style = .standard
            settings.ballistics = .standard
            settings.mixFocus = .standard
        }
    }

    /// Asks, then replaces every layout profile with the first-run layouts (undoable from the menu).
    func confirmResetLayout() {
        guard let controller else { return }
        let confirmed = TextPrompt.confirm(
            title: "Reset the layout?",
            message: "Every profile is replaced with the first-run layouts (“Bronx — UF8” and “Brooklyn — WING”) along the bottom of the main display. You can undo this from the menu bar (Undo Reset Layout).",
            confirmTitle: "Reset Layout"
        )
        if confirmed { controller.resetLayouts() }
    }

    private static func connectionInfo(of controller: AppController) -> LiveConnectionInfo {
        let live = controller.live
        let configuration = live?.configuration ?? .standard
        var warnings = controller.sourceKind == .live ? controller.snapshot.warnings : []
        if let error = live?.lastScriptError { warnings.append("Live script: \(error)") }
        return LiveConnectionInfo(
            activeSource: controller.sourceKind.title,
            statusLine: controller.sourceKind == .live ? controller.sourceStatusLine : "Not in use (the source is \(controller.sourceKind.title)).",
            listenPort: configuration.listenPort,
            scriptPort: configuration.scriptPort,
            boundPort: live?.boundPort,
            liveVersion: live?.liveVersion,
            scriptVersion: live?.scriptVersion,
            meterRate: live?.scriptMeterRate,
            warnings: warnings
        )
    }
}
