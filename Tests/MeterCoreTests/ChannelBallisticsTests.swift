import Foundation
import MeterCore
import Testing

/// Standard settings: bar falls 1.5/s, peak holds 1.5 s then falls 0.4/s, silence floor 0.0005.
private let settings = BallisticsSettings.standard
private let clipValue = MeterCalibration.uncalibrated.clipValue

private extension ChannelBallistics {
    mutating func ingest(_ value: Float, at time: TimeInterval) {
        ingest(value, at: time, clipValue: clipValue, settings: settings)
    }

    @discardableResult
    mutating func advance(by dt: TimeInterval, to time: TimeInterval) -> Bool {
        advance(by: dt, to: time, settings: settings)
    }
}

/// One meter channel: rise, fall, peak hold, max readout and clip latch.
@Suite struct ChannelBallisticsTests {
    @Test func startsSilent() {
        let channel = ChannelBallistics()
        #expect(channel.target == 0)
        #expect(channel.bar == 0)
        #expect(channel.peak == 0)
        #expect(channel.maxSinceReset == 0)
        #expect(!channel.clipped)
    }

    @Test func risesInstantly() {
        var channel = ChannelBallistics()
        channel.ingest(0.7, at: 0)
        #expect(channel.target == 0.7)
        #expect(channel.bar == 0.7)
        #expect(channel.peak == 0.7)
        #expect(channel.maxSinceReset == 0.7)
    }

    @Test func clampsReadingsToUnitRange() {
        var channel = ChannelBallistics()
        channel.ingest(1.7, at: 0)
        #expect(channel.target == 1)
        #expect(channel.bar == 1)
        #expect(channel.peak == 1)
        #expect(channel.maxSinceReset == 1)
        channel.ingest(-0.3, at: 0.1)
        #expect(channel.target == 0)
    }

    @Test func lowerReadingDoesNotDropTheBarImmediately() {
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0)
        channel.ingest(0.2, at: 0.03)
        #expect(channel.target == 0.2)
        #expect(channel.bar == 1.0)
        #expect(channel.peak == 1.0)
    }

    @Test func barFallsAtBarFallRate() {
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0)
        channel.ingest(0.0, at: 0)
        channel.advance(by: 0.1, to: 0.1)
        #expect(isClose(channel.bar, 0.85))
        channel.advance(by: 0.1, to: 0.2)
        #expect(isClose(channel.bar, 0.70))
    }

    @Test func barFallRateComesFromSettings() {
        let fast = BallisticsSettings(barFallPerSecond: 3)
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0, clipValue: clipValue, settings: fast)
        channel.ingest(0.0, at: 0, clipValue: clipValue, settings: fast)
        _ = channel.advance(by: 0.1, to: 0.1, settings: fast)
        #expect(isClose(channel.bar, 0.7))
    }

    @Test func barNeverFallsBelowTarget() {
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0)
        channel.ingest(0.6, at: 0)
        channel.advance(by: 1.0, to: 1.0)
        #expect(channel.bar == 0.6)
        channel.advance(by: 1.0, to: 2.0)
        #expect(channel.bar == 0.6)
    }

    @Test func negativeTimeStepMovesNothing() {
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0)
        channel.ingest(0.0, at: 0)
        channel.advance(by: -0.5, to: 0)
        #expect(channel.bar == 1.0)
        #expect(channel.peak == 1.0)
    }

    @Test func peakHoldsThenFallsAtPeakFallRate() {
        var channel = ChannelBallistics()
        channel.ingest(0.9, at: 100)
        channel.ingest(0.0, at: 100)

        // Inside the 1.5 s hold: the bar has dropped away, the peak line has not moved.
        channel.advance(by: 1.4, to: 101.4)
        #expect(channel.bar == 0)
        #expect(channel.peak == 0.9)

        // Hold over at 101.5: falls 0.4/s.
        channel.advance(by: 0.2, to: 101.6)
        #expect(isClose(channel.peak, 0.82))
        channel.advance(by: 1.0, to: 102.6)
        #expect(isClose(channel.peak, 0.42))

        // ...down to the bar, not below.
        channel.advance(by: 2.0, to: 104.6)
        #expect(channel.peak == 0)
    }

    @Test func peakNeverFallsBelowBar() {
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0)
        channel.ingest(0.6, at: 0)
        channel.advance(by: 1.0, to: 1.0)
        #expect(channel.peak == 1.0)
        channel.advance(by: 0.5, to: 1.5)
        #expect(isClose(channel.peak, 0.8))
        channel.advance(by: 2.0, to: 3.5)
        #expect(channel.peak == 0.6)
        #expect(channel.peak >= channel.bar)
    }

    @Test(arguments: [Float(0.8), 0.9])
    func newPeakAtOrAboveTheLineRestartsTheHold(newPeak: Float) {
        var channel = ChannelBallistics()
        channel.ingest(0.8, at: 0)
        channel.ingest(newPeak, at: 1.0)
        channel.ingest(0.0, at: 1.0)
        // Without the restart the hold would have ended at 1.5.
        channel.advance(by: 1.0, to: 2.0)
        #expect(channel.peak == newPeak)
        // The restarted hold ends at 2.5.
        channel.advance(by: 0.6, to: 2.6)
        #expect(isClose(channel.peak, newPeak - 0.24))
    }

    @Test func lowerReadingDoesNotExtendTheHold() {
        var channel = ChannelBallistics()
        channel.ingest(0.8, at: 0)
        channel.ingest(0.3, at: 1.0)
        channel.advance(by: 0.6, to: 1.6)
        #expect(channel.bar == 0.3)
        #expect(isClose(channel.peak, 0.56))
    }

    @Test func maxSinceResetKeepsTheHighestReading() {
        var channel = ChannelBallistics()
        channel.ingest(0.3, at: 0)
        channel.ingest(0.9, at: 0.1)
        channel.ingest(0.2, at: 0.2)
        #expect(channel.maxSinceReset == 0.9)
        channel.advance(by: 5, to: 5.2)
        #expect(channel.maxSinceReset == 0.9)
    }

    @Test func resetPeaksStartsFromTheCurrentState() {
        var channel = ChannelBallistics()
        channel.ingest(1.0, at: 0)
        channel.ingest(0.2, at: 0)
        channel.advance(by: 0.1, to: 0.1)
        #expect(isClose(channel.bar, 0.85))
        #expect(channel.clipped)

        channel.resetPeaks()
        #expect(channel.peak == channel.bar)
        #expect(channel.peakHoldUntil == 0)
        #expect(channel.maxSinceReset == 0.2)
        #expect(!channel.clipped)
    }

    @Test(arguments: [Float(1.0), 0.999])
    func clipLatchesAtOrAboveClipValue(value: Float) {
        var channel = ChannelBallistics()
        channel.ingest(value, at: 0)
        #expect(channel.clipped)

        channel.ingest(0.1, at: 0.1)
        channel.advance(by: 5, to: 5.1)
        #expect(channel.clipped)

        channel.resetPeaks()
        #expect(!channel.clipped)
    }

    @Test func belowClipValueDoesNotClip() {
        var channel = ChannelBallistics()
        channel.ingest(0.998, at: 0)
        #expect(!channel.clipped)
    }

    @Test func clipValueComesFromTheCaller() {
        var channel = ChannelBallistics()
        channel.ingest(0.92, at: 0, clipValue: 0.9, settings: settings)
        #expect(channel.clipped)
    }

    @Test func advanceReportsActivityUntilSilent() {
        var channel = ChannelBallistics()
        var active = channel.advance(by: 0.1, to: 0.1)
        #expect(!active, "a fresh channel is idle")

        channel.ingest(0.5, at: 0.1)
        active = channel.advance(by: 0.1, to: 0.2)
        #expect(active)
        channel.ingest(0.5, at: 0.2)
        active = channel.advance(by: 0.1, to: 0.3)
        #expect(active, "a steady signal stays active")

        channel.ingest(0.0, at: 0.3)
        // Bar gone after 1/3 s; peak holds to 1.7 s, then 1.25 s of fall.
        active = channel.advance(by: 1.0, to: 1.3)
        #expect(active, "peak still held")
        active = channel.advance(by: 1.0, to: 2.3)
        #expect(active, "peak still falling")
        active = channel.advance(by: 1.0, to: 3.3)
        #expect(!active, "everything has decayed")
        #expect(channel.bar == 0)
        #expect(channel.peak == 0)
    }

    @Test(arguments: [Float(0.0004), 0.0005])
    func readingsAtOrBelowSilenceFloorAreIdle(value: Float) {
        var channel = ChannelBallistics()
        channel.ingest(value, at: 0)
        let active = channel.advance(by: 1 / 60, to: 1 / 60)
        #expect(!active)
    }

    @Test func readingJustAboveSilenceFloorIsActive() {
        var channel = ChannelBallistics()
        channel.ingest(0.0006, at: 0)
        let active = channel.advance(by: 1 / 60, to: 1 / 60)
        #expect(active)
    }
}

@Suite struct StripMeterStateTests {
    @Test func combinesBothChannels() {
        var strip = StripMeterState()
        strip.left.ingest(0.4, at: 0)
        strip.right.ingest(0.7, at: 0)
        #expect(strip.maxSinceReset == 0.7)
        #expect(!strip.clipped)

        strip.left.ingest(1.0, at: 0.1)
        #expect(strip.maxSinceReset == 1.0)
        #expect(strip.clipped)
    }

    @Test func silentIsAllZero() {
        let silent = StripMeterState.silent
        #expect(silent == StripMeterState())
        #expect(silent.left == ChannelBallistics())
        #expect(silent.right == ChannelBallistics())
        #expect(silent.lastUpdate == 0)
        #expect(silent.maxSinceReset == 0)
        #expect(!silent.clipped)
    }
}
