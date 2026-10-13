import Foundation
import MeterCore
@testable import MeterRendering
import Testing

/// Colour thresholds, segment lighting and persistence of `MeterStyle`.
@Suite struct MeterStyleTests {
    @Test(arguments: [
        (Float(0), MeterZone.normal),
        (0.5, .normal),
        (0.7999, .normal),
        (0.80, .warning),
        (0.85, .warning),
        (0.9199, .warning),
        (0.92, .over),
        (1.0, .over),
    ])
    func defaultThresholds(value: Float, zone: MeterZone) {
        #expect(MeterStyle.standard.zone(for: value) == zone)
    }

    @Test func customThresholds() {
        var style = MeterStyle()
        style.yellowThreshold = 0.5
        style.redThreshold = 0.6
        #expect(style.zone(for: 0.49) == .normal)
        #expect(style.zone(for: 0.5) == .warning)
        #expect(style.zone(for: 0.6) == .over)
    }

    @Test func defaultSegmentZonesAre32Green5Yellow3Red() {
        let style = MeterStyle.standard
        let zones = (0..<40).map { style.zone(ofSegment: $0) }
        #expect(zones.filter { $0 == .normal }.count == 32)
        #expect(zones.filter { $0 == .warning }.count == 5)
        #expect(zones.filter { $0 == .over }.count == 3)
        #expect(zones.first == .normal && zones.last == .over)
    }

    @Test(arguments: [
        (Float(0), 0),
        (0.012, 0),
        (0.013, 1),
        (0.5, 20),
        (0.8, 32),
        (0.99, 40),
        (1.0, 40),
        (1.5, 40),
        (-0.2, 0),
        (Float.nan, 0),
    ])
    func litSegments(level: Float, lit: Int) {
        #expect(MeterStyle.standard.litSegments(for: level) == lit)
    }

    @Test func segmentCountAndGapAreClamped() {
        var style = MeterStyle()
        style.segmentCount = 0
        style.segmentGap = 3
        #expect(style.effectiveSegmentCount == 1)
        #expect(style.effectiveSegmentGap == 0.8)
        style.segmentCount = 10_000
        #expect(style.effectiveSegmentCount == 200)
    }

    @Test func codableRoundTrip() throws {
        var style = MeterStyle()
        style.segmentCount = 24
        style.showButtons = false
        style.backgroundColor = MeterCore.RGBColor(hex: 0x101010)
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(MeterStyle.self, from: data) == style)
    }

    @Test func decodingFillsMissingFieldsWithDefaults() throws {
        let json = Data(#"{"segmentCount": 30, "showNames": false}"#.utf8)
        let style = try JSONDecoder().decode(MeterStyle.self, from: json)
        #expect(style.segmentCount == 30)
        #expect(style.showNames == false)
        #expect(style.yellowThreshold == 0.80)
        #expect(style.redThreshold == 0.92)
        #expect(style.backgroundColor == MeterCore.RGBColor(hex: 0))
    }

    @Test func readoutText() {
        let uncalibrated = MeterCalibration.uncalibrated
        #expect(BankView.readoutText(for: 0, calibration: uncalibrated) == "-∞")
        #expect(BankView.readoutText(for: 1, calibration: uncalibrated) == "≈0.0")
        #expect(BankView.readoutText(for: 0.5, calibration: uncalibrated) == "≈-6.0")
        let measured = MeterCalibration(points: [.init(value: 0, decibels: -70), .init(value: 1, decibels: 6)], isMeasured: true)
        #expect(BankView.readoutText(for: 0.5, calibration: measured) == "-32.0")
    }

    @Test func textColourFollowsLuminance() {
        #expect(MeterCore.RGBColor(hex: 0xFFFFFF).prefersDarkText)
        #expect(MeterCore.RGBColor(hex: 0xF7F47C).prefersDarkText)
        #expect(!MeterCore.RGBColor(hex: 0x000000).prefersDarkText)
        #expect(!MeterCore.RGBColor(hex: 0x1F3A93).prefersDarkText)
    }

    @Test func buttonsFollowTrackKind() {
        let audio = StripRenderState(trackID: TrackID(1), kind: .audio)
        #expect(audio.allows(.solo) && audio.allows(.mute) && audio.allows(.arm))
        let group = StripRenderState(trackID: TrackID(2), kind: .group)
        #expect(group.allows(.solo) && group.allows(.mute) && !group.allows(.arm))
        let main = StripRenderState(trackID: TrackID(3), kind: .main)
        #expect(!main.allows(.solo) && !main.allows(.mute) && !main.allows(.arm))
        #expect(!StripRenderState.empty.allows(.solo))
        #expect(StripRenderState.empty.isEmpty)
    }

    @Test func stateFromTrackInfo() {
        let track = TrackInfo(id: TrackID(7), index: 0, name: "Bus", color: MeterCore.RGBColor(hex: 0x10A4EE), kind: .returnTrack,
                              isArmed: nil, volume: 0.5, volumeText: "-12.0 dB")
        let state = StripRenderState(track: track, meter: .silent, focus: .none)
        #expect(state.trackID == TrackID(7))
        #expect(!state.isEmpty)
        #expect(state.name == "Bus" && state.volume == 0.5 && state.volumeText == "-12.0 dB")
        #expect(state.canSolo && state.canMute && !state.canArm)
    }
}
