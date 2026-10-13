import BridgeLayout
import CoreGraphics
import Foundation
import Testing

@Suite struct CalibrationTests {
    let group = StripGroup(
        name: "UF8",
        binding: .surfaceUnit(index: 0, firstStrip: 0),
        stripCount: 8,
        frame: CGRect(x: 0, y: 12, width: 800, height: 140),
        physicalPitchMillimeters: 38.5
    )

    @Test func twoPointCalibrationGivesExactPitchAndEdges() throws {
        let first: CGFloat = 200.25
        let pitch: CGFloat = 166.3
        let last = first + 7 * pitch
        let calibrated = try #require(group.calibrated(firstCenterX: first, lastCenterX: last))
        #expect(approx(calibrated.stripWidth, pitch, 1e-9))
        #expect(approx(calibrated.frame.minX, first - pitch / 2, 1e-9))
        #expect(approx(calibrated.frame.width, 8 * pitch, 1e-9))
        #expect(approx(calibrated.stripCenterX(at: 0), first, 1e-9))
        #expect(approx(calibrated.stripCenterX(at: 7), last, 1e-9))
        // Vertical extent and identity are untouched.
        #expect(calibrated.frame.minY == 12 && calibrated.frame.height == 140)
        #expect(calibrated.id == group.id)
        // The calibrated pitch measures the display: 166.3 pt per 38.5 mm.
        #expect(calibrated.measuredPointsPerMillimeter.map { approx($0, 166.3 / 38.5) } == true)
    }

    @Test func reversedOrCoincidentMarkersAreRejected() {
        #expect(group.calibrated(firstCenterX: 900, lastCenterX: 100) == nil)
        #expect(group.calibrated(firstCenterX: 100, lastCenterX: 100) == nil)
        #expect(group.calibrated(firstCenterX: 100, lastCenterX: 100 + 7 * 1.5) == nil)
        #expect(group.calibrated(firstCenterX: 100, lastCenterX: 100 + 7 * StripCalibration.minimumPitch) != nil)
    }

    @Test func singleStripIsCentredBetweenTheMarkers() throws {
        let uf1 = StripGroup(name: "UF1", binding: .selectedTrack, stripCount: 1, frame: CGRect(x: 0, y: 0, width: 160, height: 100))
        let calibrated = try #require(uf1.calibrated(firstCenterX: 2000, lastCenterX: 2010))
        #expect(calibrated.frame == CGRect(x: 1925, y: 0, width: 160, height: 100))
    }

    @Test func twoPointFitSolvesScaleAndOrigin() throws {
        // Markers over UF8 fader 1 (84.3 mm) and fader 8 (353.8 mm) at 5 pt/mm, hardware edge at x = 78.5.
        let fit = try #require(TwoPointFit(firstMillimeters: 84.3, firstX: 500, secondMillimeters: 353.8, secondX: 500 + 269.5 * 5))
        #expect(approx(fit.pointsPerMillimeter, 5, 1e-9))
        #expect(approx(fit.originX, 500 - 84.3 * 5, 1e-9))
        #expect(approx(fit.x(atMillimeters: 431), fit.originX + 2155, 1e-9))

        #expect(TwoPointFit(firstMillimeters: 10, firstX: 0, secondMillimeters: 10, secondX: 50) == nil)
        #expect(TwoPointFit(firstMillimeters: 10, firstX: 50, secondMillimeters: 20, secondX: 0) == nil)
    }

    @Test func wholeTemplateCalibrationRefitsEveryWingGroup() throws {
        // Start from a guess, then calibrate on L1 and R4 and refit the six groups in place.
        let guess = TemplatePlacement(displaySize: CGSize(width: 1920, height: 540), pointsPerMillimeter: 2.0, hardwareLeftX: 0, meterY: 40, meterHeight: 400)
        let groups = TemplateBuilder.groups(for: .wingMCUPlus2Extenders, placement: guess)
        let l1 = SurfaceTemplate.wingFaderCentersMillimeters["L1"]!
        let r4 = SurfaceTemplate.wingFaderCentersMillimeters["R4"]!
        let fit = try #require(TwoPointFit(firstMillimeters: l1, firstX: 130, secondMillimeters: r4, secondX: 1790))
        let refitted = TemplateBuilder.refit(groups, to: .wingMCUPlus2Extenders, placement: guess.calibrated(with: fit))

        #expect(refitted.map(\.id) == groups.map(\.id))
        #expect(approx(refitted[0].stripCenterX(at: 0), 130, 1e-9))
        #expect(approx(refitted[5].stripCenterX(at: 3), 1790, 1e-9))
        #expect(refitted.allSatisfy { $0.frame.minY == 40 && $0.frame.height == 400 })
    }

    @Test func refitLeavesUnknownGroupsAlone() {
        let custom = StripGroup(name: "Mine", binding: .trackList(offset: 0), stripCount: 2, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let placement = TemplatePlacement(displaySize: CGSize(width: 100, height: 100), pointsPerMillimeter: 1, hardwareLeftX: 0, meterY: 0, meterHeight: 10)
        #expect(TemplateBuilder.refit([custom], to: .sslUF8, placement: placement) == [custom])
    }

    @Test func calibratedPlacementRebuildsUF8OnTheMarkers() throws {
        let start = TemplatePlacement(displaySize: CGSize(width: 1920, height: 515), pointsPerMillimeter: 6, hardwareLeftX: 0, meterY: 0, meterHeight: 515)
        let fit = try #require(TwoPointFit(firstMillimeters: 84.3, firstX: 120, secondMillimeters: 84.3 + 7 * 38.5, secondX: 1800))
        let group = try #require(TemplateBuilder.groups(for: .sslUF8, placement: start.calibrated(with: fit)).first)
        #expect(approx(group.stripCenterX(at: 0), 120, 1e-9))
        #expect(approx(group.stripCenterX(at: 7), 1800, 1e-9))
    }
}
