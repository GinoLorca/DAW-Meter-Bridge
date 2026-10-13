import BridgeLayout
import CoreGraphics
import Foundation
import Testing

@Suite struct TemplateTests {
    @Test func uf8SectionMatchesTheMeasuredDrawing() throws {
        let uf8 = try #require(SurfaceTemplate.sslUF8.sections.first)
        #expect(SurfaceTemplate.sslUF8.widthMillimeters == 431)
        #expect(uf8.stripCount == 8)
        #expect(approx(uf8.pitchMillimeters, 38.5))
        #expect(approx(uf8.faderCentersMillimeters[0], 84.3))
        #expect(approx(uf8.faderCentersMillimeters[7], 353.8))
        // The 8-strip zone is about 65.1 → 373.2 mm, 308 mm wide.
        #expect(approx(uf8.leftEdgeMillimeters, 65.05))
        #expect(approx(uf8.rightEdgeMillimeters, 373.05))
        #expect(approx(uf8.widthMillimeters, 308.0))
        #expect(uf8.maximumCenterErrorMillimeters < 1e-9)
        #expect(uf8.binding == .surfaceUnit(index: 0, firstStrip: 0))
        #expect(SurfaceTemplate.sslUF8.surfaceHint == .ssl)
    }

    @Test func uf8StripCentresAre38Point5MillimetresApartInPoints() throws {
        let ppmm = 4.3
        let placement = TemplatePlacement(displaySize: CGSize(width: 3440, height: 1440), pointsPerMillimeter: ppmm, hardwareLeftX: 100, meterY: 0, meterHeight: 150)
        let group = try #require(TemplateBuilder.groups(for: .sslUF8, placement: placement).first)
        #expect(group.stripCount == 8)
        #expect(approx(group.stripWidth, CGFloat(38.5 * ppmm)))
        for k in 0..<8 {
            // Each meter is centred over its fader.
            #expect(approx(group.stripCenterX(at: k), 100 + CGFloat((84.3 + 38.5 * Double(k)) * ppmm), 1e-9))
        }
        for k in 1..<8 {
            #expect(approx(group.stripCenterX(at: k) - group.stripCenterX(at: k - 1), CGFloat(38.5 * ppmm), 1e-9))
        }
        #expect(group.frame.minY == 0 && group.frame.height == 150)
        #expect(group.isVisible)
        #expect(group.physicalPitchMillimeters == 38.5)
        #expect(group.measuredPointsPerMillimeter.map { approx($0, ppmm) } == true)
    }

    @Test func uf1IsOneSelectedTrackMeterOneUF8PitchWide() throws {
        let uf1 = try #require(SurfaceTemplate.sslUF1.sections.first)
        #expect(SurfaceTemplate.sslUF1.widthMillimeters == 205)
        #expect(uf1.stripCount == 1)
        #expect(uf1.faderCentersMillimeters == [45.0])
        #expect(uf1.binding == .selectedTrack)
        #expect(approx(uf1.widthMillimeters, 38.5))
        #expect(approx(uf1.leftEdgeMillimeters, 45.0 - 19.25))
    }

    @Test func uc1HasNoGroups() {
        #expect(SurfaceTemplate.sslUC1.widthMillimeters == 300)
        #expect(SurfaceTemplate.sslUC1.sections.isEmpty)
        let placement = TemplatePlacement(displaySize: CGSize(width: 1000, height: 100), pointsPerMillimeter: 3, hardwareLeftX: 0, meterY: 0, meterHeight: 50)
        #expect(TemplateBuilder.groups(for: .sslUC1, placement: placement).isEmpty)
    }

    @Test func bronxRowIsUF8ThenUF1ThenUC1() throws {
        let row = SurfaceTemplate.bronxRow
        #expect(approx(row.widthMillimeters, 431 + 205 + 300))
        #expect(row.surfaceHint == .ssl)
        #expect(row.sections.map(\.name) == ["UF8", "UF1"])
        #expect(row.sections[0].binding == .surfaceUnit(index: 0, firstStrip: 0))
        #expect(row.sections[1].binding == .selectedTrack)
        // The UF1 fader is 45 mm into the UF1, which starts where the UF8 ends.
        #expect(approx(row.sections[1].faderCentersMillimeters[0], 476.0))
        #expect(row.surfaceUnitCount == 1)
    }

    @Test func rowsRenumberUnitsAndNamesAndHonourGaps() {
        let two = SurfaceTemplate.row(id: "2x", name: "2 × UF8", units: [.sslUF8, .sslUF8])
        #expect(two.sections.map(\.name) == ["UF8", "UF8 2"])
        #expect(two.sections[1].binding == .surfaceUnit(index: 1, firstStrip: 0))
        // Research: unit 2's fader 1 is at 515.3 mm, 161.4 mm after unit 1's fader 8 (butted).
        #expect(approx(two.sections[1].faderCentersMillimeters[0], 515.3))
        #expect(approx(two.sections[1].faderCentersMillimeters[0] - two.sections[0].faderCentersMillimeters[7], 161.5, 0.11))
        #expect(two.widthMillimeters == 862)
        #expect(two.surfaceUnitCount == 2)

        let gapped = SurfaceTemplate.row(id: "g", name: "g", units: [.sslUF8, .sslUF1], gapsMillimeters: [20])
        #expect(approx(gapped.sections[1].faderCentersMillimeters[0], 431 + 20 + 45))
        #expect(approx(gapped.widthMillimeters, 431 + 20 + 205))
    }

    @Test func wingHasSixGroupsOfFourOverItsThreeUnits() {
        let wing = SurfaceTemplate.wingMCUPlus2Extenders
        #expect(wing.isEstimate)
        #expect(wing.surfaceHint == .wing)
        #expect(wing.widthMillimeters == 870)
        #expect(wing.sections.map(\.name) == ["L1-4", "L5-8", "L9-12", "C1-4", "C5-8", "R1-4"])
        #expect(wing.sections.map(\.binding) == [
            .surfaceUnit(index: 0, firstStrip: 0),
            .surfaceUnit(index: 0, firstStrip: 4),
            .surfaceUnit(index: 1, firstStrip: 0),
            .surfaceUnit(index: 1, firstStrip: 4),
            .surfaceUnit(index: 2, firstStrip: 0),
            .surfaceUnit(index: 2, firstStrip: 4),
        ])
        #expect(wing.sections.map(\.stripCount) == [4, 4, 4, 4, 4, 4])
        #expect(wing.surfaceUnitCount == 3)
        let centres = wing.sections.flatMap(\.faderCentersMillimeters)
        #expect(centres == [61.6, 84.9, 108.8, 132.1, 166.5, 189.9, 213.2, 236.5, 271.0, 294.3, 317.6, 341.5,
                            403.3, 426.6, 450.2, 473.8, 507.8, 531.3, 554.9, 578.2, 763.8, 787.1, 810.4, 834.0])
        #expect(centres == centres.sorted())
    }

    @Test func everyWingGroupIsWithinHalfAMillimetreOfItsFaders() {
        for section in SurfaceTemplate.wingMCUPlus2Extenders.sections {
            #expect(section.maximumCenterErrorMillimeters < 0.5, "\(section.name)")
        }
        // One 8-strip group across the L4/L5 gap would be about 5 mm off; that is why L1-8 is split.
        let l1to8 = TemplateSection(
            name: "L1-8", binding: .surfaceUnit(index: 0, firstStrip: 0),
            faderCentersMillimeters: (1...8).map { SurfaceTemplate.wingFaderCentersMillimeters["L\($0)"]! }
        )
        #expect(l1to8.maximumCenterErrorMillimeters > 4.5)
    }

    @Test func wingGroupsCentreFirstAndLastStripsOnTheirFaders() {
        let placement = TemplatePlacement(displaySize: CGSize(width: 2000, height: 300), pointsPerMillimeter: 2.2, hardwareLeftX: 50, meterY: 10, meterHeight: 200)
        let groups = TemplateBuilder.groups(for: .wingMCUPlus2Extenders, placement: placement)
        #expect(groups.count == 6)
        let wing = SurfaceTemplate.wingMCUPlus2Extenders
        for (group, section) in zip(groups, wing.sections) {
            let first = placement.x(atMillimeters: section.faderCentersMillimeters.first!)
            let last = placement.x(atMillimeters: section.faderCentersMillimeters.last!)
            #expect(approx(group.stripCenterX(at: 0), first, 1e-9))
            #expect(approx(group.stripCenterX(at: group.stripCount - 1), last, 1e-9))
        }
    }

    @Test func groupsOffTheDisplayAreCreatedHidden() {
        // The whole WING centred under a 12.6" bar: only the middle sections land on the display.
        let placement = TemplatePlacement.centered(.wingMCUPlus2Extenders, displaySize: Fixtures.bar.pointSize, pointsPerMillimeter: Fixtures.barPointsPerMillimeter, meterHeight: 515)
        let groups = TemplateBuilder.groups(for: .wingMCUPlus2Extenders, placement: placement)
        #expect(groups.map(\.isVisible) == [false, false, true, true, true, false])
    }

    @Test func centeredPlacementCentresTheHardware() {
        let placement = TemplatePlacement.centered(.sslUF8, displaySize: CGSize(width: 3440, height: 1440), pointsPerMillimeter: 4, meterY: 5, meterHeight: 120)
        #expect(approx(placement.hardwareLeftX, (3440 - 431 * 4) / 2))
        #expect(approx(placement.x(atMillimeters: 431) - 3440 / 2, 3440 / 2 - placement.hardwareLeftX))
        #expect(placement.meterY == 5 && placement.meterHeight == 120)
    }

    @Test func displayLayoutAndProfileCarryScaleAndHint() {
        let placement = TemplatePlacement.centered(.bronxRow, displaySize: Fixtures.lg.pointSize, pointsPerMillimeter: Fixtures.lgPointsPerMillimeter, meterHeight: 150)
        let profile = TemplateBuilder.profile(named: "Bronx — UF8", template: .bronxRow, on: Fixtures.lg, placement: placement)
        #expect(profile.name == "Bronx — UF8")
        #expect(profile.surfaceHint == .ssl)
        #expect(profile.displays.count == 1)
        #expect(profile.displays[0].fingerprint == Fixtures.lg)
        #expect(profile.displays[0].pointsPerMillimeter == Fixtures.lgPointsPerMillimeter)
        #expect(profile.allGroups.map(\.name) == ["UF8", "UF1"])
        #expect(Set(profile.allGroups.map(\.id)).count == 2)
    }

    @Test func profileCountsTheSurfaceUnitsItsGroupsUse() {
        func profile(_ template: SurfaceTemplate) -> LayoutProfile {
            let placement = TemplatePlacement.centered(template, displaySize: Fixtures.lg.pointSize, pointsPerMillimeter: 2, meterHeight: 100)
            return TemplateBuilder.profile(named: template.name, template: template, on: Fixtures.lg, placement: placement)
        }
        #expect(profile(.wingMCUPlus2Extenders).surfaceUnitCount == 3)
        #expect(profile(.bronxRow).surfaceUnitCount == 1)
        #expect(profile(.sslUF1).surfaceUnitCount == 0)
    }

    @Test func displayMetricsRejectImplausibleEDIDSizes() {
        let lg = DisplayMetrics.pointsPerMillimeter(pointWidth: 3440, physicalWidthMillimeters: 797.2)
        #expect(lg.map { approx($0, 3440 / 797.2) } == true)
        #expect(DisplayMetrics.pointsPerMillimeter(pointWidth: 1920, physicalWidthMillimeters: 0) == nil)
        #expect(DisplayMetrics.pointsPerMillimeter(pointWidth: 1920, physicalWidthMillimeters: 10) == nil)
        #expect(DisplayMetrics.pointsPerMillimeter(pointWidth: 0, physicalWidthMillimeters: 300) == nil)
        #expect(DisplayMetrics.pointsPerMillimeter(pointWidth: 1920, physicalWidthMillimeters: .nan) == nil)
    }

    @Test func builtInTemplatesHaveUniqueIDs() {
        let ids = SurfaceTemplate.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
