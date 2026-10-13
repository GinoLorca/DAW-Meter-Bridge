import Foundation

/// How displayed meters move between DAW updates. All rates are in normalized meter units per second.
public struct BallisticsSettings: Hashable, Sendable, Codable {
    /// How fast the bar falls toward a lower reading (smooths ~30 Hz input at 60–120 fps).
    public var barFallPerSecond: Float
    /// How long the peak-hold line stays put before falling.
    public var peakHoldSeconds: Double
    /// How fast the peak-hold line falls after the hold.
    public var peakFallPerSecond: Float
    /// Values at or below this count as silence for idle detection.
    public var silenceFloor: Float

    public init(
        barFallPerSecond: Float = 1.5,
        peakHoldSeconds: Double = 1.5,
        peakFallPerSecond: Float = 0.4,
        silenceFloor: Float = 0.0005
    ) {
        self.barFallPerSecond = barFallPerSecond
        self.peakHoldSeconds = peakHoldSeconds
        self.peakFallPerSecond = peakFallPerSecond
        self.silenceFloor = silenceFloor
    }

    public static let standard = BallisticsSettings()
}

/// Display state of one meter channel.
public struct ChannelBallistics: Hashable, Sendable {
    /// Latest reading from the DAW.
    public var target: Float = 0
    /// Displayed bar height (0...1), rises instantly, falls at `barFallPerSecond`.
    public var bar: Float = 0
    /// Peak-hold line (0...1).
    public var peak: Float = 0
    public var peakHoldUntil: TimeInterval = 0
    /// Highest reading since the last reset; drives the numeric readout.
    public var maxSinceReset: Float = 0
    /// Latched until reset.
    public var clipped = false

    public init() {}

    /// Applies a new DAW reading.
    public mutating func ingest(_ value: Float, at time: TimeInterval, clipValue: Float, settings: BallisticsSettings) {
        let v = min(max(value, 0), 1)
        target = v
        if v >= bar { bar = v }
        if v >= peak {
            peak = v
            peakHoldUntil = time + settings.peakHoldSeconds
        }
        maxSinceReset = max(maxSinceReset, v)
        if v >= clipValue { clipped = true }
    }

    /// Moves the bar and peak line forward by `dt` seconds. Returns true while anything is still moving or lit.
    public mutating func advance(by dt: TimeInterval, to time: TimeInterval, settings: BallisticsSettings) -> Bool {
        let step = Float(max(dt, 0))
        if bar > target {
            bar = max(target, bar - settings.barFallPerSecond * step)
        }
        if time >= peakHoldUntil, peak > bar {
            peak = max(bar, peak - settings.peakFallPerSecond * step)
        }
        if peak < bar { peak = bar }
        return bar > settings.silenceFloor || peak > settings.silenceFloor || target > settings.silenceFloor
    }

    public mutating func resetPeaks() {
        peak = bar
        peakHoldUntil = 0
        maxSinceReset = target
        clipped = false
    }
}

/// Display state of one stereo strip.
public struct StripMeterState: Hashable, Sendable {
    public var left = ChannelBallistics()
    public var right = ChannelBallistics()
    /// When the last reading arrived (systemUptime), for stale detection.
    public var lastUpdate: TimeInterval = 0

    public init() {}

    public var maxSinceReset: Float { max(left.maxSinceReset, right.maxSinceReset) }
    public var clipped: Bool { left.clipped || right.clipped }

    public static let silent = StripMeterState()
}
