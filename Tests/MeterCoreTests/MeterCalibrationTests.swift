import Foundation
import MeterCore
import Testing

/// A measured table, given out of order on purpose.
private let measured = MeterCalibration(
    points: [
        .init(value: 1.0, decibels: 0),
        .init(value: 0.1, decibels: -40),
        .init(value: 0.5, decibels: -12),
    ],
    isMeasured: true
)

/// Meter value -> dBFS.
@Suite struct MeterCalibrationDecibelsTests {
    @Test func uncalibratedHasNoTableAndIsNotMeasured() {
        let calibration = MeterCalibration.uncalibrated
        #expect(calibration.points.isEmpty)
        #expect(!calibration.isMeasured)
        #expect(calibration.clipValue == 0.999)
    }

    @Test(arguments: [
        (Float(1.0), Float(0)),
        (0.5, -6.0206),
        (0.1, -20),
        (0.01, -40),
        (0.0001, -80),
    ])
    func uncalibratedIsTwentyLogTen(value: Float, decibels: Float) {
        #expect(isSameDecibels(MeterCalibration.uncalibrated.decibels(for: value), decibels, within: 1e-3))
    }

    @Test(arguments: [Float(0), 0.000_01, -0.5])
    func silenceIsMinusInfinity(value: Float) {
        #expect(MeterCalibration.uncalibrated.decibels(for: value) == nil)
        #expect(measured.decibels(for: value) == nil)
    }

    @Test func initializerSortsPointsByValue() {
        #expect(measured.points.map(\.value) == [0.1, 0.5, 1.0])
        #expect(measured.points.map(\.decibels) == [-40, -12, 0])
    }

    @Test(arguments: [(Float(0.1), Float(-40)), (0.5, -12), (1.0, 0)])
    func tablePointsReturnTheirValue(value: Float, decibels: Float) {
        #expect(isSameDecibels(measured.decibels(for: value), decibels))
    }

    @Test(arguments: [(Float(0.3), Float(-26)), (0.75, -6), (0.2, -33)])
    func tableInterpolatesLinearly(value: Float, decibels: Float) {
        #expect(isSameDecibels(measured.decibels(for: value), decibels))
    }

    @Test func tableClampsBelowFirstAndAboveLastPoint() {
        #expect(measured.decibels(for: 0.05) == -40)
        #expect(measured.decibels(for: 0.0001) == -40)
        #expect(measured.decibels(for: 1.0) == 0)
        #expect(measured.decibels(for: 1.2) == 0)
    }

    @Test func emptyTableIsLinearAmplitude() {
        let empty = MeterCalibration(points: [], isMeasured: true)
        #expect(isSameDecibels(empty.decibels(for: 0.5), -6.0206, within: 1e-3))
    }

    @Test func decodingSortsPointsByValue() throws {
        let json = """
        {"points":[{"value":1,"decibels":0},{"value":0.1,"decibels":-40},{"value":0.5,"decibels":-12}],
         "clipValue":0.95,"isMeasured":true}
        """
        let decoded = try JSONDecoder().decode(MeterCalibration.self, from: Data(json.utf8))
        #expect(decoded.points.map(\.value) == [0.1, 0.5, 1.0])
        #expect(decoded.clipValue == 0.95)
        #expect(decoded.isMeasured)
        #expect(isSameDecibels(decoded.decibels(for: 0.3), -26))
    }

    @Test func decodingRoundTripsAndFillsMissingKeysWithDefaults() throws {
        let data = try JSONEncoder().encode(measured)
        #expect(try JSONDecoder().decode(MeterCalibration.self, from: data) == measured)
        let empty = try JSONDecoder().decode(MeterCalibration.self, from: Data("{}".utf8))
        #expect(empty == .uncalibrated)
    }

    @Test func clipValueIsKept() {
        #expect(MeterCalibration(clipValue: 0.9).clipValue == 0.9)
    }
}

/// Numeric readout strings.
@Suite struct MeterCalibrationReadoutTests {
    @Test(arguments: [
        (Float(0.5), "≈-6.0"),
        (0.1, "≈-20.0"),
        (0.0001, "≈-80.0"),
        (1.0, "≈0.0"),
    ])
    func uncalibratedReadoutIsPrefixedWithApproximately(value: Float, text: String) {
        #expect(MeterCalibration.uncalibrated.readout(for: value) == text)
    }

    @Test(arguments: [(Float(0.3), "-26.0"), (0.75, "-6.0"), (0.05, "-40.0"), (1.0, "0.0")])
    func measuredReadoutHasNoPrefix(value: Float, text: String) {
        #expect(measured.readout(for: value) == text)
    }

    @Test func unmeasuredTableIsStillApproximate() {
        let estimated = MeterCalibration(points: measured.points, isMeasured: false)
        #expect(estimated.readout(for: 0.3) == "≈-26.0")
    }

    @Test(arguments: [Float(0), 0.000_01])
    func silenceReadsMinusInfinity(value: Float) {
        // -inf is exact whatever the calibration, so it carries no "≈".
        #expect(MeterCalibration.uncalibrated.readout(for: value) == "-inf")
        #expect(measured.readout(for: value) == "-inf")
    }

    @Test(arguments: [Float(0.9999), 0.999, 0.997])
    func justBelowFullScaleReadsZeroNotNegativeZero(value: Float) {
        #expect(MeterCalibration.uncalibrated.readout(for: value) == "≈0.0")
        let nearZero = MeterCalibration(
            points: [.init(value: 0, decibels: -6), .init(value: 1, decibels: 0)],
            isMeasured: true
        )
        #expect(nearZero.readout(for: value) == "0.0")
    }
}
