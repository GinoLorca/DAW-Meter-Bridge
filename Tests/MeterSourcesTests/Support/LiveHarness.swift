import BridgeProtocol
import Foundation
import MeterCore
import MeterSources
import Testing

/// A LiveSource on a free port talking to a FakeScript, with short timeouts for tests.
@MainActor
final class LiveHarness {
    let script: FakeScript
    let source: LiveSource
    let delegate = RecordingDelegate()

    /// Ids above 2^53, like real Live pointers on a 64-bit Mac.
    static func id(_ index: Int) -> TrackID { TrackID(0x7FFF_0000_0000_0000 + Int64(index)) }

    /// 9 tracks, 2 returns and Main, in Live's order.
    static let tracks: [WireTrack] = {
        let rows: [(String, TrackKind)] = [
            ("Kick", .audio), ("Snare", .audio), ("Bass", .audio), ("Keys", .midi), ("Vox", .group),
            ("Lead Vox", .audio), ("BGV L", .audio), ("Pad", .midi), ("Gtr", .audio),
            ("A Reverb", .returnTrack), ("B Delay", .returnTrack), ("Main", .main),
        ]
        return rows.enumerated().map { index, row in
            let armable = row.1 == .audio || row.1 == .midi
            return WireTrack(
                id: id(index), index: index, name: row.0, color: 0x10A4EE, kind: row.1,
                isArmed: armable ? false : nil, volume: 0.85, volumeText: "0.0 dB"
            )
        }
    }()

    /// Fast keep-alives and retries for tests. The silence timeout stays long unless a test is
    /// about silence, so a busy test machine doesn't disconnect the source mid-test.
    static func configuration(
        scriptPort: UInt16,
        listenPort: UInt16 = 0,
        silenceTimeout: TimeInterval = 3,
        missingStateTimeout: TimeInterval = 2,
        resubscribeGap: TimeInterval = 6
    ) -> LiveSourceConfiguration {
        LiveSourceConfiguration(
            listenPort: listenPort,
            scriptPort: scriptPort,
            subscribeInterval: 0.05,
            watchResendEvery: 5,
            silenceTimeout: silenceTimeout,
            trackListTimeout: 0.3,
            maxVolumeMessagesPerSecond: 30,
            volumeEchoHold: 0.25,
            bindRetryInterval: 0.1,
            missingStateTimeout: missingStateTimeout,
            resubscribeGap: resubscribeGap
        )
    }

    init(silenceTimeout: TimeInterval = 3, missingStateTimeout: TimeInterval = 2, resubscribeGap: TimeInterval = 6) throws {
        script = try FakeScript()
        source = LiveSource(configuration: Self.configuration(
            scriptPort: script.port,
            silenceTimeout: silenceTimeout,
            missingStateTimeout: missingStateTimeout,
            resubscribeGap: resubscribeGap
        ))
        source.delegate = delegate
    }

    var appPort: UInt16 { source.boundPort ?? 0 }

    func send(_ message: IncomingMessage) throws {
        try script.send(message, to: appPort)
    }

    /// Starts the source, waits for its `sub`, and plays the full post-subscribe state:
    /// hello, the track list in two parts (second part first), sel, surfaces.
    func connect(session: Int64 = 1, gen: Int = 1, tracks: [WireTrack] = LiveHarness.tracks) async throws {
        if !source.isRunning { source.start() }
        let sub = await script.next { if case .subscribe = $0 { true } else { false } }
        try #require(sub != nil, "no sub from LiveSource")
        try send(.hello(HelloMessage(
            script: "0.1.0", live: "12.4.6", session: session, hz: 30,
            vc: VolumeCurveTable(sampling: .liveApproximation)
        )))
        let parts = try TracksMessage.split(tracks, gen: gen, maxItems: 7)
        for part in parts.reversed() { try send(.tracks(part)) }
        try send(.selection(SelectionMessage(id: tracks.first?.id)))
        let strips: [TrackID?] = (0..<8).map { $0 < tracks.count ? tracks[$0].id : nil }
        try send(.surfaces(SurfacesMessage(units: [
            WireSurfaceUnit(slot: 1, script: "MackieControl", role: "main", strips: strips),
        ])))
        let ready = await waitUntil {
            source.snapshot.tracks.count == tracks.count && !source.snapshot.units.isEmpty
                && source.snapshot.selected == tracks.first?.id
        }
        try #require(ready, "LiveSource did not assemble the state")
    }
}
