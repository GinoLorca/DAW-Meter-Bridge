import BridgeLayout
import CoreGraphics
import Foundation
import Testing

@Suite struct DocumentCodingTests {
    static func sampleDocument() -> LayoutDocument {
        let lgPlacement = TemplatePlacement.centered(.bronxRow, displaySize: Fixtures.lg.pointSize, pointsPerMillimeter: Fixtures.lgPointsPerMillimeter, meterHeight: 150)
        var bronx = TemplateBuilder.profile(named: "Bronx — UF8", template: .bronxRow, on: Fixtures.lg, placement: lgPlacement)
        bronx.displays[0].groups.append(
            StripGroup(name: "Context", binding: .trackList(offset: 8), stripCount: 4, frame: CGRect(x: 10.25, y: 0, width: 400, height: 150), isVisible: false)
        )
        let wingPlacement = TemplatePlacement.centered(.wingMCUPlus2Extenders, displaySize: Fixtures.brooklyn.pointSize, pointsPerMillimeter: 2.2, meterY: 20, meterHeight: 200)
        let brooklyn = TemplateBuilder.profile(named: "Brooklyn — WING", template: .wingMCUPlus2Extenders, on: Fixtures.brooklyn, placement: wingPlacement)
        return LayoutDocument(profiles: [bronx, brooklyn], activeProfileID: brooklyn.id, selectionMode: .manual)
    }

    @Test func documentRoundTripsThroughJSON() throws {
        let document = Self.sampleDocument()
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(LayoutDocument.self, from: data)
        #expect(decoded == document)
        #expect(decoded.profiles[1].allGroups.count == 6)
        #expect(decoded.profiles[0].displays[0].groups[2].isVisible == false)
    }

    @Test func jsonIsReadable() throws {
        let group = StripGroup(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "UF1",
            binding: .selectedTrack,
            stripCount: 1,
            frame: CGRect(x: 1, y: 2, width: 3, height: 4)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(group), as: UTF8.self)
        #expect(json == #"{"binding":{"type":"selectedTrack"},"frame":{"height":4,"width":3,"x":1,"y":2},"id":"00000000-0000-0000-0000-000000000001","name":"UF1","strips":1,"visible":true}"#)

        let fingerprint = String(decoding: try encoder.encode(Fixtures.bar), as: UTF8.self)
        #expect(fingerprint.contains(#""points":{"height":515,"width":1920}"#))
        #expect(fingerprint.contains(#""uuid":"BAR-0001""#))
    }

    @Test func missingOptionalFieldsGetDefaults() throws {
        let json = #"""
        {"version":1,"profiles":[{"name":"Hand-written","displays":[{"display":{"name":"LG ULTRAWIDE"},
         "groups":[{"binding":{"type":"surfaceUnit","unit":0},"strips":8,"frame":{"x":0,"y":0,"width":800,"height":100}}]}]}]}
        """#
        let document = try JSONDecoder().decode(LayoutDocument.self, from: Data(json.utf8))
        let group = try #require(document.profiles.first?.allGroups.first)
        #expect(group.binding == .surfaceUnit(index: 0, firstStrip: 0))
        #expect(group.isVisible)
        #expect(group.physicalPitchMillimeters == nil)
        #expect(document.selectionMode == .automatic)
        #expect(document.activeProfileID == nil)
        #expect(document.profiles[0].surfaceHint == nil)
        #expect(document.profiles[0].displays[0].pointsPerMillimeter == nil)
        #expect(document.profiles[0].displays[0].fingerprint.uuid == nil)
        #expect(document.profiles[0].displays[0].fingerprint.pointSize == .zero)
    }

    @Test func newerVersionIsRefused() {
        #expect(throws: LayoutDocumentError.unsupportedVersion(2)) {
            try JSONDecoder().decode(LayoutDocument.self, from: Data(#"{"version":2,"profiles":[]}"#.utf8))
        }
    }
}

@Suite struct LayoutStoreTests {
    @Test func defaultLocationIsInApplicationSupport() {
        let path = LayoutStore.defaultURL.path
        #expect(path.hasSuffix("/Library/Application Support/DAW Meter Bridge/layouts.json"))
    }

    @Test func missingFileGivesAnEmptyDocument() throws {
        let folder = Fixtures.temporaryDirectory()
        let result = try LayoutStore(url: folder.appendingPathComponent("layouts.json")).load()
        #expect(result.status == .missing)
        #expect(result.document == .empty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func saveThenLoadRoundTrips() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The folder does not exist yet; save creates it.
        let store = LayoutStore(url: folder.appendingPathComponent("nested/layouts.json"))
        let document = DocumentCodingTests.sampleDocument()
        try store.save(document)
        let result = try store.load()
        #expect(result.status == .loaded)
        #expect(result.document == document)

        // Saving again replaces the file in place and leaves no temporary files behind.
        var changed = document
        changed.selectionMode = .automatic
        try store.save(changed)
        #expect(try store.load().document == changed)
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("nested").path)
        #expect(contents == ["layouts.json"])
    }

    @Test func unreadableFileIsKeptAsBackup() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("layouts.json")
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: url)

        let store = LayoutStore(url: url)
        let result = try store.load()
        let backup = folder.appendingPathComponent("layouts.json.bak")
        guard case let .recovered(backupURL, reason) = result.status else {
            Issue.record("expected recovery, got \(result.status)")
            return
        }
        #expect(backupURL.standardizedFileURL == backup.standardizedFileURL)
        #expect(!reason.isEmpty)
        #expect(result.document == .empty)
        #expect(try Data(contentsOf: backup) == garbage)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        // A second bad file never overwrites the first backup.
        try Data("[]".utf8).write(to: url)
        guard case let .recovered(secondBackup, _) = try store.load().status else {
            Issue.record("expected a second recovery")
            return
        }
        #expect(secondBackup.lastPathComponent == "layouts.json.1.bak")
        #expect(try Data(contentsOf: backup) == garbage)

        // After recovery the app can save a fresh file.
        try store.save(.empty)
        #expect(try store.load().status == .loaded)
    }

    @Test(arguments: [
        (#"{"version":99,"profiles":[]}"#, "format 99"),
        (#"{"version":1,"profiles":[{"name":"P","displays":[{"display":{"name":"LG"},"groups":[{"binding":{"type":"returns"},"strips":4,"frame":{"x":0,"y":0,"width":400,"height":100}}]}]}]}"#, "returns"),
        (#"{"version":1,"profiles":[],"selection":"perStudio"}"#, "perStudio"),
    ])
    func fileFromANewerAppIsLeftUntouched(json: String, mentions: String) throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("layouts.json")
        try Data(json.utf8).write(to: url)

        let result = try LayoutStore(url: url).load()
        guard case let .newerFormat(reason) = result.status else {
            Issue.record("expected a newer-format result, got \(result.status)")
            return
        }
        #expect(reason.contains("newer version"))
        #expect(reason.contains(mentions))
        #expect(result.document == .empty)
        // Not moved aside: the newer app still finds its layouts.
        #expect(try Data(contentsOf: url) == Data(json.utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["layouts.json"])
    }

    @Test(arguments: [
        #"{"type":"surfaceUnit","unit":2000000000000000000}"#,
        #"{"type":"surfaceUnit","unit":-1}"#,
        #"{"type":"surfaceUnit","unit":0,"firstStrip":8}"#,
        #"{"type":"trackList","offset":9223372036854775806}"#,
        #"{"type":"trackList","offset":-3}"#,
    ])
    func outOfRangeBindingsAreCorruptNotACrash(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StripBinding.self, from: Data(json.utf8))
        }
    }

    @Test func backupsGetFreeNumberedNames() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LayoutStore(url: folder.appendingPathComponent("layouts.json"))
        #expect(try store.copyToBackup(suffix: "before-reset") == nil, "nothing to back up yet")
        let calibrated = DocumentCodingTests.sampleDocument()
        try store.save(calibrated)
        let first = try #require(try store.copyToBackup(suffix: "before-reset"))
        try store.save(.empty)
        let second = try #require(try store.copyToBackup(suffix: "before-reset"))
        #expect(first.lastPathComponent == "layouts.json.before-reset.bak")
        #expect(second.lastPathComponent == "layouts.json.before-reset.1.bak")
        // The first backup still holds the original layout.
        let original = try JSONDecoder().decode(LayoutDocument.self, from: Data(contentsOf: first))
        #expect(original == calibrated)
    }
}
