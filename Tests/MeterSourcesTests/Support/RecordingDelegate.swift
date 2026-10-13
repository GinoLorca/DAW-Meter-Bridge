import Foundation
import MeterCore

/// Records everything a source tells its delegate.
@MainActor
final class RecordingDelegate: MeterSourceDelegate {
    private(set) var snapshots: [BridgeSnapshot] = []
    private(set) var meterBatches: [[MeterLevel]] = []

    var lastSnapshot: BridgeSnapshot? { snapshots.last }
    var allLevels: [MeterLevel] { meterBatches.flatMap { $0 } }

    func meterSource(_ source: any MeterSource, didUpdate snapshot: BridgeSnapshot) {
        snapshots.append(snapshot)
    }

    func meterSource(_ source: any MeterSource, didReceive levels: [MeterLevel], at time: TimeInterval) {
        meterBatches.append(levels)
    }

    func reset() {
        snapshots.removeAll()
        meterBatches.removeAll()
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

extension ConnectionState {
    var isDisconnected: Bool {
        if case .disconnected = self { true } else { false }
    }
}
