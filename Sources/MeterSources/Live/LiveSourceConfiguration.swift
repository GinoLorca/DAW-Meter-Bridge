import BridgeProtocol
import Foundation

/// Ports and timing of ``LiveSource``. The defaults follow docs/PROTOCOL.md; tests use other
/// ports and much shorter intervals.
public struct LiveSourceConfiguration: Hashable, Sendable {
    /// Port the app listens on, on 127.0.0.1. 0 picks any free port (tests); see ``LiveSource/boundPort``.
    public var listenPort: UInt16
    /// Port the Remote Script listens on, on 127.0.0.1.
    public var scriptPort: UInt16
    /// Meter rate requested in `sub`, in messages per second.
    public var meterRate: Int
    /// Seconds between `sub` keep-alives.
    public var subscribeInterval: TimeInterval
    /// `watch` is re-sent with every n-th `sub` (and whenever it changes).
    public var watchResendEvery: Int
    /// Seconds without any message before the source counts as disconnected.
    public var silenceTimeout: TimeInterval
    /// Seconds after which an incomplete chunked track list is discarded.
    public var trackListTimeout: TimeInterval
    /// Most `vol` commands per second per track while dragging; the last value is always sent.
    public var maxVolumeMessagesPerSecond: Double
    /// Seconds after a local volume change during which volume echoes from Live are ignored
    /// for that track, so a drag doesn't jitter back to older values.
    public var volumeEchoHold: TimeInterval
    /// Seconds between attempts to bind the listening port after it was in use.
    public var bindRetryInterval: TimeInterval
    /// If Live is sending but no `hello` arrived this long after ``LiveSource/start()``, the script
    /// ignores `sub.app` and still holds an old subscription (the app restarted within 5 s), so it
    /// won't resend its state. The source then pauses `sub` once, see ``resubscribeGap``.
    public var missingStateTimeout: TimeInterval
    /// How long `sub` pauses so the script treats the next one as a new subscription
    /// (the script's rule is 5 s without `sub`).
    public var resubscribeGap: TimeInterval

    public init(
        listenPort: UInt16 = WireProtocol.appPort,
        scriptPort: UInt16 = WireProtocol.scriptPort,
        meterRate: Int = WireProtocol.defaultMeterRate,
        subscribeInterval: TimeInterval = 1,
        watchResendEvery: Int = 5,
        silenceTimeout: TimeInterval = 3,
        trackListTimeout: TimeInterval = 1,
        maxVolumeMessagesPerSecond: Double = 30,
        volumeEchoHold: TimeInterval = 0.4,
        bindRetryInterval: TimeInterval = 2,
        missingStateTimeout: TimeInterval = 2,
        resubscribeGap: TimeInterval = 6
    ) {
        self.listenPort = listenPort
        self.scriptPort = scriptPort
        self.meterRate = meterRate
        self.subscribeInterval = subscribeInterval
        self.watchResendEvery = max(watchResendEvery, 1)
        self.silenceTimeout = silenceTimeout
        self.trackListTimeout = trackListTimeout
        self.maxVolumeMessagesPerSecond = maxVolumeMessagesPerSecond
        self.volumeEchoHold = volumeEchoHold
        self.bindRetryInterval = bindRetryInterval
        self.missingStateTimeout = missingStateTimeout
        self.resubscribeGap = resubscribeGap
    }

    /// The protocol defaults: listen on 47800, send to 47801, 30 Hz, `sub` every second,
    /// disconnected after 3 s of silence.
    public static let standard = LiveSourceConfiguration()

    /// How often the source checks keep-alive, silence and timeouts.
    var housekeepingInterval: TimeInterval {
        max(0.01, min(subscribeInterval, silenceTimeout / 3, trackListTimeout / 2, 0.25))
    }
}
