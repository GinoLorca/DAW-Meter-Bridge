import BridgeProtocol
import Dispatch
import Foundation
import MeterCore
import os

let liveLog = Logger(subsystem: "DAWMeterBridge", category: "LiveSource")

/// Tracks, mix state, surfaces and meters from Ableton Live, through the MeterBridge Remote
/// Script over UDP on 127.0.0.1 (docs/PROTOCOL.md).
///
/// - Listens on ``LiveSourceConfiguration/listenPort`` (47800) and sends to
///   ``LiveSourceConfiguration/scriptPort`` (47801).
/// - Sends `sub` every second, and `watch` when it changes and with every 5th `sub`.
/// - Counts as disconnected after 3 s without any message, and drops its cached state when a
///   `hello` carries a new session.
/// - Applies mute/solo/arm/select/volume optimistically so the UI responds at once; Live's
///   echoes correct it. Volume commands are throttled to 30 per second per track, and the
///   final value of a drag (``BridgeCommand/endVolumeDrag(_:_:)``) is sent at once with
///   `"end": true`, so Live records the drag as one gesture and one undo step.
/// - If the listening port is taken, the connection becomes `.disconnected(reason:)` with a
///   warning, and binding is retried every ``LiveSourceConfiguration/bindRetryInterval``.
/// - Every ``start()`` picks a new `app` value for `sub`, so the script resends its full state
///   even when the app (or this source) restarts within the script's 5 s timeout. For a script
///   that ignores `app`: when Live is sending but no `hello` came since ``start()``, the source
///   pauses `sub` once for ``LiveSourceConfiguration/resubscribeGap`` so the script starts a new
///   subscription and sends everything again.
///
/// Socket I/O runs on a private serial queue; everything else runs on the main actor.
@MainActor
public final class LiveSource: MeterSource {
    public let configuration: LiveSourceConfiguration
    public let displayName = "Ableton Live"
    public weak var delegate: (any MeterSourceDelegate)?
    public internal(set) var snapshot = BridgeSnapshot(connection: .idle)

    /// Port actually listened on while running (useful when ``LiveSourceConfiguration/listenPort`` is 0).
    public private(set) var boundPort: UInt16?
    /// `session` of the last `hello`.
    public internal(set) var session: Int64?
    /// Remote Script version from the last `hello`.
    public internal(set) var scriptVersion: String?
    /// Live version from the last `hello`.
    public internal(set) var liveVersion: String?
    /// Meter rate the script reported in its last `hello`.
    public internal(set) var scriptMeterRate: Int?
    /// Text of the last `err` message from the script.
    public internal(set) var lastScriptError: String?
    /// Whether ``start()`` was called without a matching ``stop()``.
    public var isRunning: Bool { running }

    // State shared with the LiveSource+*.swift extensions.
    var running = false
    var startedAt: TimeInterval = 0
    var lastHeard: TimeInterval?
    var watched: Set<TrackID> = []
    var assembler: TrackListAssembler
    var listGeneration: Int?
    var lastMeterSeq: Int?
    var staleMeterRun = 0
    var throttle: VolumeThrottle
    var volumeHolds: [TrackID: TimeInterval] = [:]
    var socketWarning: String?
    var versionWarning: String?
    var surfaceWarning: String?
    var reportedVersions: Set<Int?> = []
    var reportedUnknownTypes: Set<String> = []
    var malformedCount = 0
    /// Whether a `hello` arrived since the last ``start()``.
    var helloSinceStart = false

    private var endpoint: UDPEndpoint?
    private var housekeeping: (any DispatchSourceTimer)?
    private var lastSubscribe: TimeInterval?
    /// The `app` value of this run's `sub` messages; new on every ``start()``.
    private var appNonce = 0
    private var lastBindAttempt: TimeInterval?
    private var subscribeCount = 0
    /// While set, `sub` is held back so the script drops its old subscription.
    private var subscribePausedUntil: TimeInterval?
    private var didPauseForState = false
    private var lastPublished: BridgeSnapshot?

    /// A source with the given ports and timing; nothing happens until ``start()``.
    public init(configuration: LiveSourceConfiguration = .standard) {
        self.configuration = configuration
        assembler = TrackListAssembler(timeout: configuration.trackListTimeout)
        throttle = VolumeThrottle(maxPerSecond: configuration.maxVolumeMessagesPerSecond)
    }

    /// A source on custom ports with the default timing.
    public convenience init(listenPort: UInt16, scriptPort: UInt16) {
        self.init(configuration: LiveSourceConfiguration(listenPort: listenPort, scriptPort: scriptPort))
    }

    // MARK: Lifecycle

    /// Binds the listening port, sends the first `sub` and starts the keep-alive timer.
    /// Reports `.connecting`, or `.disconnected(reason:)` if the port is in use.
    public func start() {
        guard !running else { return }
        running = true
        let now = Self.now()
        startedAt = now
        appNonce = Int.random(in: 1...Int(Int32.max))
        lastHeard = nil
        lastSubscribe = nil
        subscribeCount = 0
        helloSinceStart = false
        subscribePausedUntil = nil
        didPauseForState = false
        snapshot.connection = .connecting
        openSocket(at: now)
        startHousekeeping()
        housekeepingTick()
    }

    /// Closes the socket and stops the timers. Cached tracks are kept for a quick restart (the next
    /// ``start()`` sends a new `app` value, so the script resends its state); the script stops
    /// sending on its own after 5 s without `sub`.
    public func stop() {
        guard running else { return }
        running = false
        housekeeping?.cancel()
        housekeeping = nil
        endpoint?.close()
        endpoint = nil
        boundPort = nil
        snapshot.connection = .idle
        publishIfChanged()
    }

    /// Sets the `watch` list (tracks shown on the bridge but not on a surface strip) and sends it if it changed.
    public func setWatchedTracks(_ ids: Set<TrackID>) {
        guard ids != watched else { return }
        watched = ids
        if running { sendWatch() }
    }

    // MARK: Sending

    /// Encodes and sends one message to the script. Does nothing while the socket is closed.
    func transmit(_ message: OutgoingMessage) {
        guard let endpoint else { return }
        do {
            let data = try WireCodec.encode(message)
            endpoint.send(data, toPort: configuration.scriptPort) { error in
                liveLog.error("Sending to the Live script failed: \(error.message, privacy: .public)")
            }
        } catch {
            liveLog.error("Could not encode \(message.messageType, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Sends the watch list, ordered like the track list and capped at the meter limit.
    func sendWatch() {
        let ordered = watched.sorted { lhs, rhs in
            let left = snapshot.track(lhs)?.index ?? Int.max
            let right = snapshot.track(rhs)?.index ?? Int.max
            return left != right ? left < right : lhs < rhs
        }
        if ordered.count > WireProtocol.maxMeterEntries {
            liveLog.warning("Watching \(ordered.count) tracks; only the first \(WireProtocol.maxMeterEntries) are metered")
        }
        transmit(.watch(WatchMessage(ids: Array(ordered.prefix(WireProtocol.maxMeterEntries)))))
    }

    private func sendSubscribe(at now: TimeInterval) {
        lastSubscribe = now
        let port = boundPort ?? configuration.listenPort
        transmit(.subscribe(SubscribeMessage(port: port, hz: configuration.meterRate, app: appNonce)))
        if subscribeCount % configuration.watchResendEvery == 0 { sendWatch() }
        subscribeCount += 1
    }

    // MARK: Socket and housekeeping

    private func openSocket(at now: TimeInterval) {
        lastBindAttempt = now
        do {
            let endpoint = try UDPEndpoint(port: configuration.listenPort, label: "DAWMeterBridge.LiveSource.socket") { [weak self] datagrams in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(datagrams) }
                }
            }
            self.endpoint = endpoint
            boundPort = endpoint.port
            if socketWarning != nil {
                socketWarning = nil
                startedAt = now
                snapshot.connection = .connecting
                updateWarnings()
                liveLog.info("Listening on 127.0.0.1:\(endpoint.port) again")
            }
        } catch {
            let reason = error.message
            if socketWarning == nil {
                liveLog.error("Cannot listen for Live: \(reason, privacy: .public)")
            }
            socketWarning = "Cannot listen for Live: \(reason). Quit the other app using it or change the port."
            snapshot.connection = .disconnected(reason: reason)
            updateWarnings()
        }
        publishIfChanged()
    }

    private func startHousekeeping() {
        let interval = configuration.housekeepingInterval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.housekeepingTick() }
        }
        timer.resume()
        housekeeping = timer
    }

    /// Keep-alive, bind retry, silence detection and track-list timeout.
    private func housekeepingTick() {
        guard running else { return }
        let now = Self.now()
        if endpoint == nil {
            if now - (lastBindAttempt ?? 0) >= configuration.bindRetryInterval { openSocket(at: now) }
            guard endpoint != nil else { return }
        }
        pauseSubscribeIfStateIsMissing(at: now)
        if let until = subscribePausedUntil, now >= until { subscribePausedUntil = nil }
        let tolerance = configuration.housekeepingInterval / 2
        if subscribePausedUntil == nil,
           lastSubscribe.map({ now - $0 >= configuration.subscribeInterval - tolerance }) ?? true {
            sendSubscribe(at: now)
        }
        if versionWarning == nil, now - (lastHeard ?? startedAt) > configuration.silenceTimeout {
            if case .disconnected = snapshot.connection {} else {
                let seconds = String(format: "%g", configuration.silenceTimeout)
                let reason = lastHeard == nil
                    ? "No answer from Live. Is the MeterBridge control surface selected in Live's Link, Tempo & MIDI settings?"
                    : "Live stopped sending for \(seconds) s."
                liveLog.info("Disconnected: \(reason, privacy: .public)")
                snapshot.connection = .disconnected(reason: reason)
            }
        }
        if assembler.expire(at: now) {
            liveLog.warning("Discarded an incomplete track list after \(self.configuration.trackListTimeout) s")
        }
        publishIfChanged()
    }

    /// Live is talking to us but sent no `hello` since ``start()``: a script that ignores `sub.app`
    /// still holds the subscription of an app instance (or an earlier run of this source) that
    /// stopped less than 5 s ago. Hold back `sub` once so it starts over. Cached tracks don't
    /// count as state: they may be stale.
    private func pauseSubscribeIfStateIsMissing(at now: TimeInterval) {
        guard !didPauseForState, !helloSinceStart, lastHeard != nil,
              now - startedAt > configuration.missingStateTimeout else { return }
        didPauseForState = true
        subscribePausedUntil = now + configuration.resubscribeGap
        liveLog.info("Live is sending but sent no state; pausing sub for \(self.configuration.resubscribeGap) s so the script resubscribes")
    }

    // MARK: Snapshot

    func updateWarnings() {
        snapshot.warnings = [socketWarning, versionWarning, surfaceWarning].compactMap { $0 }
    }

    /// Tells the delegate about the snapshot if it changed since the last call.
    func publishIfChanged() {
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        delegate?.meterSource(self, didUpdate: snapshot)
    }

    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
