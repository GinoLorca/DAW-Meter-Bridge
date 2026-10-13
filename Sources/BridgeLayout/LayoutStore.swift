import Foundation

/// What `LayoutStore.load()` found.
public struct LayoutLoadResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The file was read and decoded.
        case loaded
        /// No file yet (first launch); the document is empty.
        case missing
        /// The file could not be decoded. It was moved to `backupURL` and the document is empty.
        /// Tell the user; the next save writes a fresh file.
        case recovered(backupURL: URL, reason: String)
        /// The file was written by a newer version of the app (a newer format, or a value this version
        /// doesn't know). It was left untouched and the document is empty: use defaults in memory and
        /// don't save over the file, so the newer version still finds the user's layouts.
        case newerFormat(reason: String)
    }

    public var document: LayoutDocument
    public var status: Status

    public init(document: LayoutDocument, status: Status) {
        self.document = document
        self.status = status
    }
}

/// Reads and writes the layout document as JSON at one URL.
///
/// Saves are atomic (write to a temporary file, then rename), so a crash never leaves half a file.
/// An unreadable file is never overwritten silently: `load()` moves it aside to a `.bak` first.
/// Calls are synchronous and the file is small; use it from one actor (the app's main actor).
public struct LayoutStore: Sendable {
    public let url: URL

    public init(url: URL = LayoutStore.defaultURL) {
        self.url = url
    }

    /// `~/Library/Application Support/DAW Meter Bridge/layouts.json`
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("DAW Meter Bridge", isDirectory: true)
            .appendingPathComponent("layouts.json", isDirectory: false)
    }

    /// Loads the document. A missing file gives an empty document; an undecodable one (corrupt JSON) is
    /// moved to a backup and gives an empty document. A file from a newer app version is left where it
    /// is (`.newerFormat`).
    ///
    /// Throws only when the file exists but cannot be read, or cannot be moved aside. The app must not
    /// save over the file in that case.
    public func load() throws -> LayoutLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return LayoutLoadResult(document: .empty, status: .missing)
        }
        do {
            let document = try Self.decoder.decode(LayoutDocument.self, from: data)
            return LayoutLoadResult(document: document, status: .loaded)
        } catch let error as LayoutDocumentError {
            return LayoutLoadResult(document: .empty, status: .newerFormat(reason: Self.describe(error)))
        } catch {
            let backup = try moveAside()
            return LayoutLoadResult(document: .empty, status: .recovered(backupURL: backup, reason: Self.describe(error)))
        }
    }

    /// Writes the document atomically, creating the folder if needed.
    public func save(_ document: LayoutDocument) throws {
        let data = try Self.encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Moves the current file to the first free name of `layouts.json.bak`, `layouts.json.1.bak`, ...
    private func moveAside() throws -> URL {
        let candidate = backupURL()
        try FileManager.default.moveItem(at: url, to: candidate)
        return candidate
    }

    /// Copies the current file to the first free name of `layouts.json.<suffix>.bak`,
    /// `layouts.json.<suffix>.1.bak`, ... (an existing backup is never replaced). Returns nil when there
    /// is no file to copy.
    public func copyToBackup(suffix: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let candidate = backupURL(suffix: suffix)
        try FileManager.default.copyItem(at: url, to: candidate)
        return candidate
    }

    /// The first backup name that doesn't exist yet: `layouts.json[.<suffix>].bak`, then
    /// `layouts.json[.<suffix>].1.bak`, `.2.bak`, ...
    public func backupURL(suffix: String? = nil) -> URL {
        let fileManager = FileManager.default
        let folder = url.deletingLastPathComponent()
        let base = url.lastPathComponent + (suffix.map { ".\($0)" } ?? "")
        var candidate = folder.appendingPathComponent(base + ".bak")
        var n = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base).\(n).bak")
            n += 1
        }
        return candidate
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case LayoutDocumentError.unsupportedVersion(let version):
            return "The layouts file was saved by a newer version of the app (format \(version))."
        case LayoutDocumentError.unknownValue(let what):
            return "The layouts file was saved by a newer version of the app (it uses \(what))."
        case let error as DecodingError:
            switch error {
            case let .dataCorrupted(context), let .keyNotFound(_, context), let .typeMismatch(_, context), let .valueNotFound(_, context):
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
            @unknown default:
                return String(describing: error)
            }
        default:
            return String(describing: error)
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder { JSONDecoder() }
}
