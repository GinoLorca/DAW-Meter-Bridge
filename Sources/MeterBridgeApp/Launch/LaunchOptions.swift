import BridgeControl
import Foundation

/// Where meters come from.
enum SourceKind: String, Codable, CaseIterable, Sendable {
    case simulator
    case live

    /// Menu title.
    var title: String {
        switch self {
        case .simulator: return "Simulator"
        case .live: return "Ableton Live"
        }
    }
}

/// Command-line options of the app.
///
/// ```
/// MeterBridge [--source simulator|live] [--snapshot <dir>] [--reset-layout] [--data-dir <dir>] [--control-port <n>]
/// ```
struct LaunchOptions: Equatable, Sendable {
    /// Source to start with; nil = the last one used, else the simulator.
    var source: SourceKind?
    /// Render every strip group to PNG in this folder, write a JSON summary and quit.
    var snapshotDirectory: URL?
    /// How long `--snapshot` lets data arrive before rendering.
    var snapshotWait: TimeInterval = 2
    /// Replace layouts.json with the first-run layouts (the old file is kept as a backup).
    var resetLayout = false
    /// Keep layouts.json and settings in this folder instead of Application Support and UserDefaults.
    var dataDirectory: URL?
    /// UDP port of the control protocol on 127.0.0.1 (docs/CONTROL.md; the Stream Deck plugin uses 47802).
    var controlPort: UInt16 = ControlProtocol.defaultPort
    /// Print usage and quit.
    var showHelp = false
    /// Hidden `--demo-edit <dir>`: enter edit mode, drive scripted moves, resizes, keys and a calibration
    /// through the editor, check the results, write a report and PNGs to this folder and quit.
    /// Uses `<dir>/data` as the data directory unless `--data-dir` is given, so real layouts are untouched.
    var demoEditDirectory: URL?

    static let usage = """
    Usage: MeterBridge [options]

      --source simulator|live   Meter source to start with (default: the last one used, else simulator)
      --snapshot <dir>          Wait for data, render every strip group to PNG in <dir>, write
                                summary.json and quit. Never saves settings or layouts.
      --snapshot-wait <seconds> How long --snapshot waits for data (default 2)
      --reset-layout            Replace the saved layouts with the first-run layouts
                                (the old file is kept as layouts.json.before-reset.bak,
                                or .before-reset.1.bak, .2.bak, ... when that exists)
      --data-dir <dir>          Keep layouts.json and settings.json in <dir> instead of
                                ~/Library/Application Support and the app's defaults
      --control-port <n>        Listen for the Stream Deck control protocol on 127.0.0.1:<n>
                                (default 47802; for test runs beside the installed app)
      --help                    Show this help
    """

    /// Parses `CommandLine.arguments` (the first element is the executable and is skipped).
    ///
    /// Single-dash arguments that AppKit or Xcode add (`-NSDocumentRevisionsDebugMode YES`,
    /// `-psn_0_12345`) are ignored.
    static func parse(_ arguments: [String]) throws(LaunchOptionsError) -> LaunchOptions {
        var options = try parseArguments(arguments)
        if let demo = options.demoEditDirectory, options.dataDirectory == nil {
            options.dataDirectory = demo.appendingPathComponent("data", isDirectory: true)
        }
        return options
    }

    private static func parseArguments(_ arguments: [String]) throws(LaunchOptionsError) -> LaunchOptions {
        var options = LaunchOptions()
        var queue = Array(arguments.dropFirst())[...]

        func value(for name: String, inline: String?) throws(LaunchOptionsError) -> String {
            if let inline { return inline }
            guard let next = queue.popFirst(), !next.hasPrefix("--") else {
                throw .missingValue(name)
            }
            return next
        }

        while let argument = queue.popFirst() {
            if argument.hasPrefix("-psn_") { continue }
            if argument.hasPrefix("-"), !argument.hasPrefix("--") {
                // NSArgumentDomain pair such as -NSDocumentRevisionsDebugMode YES.
                if let next = queue.first, !next.hasPrefix("-") { queue.removeFirst() }
                continue
            }
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let name = parts[0]
            let inline = parts.count > 1 ? parts[1] : nil
            switch name {
            case "--source":
                let text = try value(for: name, inline: inline)
                guard let kind = SourceKind(rawValue: text.lowercased()) else {
                    throw .invalidValue(name, text)
                }
                options.source = kind
            case "--snapshot":
                options.snapshotDirectory = URL(fileURLWithPath: try value(for: name, inline: inline), isDirectory: true).standardizedFileURL
            case "--snapshot-wait":
                let text = try value(for: name, inline: inline)
                guard let seconds = TimeInterval(text), seconds >= 0, seconds <= 120 else {
                    throw .invalidValue(name, text)
                }
                options.snapshotWait = seconds
            case "--reset-layout":
                options.resetLayout = true
            case "--demo-edit":
                options.demoEditDirectory = URL(fileURLWithPath: try value(for: name, inline: inline), isDirectory: true).standardizedFileURL
            case "--control-port":
                let text = try value(for: name, inline: inline)
                guard let port = UInt16(text), port > 0 else {
                    throw .invalidValue(name, text)
                }
                options.controlPort = port
            case "--data-dir":
                options.dataDirectory = URL(fileURLWithPath: try value(for: name, inline: inline), isDirectory: true).standardizedFileURL
            case "--help", "-h":
                options.showHelp = true
            default:
                throw .unknownOption(argument)
            }
        }
        return options
    }
}

/// Why the command line could not be parsed.
enum LaunchOptionsError: Error, Equatable, CustomStringConvertible {
    case unknownOption(String)
    case missingValue(String)
    case invalidValue(String, String)

    var description: String {
        switch self {
        case let .unknownOption(option): return "unknown option \(option)"
        case let .missingValue(option): return "\(option) needs a value"
        case let .invalidValue(option, value): return "invalid value '\(value)' for \(option)"
        }
    }
}
