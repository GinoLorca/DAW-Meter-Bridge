import BridgeProtocol
import Foundation
import MeterCore
@testable import MeterSources
import Testing

/// LiveSource against a fake Remote Script over real UDP sockets on free ports.
@Suite("LiveSource loopback", .serialized)
@MainActor
struct LiveSourceLoopbackTests {
    @Test func subscribesWithItsPortAndKeepsAlive() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        #expect(harness.source.snapshot.connection == .idle)
        harness.source.start()
        #expect(harness.source.snapshot.connection == .connecting)
        #expect(harness.source.boundPort != nil)

        let first = await harness.script.next { if case .subscribe = $0 { true } else { false } }
        guard case let .subscribe(sub)? = first?.message else {
            Issue.record("no sub")
            return
        }
        #expect(sub.port == harness.appPort)
        #expect(sub.hz == 30)
        let app = try #require(sub.app)
        #expect(app > 0)
        // The first sub comes with the watch list.
        let watch = await harness.script.next { if case .watch = $0 { true } else { false } }
        #expect(watch?.message == .watch(WatchMessage(ids: [])))
        // Keep-alives keep coming (every 50 ms here), each naming the bound port and the same app value.
        let later = await harness.script.collect { subscribes(in: $0).count >= 3 }
        #expect(subscribes(in: later).count >= 3)
        #expect(subscribes(in: later).allSatisfy { $0 == SubscribeMessage(port: harness.appPort, hz: 30, app: app) })
        let raw = await harness.script.next { if case .subscribe = $0 { true } else { false } }
        #expect(raw.map { String(decoding: $0.raw, as: UTF8.self).contains(#""app":\#(app)"#) } == true)
    }

    @Test func everyStartSendsANewAppValue() async throws {
        // Source Live -> Simulator -> Live within the script's 5 s timeout: a new app value makes the
        // script resend hello, tracks, sel and surfaces, which may have changed meanwhile.
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect(session: 1, gen: 1)
        let before = await harness.script.collect { !subscribes(in: $0).isEmpty }
        let first = try #require(subscribes(in: before).last?.app)
        harness.source.stop()
        harness.script.discardInbox()
        harness.source.start()
        let after = await harness.script.collect { subscribes(in: $0).contains { $0.app != first } }
        let second = try #require(subscribes(in: after).last?.app)
        #expect(second != first)

        // The script answers the new subscription with its full state (same session, newer list).
        try harness.send(.hello(HelloMessage(script: "0.1.0", live: "12.4.6", session: 1, hz: 30, vc: nil)))
        var tracks = LiveHarness.tracks
        tracks[2].name = "Bass Renamed"
        for part in try TracksMessage.split(tracks, gen: 2) { try harness.send(.tracks(part)) }
        let banked: [TrackID?] = [LiveHarness.id(8)] + Array(repeating: nil, count: 7)
        try harness.send(.surfaces(SurfacesMessage(units: [
            WireSurfaceUnit(slot: 1, script: "MackieControl", role: "main", strips: banked),
        ])))
        #expect(await waitUntil {
            harness.source.snapshot.track(LiveHarness.id(2))?.name == "Bass Renamed"
                && harness.source.snapshot.units.first?.strips == banked
        })
        #expect(harness.source.snapshot.connection == .connected)
    }

    @Test func fullStateBuildsTheSnapshot() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        let snapshot = harness.source.snapshot
        #expect(snapshot.connection == .connected)
        #expect(snapshot.tracks == LiveHarness.tracks.map(\.trackInfo))
        #expect(snapshot.selected == LiveHarness.id(0))
        #expect(snapshot.units.count == 1)
        #expect(snapshot.units[0].role == .main)
        #expect(snapshot.units[0].strips == (0..<8).map { LiveHarness.id($0) })
        #expect(snapshot.volumeCurve != nil)
        #expect(snapshot.warnings.isEmpty)
        #expect(harness.source.session == 1)
        #expect(harness.source.scriptVersion == "0.1.0")
        #expect(harness.source.liveVersion == "12.4.6")
        #expect(harness.delegate.lastSnapshot == snapshot)
    }

    @Test func metersReachTheDelegateInOrder() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        let first = [MeterLevel(id: LiveHarness.id(0), left: 0.6123, right: 0.5871), MeterLevel(id: LiveHarness.id(11), left: 0.5, right: 0.4)]
        try harness.send(.meters(MetersMessage(seq: 10, levels: first)))
        // An older sequence number is ignored.
        try harness.send(.meters(MetersMessage(seq: 5, levels: [MeterLevel(id: LiveHarness.id(1), left: 1, right: 1)])))
        let second = [MeterLevel(id: LiveHarness.id(0), left: 0, right: 0)]
        try harness.send(.meters(MetersMessage(seq: 11, levels: second)))
        #expect(await waitUntil { harness.delegate.meterBatches.count >= 2 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.delegate.meterBatches == [first, second])
    }

    @Test func trackDeltasApplyOnlyToKnownTracksOfTheCurrentList() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect(gen: 4)
        var muted = LiveHarness.tracks[2]
        muted.isMuted = true
        try harness.send(.track(TrackMessage(gen: 4, item: muted)))
        var stranger = LiveHarness.tracks[3]
        stranger.id = TrackID(42)
        stranger.isSoloed = true
        try harness.send(.track(TrackMessage(gen: 4, item: stranger)))
        var stale = LiveHarness.tracks[5]
        stale.name = "Old Name"
        try harness.send(.track(TrackMessage(gen: 3, item: stale)))
        try harness.send(.selection(SelectionMessage(id: nil)))
        #expect(await waitUntil { harness.source.snapshot.selected == nil })
        let snapshot = harness.source.snapshot
        #expect(snapshot.track(LiveHarness.id(2))?.isMuted == true)
        #expect(!snapshot.contains(TrackID(42)))
        #expect(snapshot.track(LiveHarness.id(5))?.name == "Lead Vox")
    }

    @Test func surfacesWarningBecomesASnapshotWarning() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        try harness.send(.surfaces(SurfacesMessage(
            units: [WireSurfaceUnit(slot: 1, script: "MackieControl", role: "main", strips: Array(repeating: nil, count: 8))],
            warn: "MackieControl internals changed"
        )))
        #expect(await waitUntil { harness.source.snapshot.warnings == ["MackieControl internals changed"] })
        #expect(harness.source.snapshot.units[0].strips.allSatisfy { $0 == nil })
    }

    @Test func commandsArriveAsCmdJSONWithOptimisticUpdates() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        let source = harness.source
        let kick = LiveHarness.id(0)
        let bass = LiveHarness.id(2)
        let main = LiveHarness.id(11)

        source.send(.setMute(kick, true))
        #expect(source.snapshot.track(kick)?.isMuted == true) // optimistic, before any echo
        #expect(await harness.script.nextCommand()?.command == .setMute(kick, true))

        source.send(.select(bass))
        #expect(source.snapshot.selected == bass)
        #expect(await harness.script.nextCommand()?.command == .select(bass))

        source.send(.setSolo(kick, true, exclusive: false))
        let additive = await harness.script.nextCommand()
        #expect(additive?.command == .setSolo(kick, true, exclusive: false))
        source.send(.setSolo(bass, true, exclusive: nil))
        let exclusive = await harness.script.nextCommand()
        #expect(exclusive?.command == .setSolo(bass, true, exclusive: nil))
        let json = try #require(exclusive.map { String(decoding: $0.raw, as: UTF8.self) })
        #expect(json.contains(#""excl":null"#))
        #expect(json.contains(#""id":\#(bass.rawValue)"#))
        // Exclusive by default: the kick's solo is cleared, others are muted via solo, returns never.
        #expect(source.snapshot.track(kick)?.isSoloed == false)
        #expect(source.snapshot.track(bass)?.isSoloed == true)
        #expect(source.snapshot.track(kick)?.isMutedViaSolo == true)
        #expect(source.snapshot.track(LiveHarness.id(9))?.isMutedViaSolo == false)
        #expect(source.snapshot.track(main)?.isMutedViaSolo == false)

        source.send(.setArm(LiveHarness.id(3), true))
        #expect(source.snapshot.track(LiveHarness.id(3))?.isArmed == true)
        #expect(await harness.script.nextCommand()?.command == .setArm(LiveHarness.id(3), true))

        // Ops Live would reject are not sent: mute/solo on Main, arm on a return.
        source.send(.setMute(main, true))
        source.send(.setSolo(main, true, exclusive: nil))
        source.send(.setArm(LiveHarness.id(9), true))
        source.send(.select(main))
        #expect(await harness.script.nextCommand()?.command == .select(main))

        // Live's echo corrects the optimistic state.
        try harness.send(.track(TrackMessage(gen: 1, item: LiveHarness.tracks[0])))
        #expect(await waitUntil { source.snapshot.track(kick)?.isMuted == false })
    }

    @Test func volumeDragsAreThrottledAndEndOnTheFinalValue() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        let source = harness.source
        let keys = LiveHarness.id(3)
        harness.script.discardInbox()

        // A burst of 50 values at once: one now, one flush with the last value.
        for step in 0..<50 { source.send(.setVolume(keys, 0.5 + Double(step) * 0.01)) }
        #expect(source.snapshot.track(keys)?.volume == 0.99)
        #expect(source.snapshot.track(keys)?.volumeText == VolumeCurve.liveApproximation.text(atNormalized: 0.99))
        var burst = volumes(in: await harness.script.collect { volumes(in: $0, for: keys).last == 0.99 }, for: keys)
        burst += volumes(in: await harness.script.collect(for: 0.1), for: keys)
        #expect(burst == [0.5, 0.99])

        // A 0.3 s drag at ~200 Hz: at most 30/s (plus the first and final), ending on the final value.
        let start = Date()
        var value = 0.2
        while Date().timeIntervalSince(start) < 0.3 {
            value += 0.001
            source.send(.setVolume(keys, value))
            try? await Task.sleep(for: .milliseconds(5))
        }
        let final = CommandMessage.wireVolume(value)
        var drag = volumes(in: await harness.script.collect { volumes(in: $0, for: keys).last == final }, for: keys)
        let elapsed = Date().timeIntervalSince(start)
        drag += volumes(in: await harness.script.collect(for: 0.1), for: keys)
        #expect(drag.count >= 2)
        #expect(Double(drag.count) <= elapsed * 30 + 2)
        #expect(drag.last == final)
    }

    @Test func theEndOfADragGoesOutAtOnceMarkedEnd() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        let source = harness.source
        let keys = LiveHarness.id(3)
        harness.script.discardInbox()

        // Mid-drag: one value sent, a newer one held for the throttle's flush.
        source.send(.setVolume(keys, 0.5))
        source.send(.setVolume(keys, 0.6))
        // Mouse up: the final value replaces the held one and is sent now with "end":true.
        source.send(.endVolumeDrag(keys, 0.42))
        #expect(source.snapshot.track(keys)?.volume == 0.42)
        let first = await harness.script.nextCommand()
        #expect(first?.command == .setVolume(keys, 0.5))
        let last = await harness.script.nextCommand()
        #expect(last?.command == .endVolumeDrag(keys, 0.42))
        let json = try #require(last.map { String(decoding: $0.raw, as: UTF8.self) })
        #expect(json.contains(#""end":true"#))
        #expect(json.contains(#""op":"vol""#))
        // The held 0.6 is never sent afterwards.
        #expect(volumes(in: await harness.script.collect(for: 0.15), for: keys).isEmpty)

        // A later drag on the same track starts normally.
        source.send(.setVolume(keys, 0.3))
        let next = await harness.script.collect { volumes(in: $0, for: keys).last == 0.3 }
        #expect(volumes(in: next, for: keys).last == 0.3)
    }

    @Test func volumeEchoesDuringADragDoNotJumpBack() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        let source = harness.source
        let pad = LiveHarness.id(7)
        source.send(.setVolume(pad, 0.4))
        // Live echoes an older value while the user still holds the fader.
        try harness.send(.track(TrackMessage(gen: 1, item: LiveHarness.tracks[7])))
        var renamed = LiveHarness.tracks[7]
        renamed.name = "Pad 2"
        try harness.send(.track(TrackMessage(gen: 1, item: renamed)))
        #expect(await waitUntil { source.snapshot.track(pad)?.name == "Pad 2" })
        #expect(source.snapshot.track(pad)?.volume == 0.4)
        // After the hold, Live's value wins again.
        try? await Task.sleep(for: .milliseconds(300))
        try harness.send(.track(TrackMessage(gen: 1, item: renamed)))
        #expect(await waitUntil { source.snapshot.track(pad)?.volume == 0.85 })
    }

    @Test func watchIsSentOnChangeOrderedByTrackAndRepeated() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        harness.script.discardInbox()
        harness.source.setWatchedTracks([LiveHarness.id(9), LiveHarness.id(4), TrackID(5)])
        let watch = await harness.script.next { if case .watch = $0 { true } else { false } }
        #expect(watch?.message == .watch(WatchMessage(ids: [LiveHarness.id(4), LiveHarness.id(9), TrackID(5)])))
        // Unchanged set: not sent again immediately, but repeated with every 5th sub.
        harness.source.setWatchedTracks([LiveHarness.id(9), LiveHarness.id(4), TrackID(5)])
        let messages = await harness.script.collect { subscribes(in: $0).count >= 11 }
        let subs = subscribes(in: messages).count
        let watches = messages.filter { if case .watch = $0 { true } else { false } }
        #expect(subs >= 11)
        #expect(watches.count >= 2)
        #expect(watches.count <= subs / 5 + 1)
        #expect(watches.allSatisfy { $0 == watch?.message })
    }

    @Test func silenceDisconnectsAndAnyMessageReconnects() async throws {
        let harness = try LiveHarness(silenceTimeout: 0.4)
        defer { harness.source.stop() }
        try await harness.connect()
        #expect(harness.source.snapshot.connection == .connected)
        let silentSince = Date()
        #expect(await waitUntil { harness.source.snapshot.connection.isDisconnected })
        #expect(Date().timeIntervalSince(silentSince) > 0.3)
        // Cached state is kept while disconnected.
        #expect(harness.source.snapshot.tracks.count == LiveHarness.tracks.count)
        try harness.send(.heartbeat(HeartbeatMessage(seq: 1)))
        #expect(await waitUntil { harness.source.snapshot.connection == .connected })
    }

    @Test func noAnswerAtAllAlsoDisconnects() async throws {
        let harness = try LiveHarness(silenceTimeout: 0.4)
        defer { harness.source.stop() }
        harness.source.start()
        #expect(await waitUntil { harness.source.snapshot.connection.isDisconnected })
        #expect(harness.delegate.snapshots.map(\.connection).contains(.connecting))
    }

    @Test func newSessionDropsCachedState() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect(session: 1, gen: 9)
        try harness.send(.meters(MetersMessage(seq: 500, levels: [MeterLevel(id: LiveHarness.id(0), left: 0.5, right: 0.5)])))
        #expect(await waitUntil { harness.delegate.meterBatches.count == 1 })

        try harness.send(.hello(HelloMessage(script: "0.1.0", live: "12.4.6", session: 2, hz: 30, vc: nil)))
        #expect(await waitUntil { harness.source.session == 2 })
        #expect(harness.source.snapshot.tracks.isEmpty)
        #expect(harness.source.snapshot.units.isEmpty)
        #expect(harness.source.snapshot.selected == nil)
        // The new session's generations and meter sequence start again from low numbers.
        let fresh = Array(LiveHarness.tracks.prefix(3))
        for part in try TracksMessage.split(fresh, gen: 1) { try harness.send(.tracks(part)) }
        try harness.send(.meters(MetersMessage(seq: 1, levels: [MeterLevel(id: fresh[0].id, left: 0.25, right: 0.25)])))
        #expect(await waitUntil { harness.source.snapshot.tracks.count == 3 && harness.delegate.meterBatches.count == 2 })
    }

    @Test func missingStateAfterAQuickRestartPausesSubOnce() async throws {
        // The script still holds the subscription of an app instance that just quit: it keeps
        // sending heartbeats and meters but no hello/tracks. The source pauses sub once so the
        // script times the old subscription out and sends its full state again.
        let harness = try LiveHarness(missingStateTimeout: 0.2, resubscribeGap: 0.6)
        defer { harness.source.stop() }
        harness.source.start()
        var arrivals: [Date] = []
        var heartbeat = 0
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, arrivals.count < 40 {
            heartbeat += 1
            try harness.send(.heartbeat(HeartbeatMessage(seq: heartbeat)))
            if await harness.script.next(timeout: 0.1, where: { if case .subscribe = $0 { true } else { false } }) != nil {
                arrivals.append(Date())
            }
            if let last = arrivals.last, arrivals.count > 1,
               last.timeIntervalSince(arrivals[arrivals.count - 2]) > 0.5 { break }
        }
        let gaps = zip(arrivals.dropFirst(), arrivals).map { $0.timeIntervalSince($1) }
        #expect(gaps.contains { $0 > 0.5 }, "no pause in sub: \(gaps)")
        #expect(harness.source.snapshot.connection == .connected)

        // Only once: without a hello, subs carry on at the normal rate afterwards.
        var later: [Date] = []
        while later.count < 8, Date() < deadline.addingTimeInterval(3) {
            heartbeat += 1
            try harness.send(.heartbeat(HeartbeatMessage(seq: heartbeat)))
            if await harness.script.next(timeout: 0.1, where: { if case .subscribe = $0 { true } else { false } }) != nil {
                later.append(Date())
            }
        }
        let laterGaps = zip(later.dropFirst(), later).map { $0.timeIntervalSince($1) }
        #expect(later.count == 8)
        #expect(laterGaps.allSatisfy { $0 < 0.4 }, "paused again: \(laterGaps)")
    }

    @Test func missingStateAfterARestartPausesSubEvenWithCachedTracks() async throws {
        // A script that ignores `sub.app` keeps the old subscription after a quick stop/start and
        // never resends its state. The cached tracks may be stale, so they don't stop the pause.
        let harness = try LiveHarness(missingStateTimeout: 0.2, resubscribeGap: 0.6)
        defer { harness.source.stop() }
        try await harness.connect()
        harness.source.stop()
        harness.source.start()
        #expect(!harness.source.snapshot.tracks.isEmpty)
        var arrivals: [Date] = []
        var heartbeat = 0
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, arrivals.count < 40 {
            heartbeat += 1
            try harness.send(.heartbeat(HeartbeatMessage(seq: heartbeat)))
            if await harness.script.next(timeout: 0.1, where: { if case .subscribe = $0 { true } else { false } }) != nil {
                arrivals.append(Date())
            }
            if let last = arrivals.last, arrivals.count > 1,
               last.timeIntervalSince(arrivals[arrivals.count - 2]) > 0.5 { break }
        }
        let gaps = zip(arrivals.dropFirst(), arrivals).map { $0.timeIntervalSince($1) }
        #expect(gaps.contains { $0 > 0.5 }, "no pause in sub: \(gaps)")
    }

    @Test func noPauseWhenTheStateArrives() async throws {
        let harness = try LiveHarness(missingStateTimeout: 0.2, resubscribeGap: 0.6)
        defer { harness.source.stop() }
        try await harness.connect()
        harness.script.discardInbox()
        var arrivals: [Date] = []
        while arrivals.count < 12 {
            guard await harness.script.next(where: { if case .subscribe = $0 { true } else { false } }) != nil else { break }
            arrivals.append(Date())
        }
        let gaps = zip(arrivals.dropFirst(), arrivals).map { $0.timeIntervalSince($1) }
        #expect(arrivals.count == 12)
        #expect(gaps.allSatisfy { $0 < 0.4 }, "paused: \(gaps)")
    }

    @Test func otherProtocolVersionsAreDroppedWithAWarning() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        harness.source.start()
        _ = await harness.script.next { if case .subscribe = $0 { true } else { false } }
        harness.script.sendRaw(Data(#"{"v":2,"t":"hb","seq":1}"#.utf8), to: harness.appPort)
        #expect(await waitUntil { !harness.source.snapshot.warnings.isEmpty })
        #expect(harness.source.snapshot.connection.isDisconnected)
        #expect(harness.source.snapshot.warnings.first?.contains("v2") == true)
        try harness.send(.heartbeat(HeartbeatMessage(seq: 2)))
        #expect(await waitUntil { harness.source.snapshot.connection == .connected })
        #expect(harness.source.snapshot.warnings.isEmpty)
    }

    @Test func garbageAndUnknownTypesAreIgnored() async throws {
        let harness = try LiveHarness()
        defer { harness.source.stop() }
        try await harness.connect()
        harness.script.sendRaw(Data("not json".utf8), to: harness.appPort)
        harness.script.sendRaw(Data(#"{"v":1,"t":"tempo","bpm":128}"#.utf8), to: harness.appPort)
        harness.script.sendRaw(Data(#"{"v":1,"t":"track","gen":1}"#.utf8), to: harness.appPort)
        try harness.send(.error(ErrorMessage(msg: "unknown track id 123 in cmd")))
        #expect(await waitUntil { harness.source.lastScriptError == "unknown track id 123 in cmd" })
        #expect(harness.source.snapshot.tracks.count == LiveHarness.tracks.count)
        #expect(harness.source.snapshot.connection == .connected)
    }

    @Test func portInUseIsReportedAndRetried() async throws {
        let first = try LiveHarness()
        first.source.start()
        let port = try #require(first.source.boundPort)

        let script = try FakeScript()
        let second = LiveSource(configuration: LiveHarness.configuration(scriptPort: script.port, listenPort: port))
        let delegate = RecordingDelegate()
        second.delegate = delegate
        defer { second.stop() }
        second.start()
        #expect(second.boundPort == nil)
        #expect(second.snapshot.connection.isDisconnected)
        #expect(second.snapshot.warnings.count == 1)
        #expect(second.snapshot.warnings.first?.contains("\(port)") == true)
        #expect(delegate.lastSnapshot?.connection.isDisconnected == true)

        // Once the port is free, the retry binds it and the warning goes away.
        first.source.stop()
        #expect(await waitUntil { second.boundPort == port })
        #expect(second.snapshot.warnings.isEmpty)
        #expect(second.snapshot.connection == .connecting)
        let sub = await script.next { if case .subscribe = $0 { true } else { false } }
        #expect(sub != nil)
    }

    @Test func stopClosesThePortAndGoesIdle() async throws {
        let harness = try LiveHarness()
        try await harness.connect()
        let port = harness.appPort
        harness.source.stop()
        #expect(harness.source.snapshot.connection == .idle)
        #expect(!harness.source.isRunning)
        // The port can be bound again immediately.
        let again = LiveSource(configuration: LiveHarness.configuration(scriptPort: harness.script.port, listenPort: port))
        again.start()
        defer { again.stop() }
        #expect(again.boundPort == port)
        // Commands while stopped are dropped.
        harness.script.discardInbox()
        harness.source.send(.select(LiveHarness.id(1)))
        let stray = await harness.script.nextCommand(timeout: 0.1)
        #expect(stray == nil)
    }

    private func subscribes(in messages: [OutgoingMessage]) -> [SubscribeMessage] {
        messages.compactMap { if case let .subscribe(body) = $0 { body } else { nil } }
    }

    private func volumes(in messages: [OutgoingMessage], for id: TrackID) -> [Double] {
        messages.compactMap {
            guard case let .command(body) = $0 else { return nil }
            switch body.command {
            case let .setVolume(target, value) where target == id, let .endVolumeDrag(target, value) where target == id:
                return value
            default:
                return nil
            }
        }
    }
}
