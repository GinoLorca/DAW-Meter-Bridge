import Testing
@testable import MeterCore

/// Live 12.4.6 track-meter readings for a 997 Hz sine at known peak levels, captured 2026-10-13 with
/// AbletonRemoteScript/tools/capture_meters.py (docs/research/05-live-meter-calibration.md).
private let measuredLive12: [(decibels: Float, value: Float)] = [
    (0, 0.9211), (-1, 0.9079), (-2, 0.8947), (-3, 0.8816), (-4.5, 0.8618), (-6, 0.8421),
    (-9, 0.8026), (-12, 0.7632), (-15, 0.7237), (-18, 0.6842), (-21, 0.6447), (-24, 0.6053),
    (-30, 0.5263), (-36, 0.4474), (-42, 0.3684), (-48, 0.2895), (-54, 0.2105), (-60, 0.1316),
]

@Suite("Ableton Live 12 meter calibration")
struct LiveMeterCalibrationTests {
    @Test("Readouts match every measured step within 0.05 dB", arguments: measuredLive12)
    func readoutsMatchMeasurement(step: (decibels: Float, value: Float)) {
        let decibels = MeterCalibration.ableton12.decibels(for: step.value)
        #expect(decibels != nil)
        #expect(abs((decibels ?? .nan) - step.decibels) < 0.05)
    }

    @Test func readoutTextHasNoApproximationMark() {
        #expect(MeterCalibration.ableton12.readout(for: 0.8421) == "-6.0")
        #expect(MeterCalibration.ableton12.readout(for: 0.9211) == "0.0")
        #expect(MeterCalibration.ableton12.readout(for: 0) == "-inf")
    }

    @Test func meterFloorReadsSilence() {
        // The -70 dB step read exactly 0 in Live: the floor of its meter.
        #expect(MeterCalibration.ableton12.decibels(for: 0) == nil)
    }

    @Test func clipLatchesOnlyAboveZeroDBFS() {
        let calibration = MeterCalibration.ableton12
        let settings = BallisticsSettings.standard
        var fullScale = ChannelBallistics()
        fullScale.ingest(0.9211, at: 0, clipValue: calibration.clipValue, settings: settings)
        #expect(!fullScale.clipped)
        var over = ChannelBallistics()
        over.ingest(0.9212, at: 0, clipValue: calibration.clipValue, settings: settings)
        #expect(over.clipped)
    }

    @Test func calibrationIsChosenByLiveMajorVersion() {
        #expect(MeterCalibration.ableton(version: "12.4.6") == .ableton12)
        #expect(MeterCalibration.ableton(version: "12") == .ableton12)
        #expect(MeterCalibration.ableton(version: "11.3.42") == nil)
        #expect(MeterCalibration.ableton(version: "13.0") == nil)
        #expect(MeterCalibration.ableton(version: nil) == nil)
        #expect(MeterCalibration.ableton(version: "") == nil)
        #expect(MeterCalibration.ableton(version: "beta") == nil)
    }

    @Test func liveMeterValueInvertsTheCalibration() {
        #expect(MeterCalibration.liveMeterValue(decibels: nil) == 0)
        #expect(MeterCalibration.liveMeterValue(decibels: -.infinity) == 0)
        #expect(MeterCalibration.liveMeterValue(decibels: -80) == 0)
        #expect(MeterCalibration.liveMeterValue(decibels: 12) == 1)
        for step in measuredLive12 {
            let value = MeterCalibration.liveMeterValue(decibels: Double(step.decibels))
            #expect(abs(value - Double(step.value)) < 0.0001)
        }
    }
}
