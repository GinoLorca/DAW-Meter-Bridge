import BridgeLayout
import Foundation

/// Where the app keeps its files.
struct AppPaths: Sendable {
    /// `--data-dir`, when given: layouts and settings live there instead of the standard places.
    var dataDirectory: URL?

    /// layouts.json.
    var layoutsURL: URL {
        dataDirectory.map { $0.appendingPathComponent("layouts.json", isDirectory: false) } ?? LayoutStore.defaultURL
    }

    /// settings.json when a data directory is set; nil means UserDefaults.
    var settingsFileURL: URL? {
        dataDirectory.map { $0.appendingPathComponent("settings.json", isDirectory: false) }
    }

    /// The `AbletonRemoteScript/MeterBridge` folder: inside the app bundle's Resources (copied there by
    /// scripts/build-app.sh), next to the executable in a checkout, or in the source tree this was built from.
    static func remoteScriptFolder() -> URL? {
        let relative = "AbletonRemoteScript/MeterBridge"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(relative, isDirectory: true))
        }
        if var directory = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            for _ in 0..<8 {
                candidates.append(directory.appendingPathComponent(relative, isDirectory: true))
                directory.deleteLastPathComponent()
            }
        }
        // Sources/MeterBridgeApp/Launch/AppPaths.swift -> repository root.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(sourceRoot.appendingPathComponent(relative, isDirectory: true))

        return candidates.first { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("__init__.py").path)
        }
    }
}
