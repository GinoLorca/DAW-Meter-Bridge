import MeterCore
import Testing

/// `VolumeCurve.liveApproximation`: Live's fader with 0.85 = 0 dB and 1.0 = +6 dB.
@Suite struct LiveVolumeApproximationTests {
    private let live = VolumeCurve.liveApproximation

    @Test func hasTheProtocolShape() {
        // PROTOCOL.md `vc`: 101 samples at x = k/100, -inf at 0.
        #expect(live.samples.count == 101)
        for (k, sample) in live.samples.enumerated() {
            #expect(isClose(sample.normalized, Double(k) / 100), "k = \(k)")
        }
        #expect(live.samples[0].decibels == nil)
        #expect(live.samples.dropFirst().allSatisfy { $0.decibels != nil })
    }

    @Test func rebuildsFromProtocolArrays() {
        let rebuilt = VolumeCurve(
            normalized: (0...100).map { Double($0) / 100 },
            decibels: live.samples.map(\.decibels)
        )
        #expect(rebuilt == live)
    }

    @Test func unityIsZeroDecibels() {
        #expect(isSameDecibels(live.decibels(atNormalized: 0.85), 0))
        #expect(live.text(atNormalized: 0.85) == "0.0 dB")
    }

    @Test func topIsPlusSixDecibels() {
        #expect(isSameDecibels(live.decibels(atNormalized: 1.0), 6))
        #expect(live.text(atNormalized: 1.0) == "6.0 dB")
    }

    @Test func bottomIsMinusInfinity() {
        #expect(live.decibels(atNormalized: 0) == nil)
        #expect(live.decibels(atNormalized: 0.005) == nil)
        #expect(live.text(atNormalized: 0) == "-inf dB")
    }

    @Test func linearAndLogSegmentsMeetAtMinusEighteen() {
        #expect(isSameDecibels(live.decibels(atNormalized: 0.4), -18))
        #expect(isSameDecibels(live.decibels(atNormalized: 0.7), -6))
        #expect(live.text(atNormalized: 0.7) == "-6.0 dB")
        #expect(live.text(atNormalized: 0.4) == "-18.0 dB")
    }

    @Test func lowestFiniteSampleIsAboutMinusSeventy() throws {
        let db = try #require(live.decibels(atNormalized: 0.01))
        #expect(db > -75 && db < -65)
    }

    @Test func sampledDecibelsRiseStrictly() throws {
        let finite = live.samples.compactMap(\.decibels)
        #expect(finite.count == 100)
        for (lower, upper) in zip(finite, finite.dropFirst()) {
            #expect(upper > lower)
        }
    }

    @Test func interpolatedDecibelsNeverFall() {
        var previous: Double? = nil
        var sawFinite = false
        for step in 0...1000 {
            let x = Double(step) / 1000
            let db = live.decibels(atNormalized: x)
            if let db {
                if let previous { #expect(db >= previous, "x = \(x)") }
                sawFinite = true
            } else {
                #expect(!sawFinite, "-inf after a finite value at x = \(x)")
            }
            previous = db
        }
    }

    @Test(arguments: [(0.0, 0.85), (6.0, 1.0), (-6.0, 0.7), (-18.0, 0.4), (12.0, 1.0)])
    func normalizedForKnownDecibels(decibels: Double, normalized: Double) {
        #expect(isClose(live.normalized(atDecibels: decibels), normalized))
    }

    @Test func minusInfinityIsTheBottomOfTheFader() {
        #expect(live.normalized(atDecibels: nil) == 0)
    }

    @Test func normalizedIsTheInverseOfDecibels() throws {
        for step in 2...200 {
            let x = Double(step) / 200
            let db = try #require(live.decibels(atNormalized: x))
            #expect(isClose(live.normalized(atDecibels: db), x), "x = \(x)")
        }
    }

    /// Just below unity the interpolated dB is a tiny negative number. It should read "0.0 dB"
    /// (as `MeterCalibration.readout` does for meters), never the printf artefact "-0.0 dB".
    @Test(arguments: [0.8495, 0.8499, 0.84999])
    func neverShowsNegativeZero(normalized: Double) {
        #expect(live.text(atNormalized: normalized) == "0.0 dB")
    }

    @Test func trackInfoDefaultsAgreeWithTheCurve() {
        let track = TrackInfo(id: TrackID(1), index: 0, name: "Default")
        #expect(live.text(atNormalized: track.volume) == track.volumeText)
    }
}
