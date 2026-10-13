import Foundation
import os

let appLog = Logger(subsystem: "DAWMeterBridge", category: "App")

/// Loads and saves `AppSettings` as JSON, in UserDefaults or (with `--data-dir`) in a file.
@MainActor
final class SettingsStore {
    enum Backend {
        case userDefaults(UserDefaults, key: String)
        case file(URL)
    }

    static let defaultsKey = "settings.v1"

    let backend: Backend
    /// When false, `save` does nothing (snapshot mode never changes the user's settings).
    var isWritable = true

    init(backend: Backend) {
        self.backend = backend
    }

    /// UserDefaults by default; a settings.json file when `paths` has a data directory.
    convenience init(paths: AppPaths) {
        if let url = paths.settingsFileURL {
            self.init(backend: .file(url))
        } else {
            self.init(backend: .userDefaults(.standard, key: Self.defaultsKey))
        }
    }

    /// The saved settings, or the defaults when nothing (readable) is saved.
    func load() -> AppSettings {
        let data: Data?
        switch backend {
        case let .userDefaults(defaults, key):
            data = defaults.data(forKey: key)
        case let .file(url):
            data = try? Data(contentsOf: url)
        }
        guard let data else { return .standard }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            appLog.error("Ignoring unreadable settings: \(String(describing: error), privacy: .public)")
            return .standard
        }
    }

    func save(_ settings: AppSettings) {
        guard isWritable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            switch backend {
            case let .userDefaults(defaults, key):
                defaults.set(data, forKey: key)
            case let .file(url):
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        } catch {
            appLog.error("Could not save settings: \(String(describing: error), privacy: .public)")
        }
    }
}
