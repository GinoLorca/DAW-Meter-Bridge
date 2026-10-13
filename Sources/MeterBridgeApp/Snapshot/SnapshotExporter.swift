import AppKit
import BridgeLayout
import MeterCore
import MeterRendering

/// `--snapshot <dir>`: runs the source without panels, lets data arrive, renders every placed strip
/// group to PNG with `BankView.renderPNG` and writes summary.json. Nothing is saved.
@MainActor
final class SnapshotExporter {
    let controller: AppController
    let directory: URL
    /// Minimum time to let data arrive.
    let wait: TimeInterval
    /// For Live: keep waiting up to this long for a connection with tracks and meters.
    let maxWait: TimeInterval
    /// After the data first looks complete, wait this much longer so meters fill.
    let settle: TimeInterval = 0.5

    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var readyAt: TimeInterval?
    private var completion: (@MainActor (Int32) -> Void)?

    init(controller: AppController, directory: URL, wait: TimeInterval) {
        self.controller = controller
        self.directory = directory
        self.wait = wait
        maxWait = max(wait, 10)
    }

    /// Starts the controller and calls `completion` with the exit code once the files are written.
    func run(completion: @escaping @MainActor (Int32) -> Void) {
        self.completion = completion
        controller.start()
        startedAt = Self.now
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Advances the meters like a display link would, and exports when the data is in.
    private func tick() {
        let now = Self.now
        _ = controller.frameClock.advance(controller.store, to: now)
        let elapsed = now - startedAt
        if readyAt == nil, hasData { readyAt = now }
        let settled = readyAt.map { now - $0 >= settle } ?? false
        guard (elapsed >= wait && settled) || elapsed >= maxWait else { return }
        timer?.invalidate()
        timer = nil
        let code = export(waited: elapsed)
        controller.shutdown()
        completion?(code)
    }

    /// The simulator always has data; Live needs a connection, a track list and some meters.
    private var hasData: Bool {
        let snapshot = controller.snapshot
        guard controller.sourceKind == .live else { return snapshot.connection.isConnected }
        guard snapshot.connection.isConnected, !snapshot.tracks.isEmpty else { return false }
        return snapshot.tracks.contains { controller.store.state(for: $0.id).lastUpdate > startedAt }
    }

    private func export(waited: TimeInterval) -> Int32 {
        let snapshot = controller.snapshot
        let store = controller.store
        let settings = controller.settings
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var groups: [SnapshotSummary.Group] = []
            for (index, placement) in controller.presentation.placements.enumerated() {
                let group = placement.group
                let states = StripStateBuilder.states(
                    for: group.resolveTracks(in: snapshot), snapshot: snapshot, store: store, mixFocus: settings.mixFocus
                )
                let scale = placement.display.backingScale
                let fileName = String(format: "%02d-%@.png", index + 1, Self.fileSafe(group.name))
                guard let png = BankView.renderPNG(
                    strips: states,
                    style: settings.style,
                    size: group.frame.size,
                    scale: scale,
                    stripCount: group.stripCount,
                    calibration: store.calibration
                ) else {
                    throw SnapshotError.renderFailed(group.name)
                }
                try png.write(to: directory.appendingPathComponent(fileName), options: .atomic)
                groups.append(SnapshotSummary.Group(
                    name: group.name,
                    binding: SnapshotSummary.describe(group.binding),
                    stripCount: group.stripCount,
                    display: placement.display.name,
                    frame: .init(group.frame),
                    globalFrame: .init(placement.globalFrame),
                    shownOnStandInDisplay: placement.isFallback,
                    image: fileName,
                    imagePixels: [Int((group.frame.width * scale).rounded()), Int((group.frame.height * scale).rounded())],
                    strips: states.enumerated().map { SnapshotSummary.strip($1, index: $0, calibration: store.calibration) }
                ))
            }
            let summary = makeSummary(groups: groups, waited: waited)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(summary).write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
            print("Snapshot: \(groups.count) group(s) from \(summary.source) (\(summary.connection), \(summary.trackCount) tracks) written to \(directory.path)")
            for warning in summary.warnings { print("  warning: \(warning)") }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
            return 1
        }
    }

    private func makeSummary(groups: [SnapshotSummary.Group], waited: TimeInterval) -> SnapshotSummary {
        let snapshot = controller.snapshot
        let name: (TrackID?) -> String? = { id in id.flatMap { snapshot.track($0)?.name } }
        return SnapshotSummary(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            source: controller.source?.displayName ?? controller.sourceKind.title,
            status: controller.sourceStatusLine,
            connection: SnapshotSummary.describe(snapshot.connection),
            warnings: controller.statusWarnings,
            trackCount: snapshot.tracks.count,
            selectedTrack: name(snapshot.selected),
            units: snapshot.units.map { unit in
                SnapshotSummary.Unit(slot: unit.slot, script: unit.scriptName, role: unit.role.rawValue, strips: unit.strips.map(name))
            },
            activeProfile: controller.document.activeProfile?.name,
            profiles: controller.document.profiles.map(\.name),
            layoutsFile: controller.layoutStore.url.path,
            displays: controller.displayManager.displays.map { display in
                SnapshotSummary.Display(
                    name: display.name,
                    isMain: display.isMain,
                    frame: .init(display.frame),
                    backingScale: Double(display.backingScale),
                    physicalWidthMM: Double(display.physicalSizeMillimeters.width),
                    physicalHeightMM: Double(display.physicalSizeMillimeters.height),
                    pointsPerMM: display.pointsPerMillimeter
                )
            },
            groups: groups,
            waitedSeconds: (waited * 100).rounded() / 100
        )
    }

    private static func fileSafe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? "group" : result
    }

    enum SnapshotError: Error, CustomStringConvertible {
        case renderFailed(String)

        var description: String {
            switch self {
            case let .renderFailed(name): return "could not render group “\(name)”"
            }
        }
    }
}
