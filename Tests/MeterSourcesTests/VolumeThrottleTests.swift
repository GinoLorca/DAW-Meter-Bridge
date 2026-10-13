import MeterCore
@testable import MeterSources
import Testing

@Suite("Volume throttle")
struct VolumeThrottleTests {
    let a = TrackID(1)
    let b = TrackID(2)

    @Test func firstValueGoesOutAtOnce() {
        var throttle = VolumeThrottle(maxPerSecond: 30)
        #expect(throttle.submit(0.5, for: a, at: 10) == .sendNow)
    }

    @Test func fastValuesAreHeldAndTheLastOneWins() {
        var throttle = VolumeThrottle(maxPerSecond: 30)
        #expect(throttle.submit(0.5, for: a, at: 10) == .sendNow)
        #expect(throttle.submit(0.6, for: a, at: 10.01) == .flushAt(10 + 1.0 / 30))
        #expect(throttle.submit(0.7, for: a, at: 10.02) == .coalesced)
        #expect(throttle.flush(a, at: 10.034) == 0.7)
        #expect(throttle.flush(a, at: 10.04) == nil)
        // The flush counts as a send for the next interval.
        #expect(throttle.submit(0.8, for: a, at: 10.05) == .flushAt(10.034 + 1.0 / 30))
        #expect(throttle.submit(0.9, for: a, at: 10.2) == .coalesced)
        #expect(throttle.flush(a, at: 10.2) == 0.9)
        #expect(throttle.submit(1.0, for: a, at: 10.3) == .sendNow)
    }

    @Test func tracksAreThrottledIndependently() {
        var throttle = VolumeThrottle(maxPerSecond: 30)
        #expect(throttle.submit(0.5, for: a, at: 0) == .sendNow)
        #expect(throttle.submit(0.5, for: b, at: 0.001) == .sendNow)
    }

    @Test func zeroRateMeansUnthrottled() {
        var throttle = VolumeThrottle(maxPerSecond: 0)
        #expect(throttle.submit(0.5, for: a, at: 0) == .sendNow)
        #expect(throttle.submit(0.6, for: a, at: 0) == .sendNow)
    }
}
