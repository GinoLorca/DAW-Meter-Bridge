import MeterCore
import Testing

/// -inf at 0, then three finite breakpoints. Values in the tests are worked out by hand from these.
private let curve = VolumeCurve(samples: [
    .init(normalized: 0, decibels: nil),
    .init(normalized: 0.25, decibels: -30),
    .init(normalized: 0.5, decibels: -12),
    .init(normalized: 1.0, decibels: 6),
])!

/// A curve whose lowest sample is finite and above 0.
private let finiteCurve = VolumeCurve(samples: [
    .init(normalized: 0.2, decibels: -20),
    .init(normalized: 1.0, decibels: 0),
])!

/// Construction rules of `VolumeCurve`.
@Suite struct VolumeCurveInitTests {
    @Test(arguments: [
        [VolumeCurve.Sample](),
        [.init(normalized: 0.5, decibels: -6)],
        [.init(normalized: 0, decibels: nil), .init(normalized: 1, decibels: 0)],
        [.init(normalized: 0, decibels: nil), .init(normalized: 0.5, decibels: nil), .init(normalized: 1, decibels: 6)],
    ])
    func rejectsFewerThanTwoFiniteSamples(samples: [VolumeCurve.Sample]) {
        #expect(VolumeCurve(samples: samples) == nil)
    }

    @Test func acceptsExactlyTwoFiniteSamples() throws {
        let twoPoint = try #require(VolumeCurve(samples: [
            .init(normalized: 0, decibels: -10),
            .init(normalized: 1, decibels: 0),
        ]))
        #expect(twoPoint.samples.count == 2)
    }

    @Test func acceptsInfiniteSamplesAlongsideTwoFiniteOnes() {
        #expect(curve.samples.count == 4)
        #expect(curve.samples.first?.decibels == nil)
    }

    @Test func sortsSamplesByNormalizedValue() throws {
        let shuffled = try #require(VolumeCurve(samples: [
            .init(normalized: 1.0, decibels: 6),
            .init(normalized: 0, decibels: nil),
            .init(normalized: 0.5, decibels: -12),
            .init(normalized: 0.25, decibels: -30),
        ]))
        #expect(shuffled.samples.map(\.normalized) == [0, 0.25, 0.5, 1.0])
        #expect(shuffled == curve)
    }

    @Test func buildsFromProtocolParallelArrays() throws {
        let fromArrays = try #require(VolumeCurve(normalized: [0, 0.25, 0.5, 1.0], decibels: [nil, -30, -12, 6]))
        #expect(fromArrays == curve)
    }

    @Test func rejectsParallelArraysOfDifferentLengths() {
        #expect(VolumeCurve(normalized: [0, 0.5, 1.0], decibels: [nil, -12]) == nil)
        #expect(VolumeCurve(normalized: [0.5, 1.0], decibels: [-12, 6, 7]) == nil)
    }

    @Test func rejectsParallelArraysWithTooFewFiniteValues() {
        #expect(VolumeCurve(normalized: [0, 1], decibels: [nil, 0]) == nil)
    }
}

/// Normalized -> dB.
@Suite struct VolumeCurveDecibelsTests {
    @Test(arguments: [(0.25, -30.0), (0.5, -12.0), (1.0, 6.0)])
    func exactSamplesReturnTheirValue(normalized: Double, decibels: Double) {
        #expect(curve.decibels(atNormalized: normalized) == decibels)
    }

    @Test(arguments: [(0.375, -21.0), (0.3, -26.4), (0.75, -3.0), (0.875, 1.5)])
    func interpolatesLinearlyBetweenSamples(normalized: Double, decibels: Double) {
        #expect(isSameDecibels(curve.decibels(atNormalized: normalized), decibels))
    }

    @Test(arguments: [0.0, 0.1, 0.2499])
    func reportsMinusInfinityBelowFirstFiniteSample(normalized: Double) {
        #expect(curve.decibels(atNormalized: normalized) == nil)
    }

    @Test func clampsOutOfRangeInput() {
        #expect(curve.decibels(atNormalized: -0.5) == nil)
        #expect(curve.decibels(atNormalized: 1.5) == 6)
        #expect(finiteCurve.decibels(atNormalized: 0) == -20)
        #expect(finiteCurve.decibels(atNormalized: 0.1) == -20)
        #expect(finiteCurve.decibels(atNormalized: 2) == 0)
    }
}

/// dB -> normalized, and the round trip both ways.
@Suite struct VolumeCurveNormalizedTests {
    @Test(arguments: [(-30.0, 0.25), (-21.0, 0.375), (-12.0, 0.5), (-3.0, 0.75), (6.0, 1.0)])
    func interpolatesLinearly(decibels: Double, normalized: Double) {
        #expect(isClose(curve.normalized(atDecibels: decibels), normalized))
    }

    @Test func minusInfinityMapsToLowestSample() {
        #expect(curve.normalized(atDecibels: nil) == 0)
        #expect(finiteCurve.normalized(atDecibels: nil) == 0.2)
    }

    @Test func clampsAboveTheTable() {
        #expect(curve.normalized(atDecibels: 12) == 1.0)
        #expect(finiteCurve.normalized(atDecibels: 10) == 1.0)
    }

    @Test func staysAtTheBottomBelowTheTable() {
        let veryQuiet = curve.normalized(atDecibels: -200)
        #expect(veryQuiet >= 0 && veryQuiet <= 0.25)
        #expect(finiteCurve.normalized(atDecibels: -50) == 0.2)
    }

    @Test func isTheInverseOfDecibels() throws {
        for step in 25...100 {
            let x = Double(step) / 100
            let db = try #require(curve.decibels(atNormalized: x))
            #expect(isClose(curve.normalized(atDecibels: db), x), "x = \(x)")
        }
    }

    @Test func decibelsIsTheInverseOfNormalized() {
        for halfDB in -60...12 {
            let db = Double(halfDB) / 2
            #expect(isSameDecibels(curve.decibels(atNormalized: curve.normalized(atDecibels: db)), db), "dB = \(db)")
        }
    }
}

/// Display text.
@Suite struct VolumeCurveTextTests {
    @Test(arguments: [
        (0.75, "-3.0 dB"),
        (0.5, "-12.0 dB"),
        (0.3, "-26.4 dB"),
        (1.0, "6.0 dB"),
        (0.875, "1.5 dB"),
        (0.0, "-inf dB"),
        (0.1, "-inf dB"),
    ])
    func formatsOneDecimalOrMinusInfinity(normalized: Double, text: String) {
        #expect(curve.text(atNormalized: normalized) == text)
    }
}
