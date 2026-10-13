import Foundation
import MeterCore
import Testing

/// Settings types are persisted as JSON, so they must survive a round trip unchanged.
@Suite struct SettingsCodingTests {
    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test func ballisticsSettingsRoundTrip() throws {
        let custom = BallisticsSettings(barFallPerSecond: 2.25, peakHoldSeconds: 3, peakFallPerSecond: 0.5, silenceFloor: 0.001)
        #expect(try roundTrip(custom) == custom)
        #expect(try roundTrip(BallisticsSettings.standard) == .standard)
    }

    @Test func mixFocusSettingsRoundTrip() throws {
        let custom = MixFocusSettings(soloDim: 0.4, muteDim: 0.7)
        #expect(try roundTrip(custom) == custom)
        #expect(try roundTrip(MixFocusSettings.standard) == .standard)
    }

    @Test func meterCalibrationRoundTrip() throws {
        let calibration = MeterCalibration(
            points: [.init(value: 0.1, decibels: -40), .init(value: 0.5, decibels: -12), .init(value: 1, decibels: 0)],
            clipValue: 0.98,
            isMeasured: true
        )
        let decoded = try roundTrip(calibration)
        #expect(decoded == calibration)
        #expect(decoded.readout(for: 0.3) == calibration.readout(for: 0.3))
        #expect(try roundTrip(MeterCalibration.uncalibrated) == .uncalibrated)
    }
}
