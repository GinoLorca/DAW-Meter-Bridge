import BridgeLayout
import CoreGraphics
import Foundation
import Testing

/// "Slide the bridge over": develop on a strip along the bottom of the LG ultrawide, then move the
/// same layout to a 12.6" 1920×515 bar display and recalibrate.
@Suite struct DisplayTransferTests {
    static func lgLayout(_ template: SurfaceTemplate) -> DisplayLayout {
        let placement = TemplatePlacement.centered(template, displaySize: Fixtures.lg.pointSize, pointsPerMillimeter: Fixtures.lgPointsPerMillimeter, meterY: 0, meterHeight: 150)
        return TemplateBuilder.displayLayout(for: template, on: Fixtures.lg, placement: placement)
    }

    @Test func uf8KeepsItsPhysicalSizeOnTheBar() throws {
        let source = Self.lgLayout(.sslUF8)
        let result = DisplayTransfer.move(source, to: Fixtures.bar, targetPointsPerMillimeter: Fixtures.barPointsPerMillimeter)
        #expect(result.mode == .physical)
        #expect(result.offscreenGroupIDs.isEmpty)
        #expect(result.layout.fingerprint == Fixtures.bar)
        #expect(result.layout.pointsPerMillimeter == Fixtures.barPointsPerMillimeter)

        let group = try #require(result.layout.groups.first)
        #expect(group.id == source.groups[0].id)
        // Strips are still 38.5 mm apart, now in bar-display points.
        // (Within the pixel-grid snap: edges move at most half a pixel, so 1/8 pt per strip.)
        #expect(approx(group.stripWidth, CGFloat(38.5 * Fixtures.barPointsPerMillimeter), 0.13))
        // The 308 mm group just fits the 309 mm bar. It keeps its relative position (near the centre),
        // then is nudged fully onto the display.
        #expect(group.frame.minX >= 0 && group.frame.maxX <= 1920 + 1e-9)
        #expect(abs(group.frame.midX - source.groups[0].frame.midX / 3440 * 1920) < 5)
        // It stays along the bottom, 150 pt on the LG = 34.8 mm = 216 pt on the bar.
        #expect(group.frame.minY == 0)
        #expect(approx(group.frame.height, CGFloat(150 / Fixtures.lgPointsPerMillimeter * Fixtures.barPointsPerMillimeter), 1))
    }

    @Test func bronxRowKeepsTheUF8OnTheBarAndReportsTheUF1Offscreen() throws {
        // UF8 + UF1 span about 430 mm; the bar is 309 mm. The UF8 group (most strips) is the anchor.
        let source = Self.lgLayout(.bronxRow)
        let result = DisplayTransfer.move(source, to: Fixtures.bar, targetPointsPerMillimeter: Fixtures.barPointsPerMillimeter)
        let uf8 = result.layout.groups[0]
        let uf1 = result.layout.groups[1]
        #expect(uf8.frame.minX >= -1e-9 && uf8.frame.maxX <= 1920 + 1e-9)
        #expect(result.offscreenGroupIDs == [uf1.id])
        // Physical spacing between UF8 fader 1 and the UF1 fader is preserved: 476 − 84.3 = 391.7 mm.
        let millimeters = Double(uf1.stripCenterX(at: 0) - uf8.stripCenterX(at: 0)) / Fixtures.barPointsPerMillimeter
        #expect(approx(millimeters, 391.7, 0.2))
    }

    @Test func explicitAnchorKeepsThatGroupsRelativePosition() throws {
        let source = Self.lgLayout(.bronxRow)
        let uf1 = source.groups[1]
        let result = DisplayTransfer.move(source, to: Fixtures.bar, targetPointsPerMillimeter: Fixtures.barPointsPerMillimeter, anchorGroupID: uf1.id)
        let moved = try #require(result.layout.groups.first { $0.id == uf1.id })
        #expect(approx(moved.frame.midX / 1920, uf1.frame.midX / 3440, 1e-3))
        #expect(moved.frame.minY == 0)
    }

    @Test func withoutScalesFramesMoveProportionally() {
        var source = Self.lgLayout(.sslUF8)
        source.pointsPerMillimeter = nil
        let result = DisplayTransfer.move(source, to: Fixtures.bar, targetPointsPerMillimeter: Fixtures.barPointsPerMillimeter)
        #expect(result.mode == .proportional)
        let before = source.groups[0].frame
        let after = result.layout.groups[0].frame
        #expect(approx(after.minX, before.minX * 1920 / 3440, 0.5))
        #expect(approx(after.width, before.width * 1920 / 3440, 1))
        #expect(approx(after.minY, before.minY * 515 / 1440, 0.5))
        #expect(approx(after.height, before.height * 515 / 1440, 1))
        #expect(result.layout.pointsPerMillimeter == Fixtures.barPointsPerMillimeter)

        let unknownTarget = DisplayTransfer.move(Self.lgLayout(.sslUF8), to: Fixtures.bar, targetPointsPerMillimeter: nil)
        #expect(unknownTarget.mode == .proportional)
        #expect(unknownTarget.layout.pointsPerMillimeter == nil)
    }

    @Test func movingBackAndForthReturnsToTheStart() throws {
        // When nothing has to be nudged onto the display, a move is reversible (up to the pixel-grid snap).
        let source = Self.lgLayout(.sslUF8)
        let brooklynScale = 1920.0 / 597.0
        let there = DisplayTransfer.move(source, to: Fixtures.brooklyn, targetPointsPerMillimeter: brooklynScale)
        #expect(approx(there.layout.groups[0].frame.midX / 1920, source.groups[0].frame.midX / 3440, 1e-3))
        let back = DisplayTransfer.move(there.layout, to: Fixtures.lg, targetPointsPerMillimeter: Fixtures.lgPointsPerMillimeter)
        #expect(approx(back.layout.groups[0].frame, source.groups[0].frame, 1.5))
    }

    @Test func profileMoveMergesEveryDisplayOntoTheTarget() {
        var profile = LayoutProfile(name: "Bronx", displays: [Self.lgLayout(.sslUF8)], surfaceHint: .ssl)
        // A group already on the bar stays where it is.
        let existing = StripGroup(name: "Main", binding: .mainTrack, stripCount: 1, frame: CGRect(x: 1800, y: 0, width: 100, height: 515))
        profile.displays.append(DisplayLayout(fingerprint: Fixtures.bar, groups: [existing], pointsPerMillimeter: Fixtures.barPointsPerMillimeter))

        let result = profile.moveAllGroups(to: Fixtures.bar, targetPointsPerMillimeter: Fixtures.barPointsPerMillimeter)
        #expect(result.mode == .physical)
        #expect(profile.displays.count == 1)
        #expect(profile.displays[0].fingerprint == Fixtures.bar)
        #expect(profile.allGroups.count == 2)
        #expect(profile.group(withID: existing.id)?.frame == existing.frame)
        #expect(profile.allGroups.allSatisfy { $0.frame.intersects(Fixtures.bar.bounds) })
    }

    @Test func modeChangeOnTheSameDisplayRescales() {
        let source = Self.lgLayout(.sslUF8)
        var halfSize = Fixtures.lg
        halfSize.pointSize = CGSize(width: 1720, height: 720)
        let adapted = source.adapted(to: halfSize)
        #expect(approx(adapted.groups[0].frame, CGRect(
            x: source.groups[0].frame.minX / 2,
            y: source.groups[0].frame.minY / 2,
            width: source.groups[0].frame.width / 2,
            height: source.groups[0].frame.height / 2
        ), 0.5))
        #expect(adapted.pointsPerMillimeter.map { approx($0, Fixtures.lgPointsPerMillimeter / 2) } == true)
        #expect(adapted.fingerprint == halfSize)
    }

    /// True when every edge of every group lies on the layout's device-pixel grid.
    static func isOnPixelGrid(_ layout: DisplayLayout) -> Bool {
        let scale = layout.fingerprint.backingScale
        func onGrid(_ v: CGFloat) -> Bool { abs((v * scale).rounded() - v * scale) < 1e-6 }
        return layout.groups.allSatisfy { g in
            onGrid(g.frame.minX) && onGrid(g.frame.minY) && onGrid(g.frame.maxX) && onGrid(g.frame.maxY)
        }
    }

    @Test func movedAndAdaptedFramesLandOnThePixelGrid() {
        let source = Self.lgLayout(.bronxRow)
        let toRetina = DisplayTransfer.move(source, to: Fixtures.brooklyn, targetPointsPerMillimeter: 1920.0 / 597.0)
        #expect(Self.isOnPixelGrid(toRetina.layout))
        let proportional = DisplayTransfer.move(source, to: Fixtures.bar, targetPointsPerMillimeter: nil)
        #expect(Self.isOnPixelGrid(proportional.layout))
        var scaled = Fixtures.lg
        scaled.pointSize = CGSize(width: 2293.33, height: 960)
        #expect(Self.isOnPixelGrid(source.adapted(to: scaled)))
        var profile = LayoutProfile(name: "Bronx", displays: [source])
        profile.moveAllGroups(to: Fixtures.brooklyn, targetPointsPerMillimeter: 1920.0 / 597.0)
        #expect(Self.isOnPixelGrid(profile.displays[0]))
    }

    @Test func standInOnATallDisplaySitsAlongTheBottom() throws {
        // A full-height layout on the 515-pt bar, shown on the LG while the bar is off.
        let placement = TemplatePlacement.centered(.sslUF8, displaySize: Fixtures.bar.pointSize, pointsPerMillimeter: Fixtures.barPointsPerMillimeter, meterY: 0, meterHeight: 515)
        let bar = TemplateBuilder.displayLayout(for: .sslUF8, on: Fixtures.bar, placement: placement)
        let moved = DisplayTransfer.move(bar, to: Fixtures.lg, targetPointsPerMillimeter: Fixtures.lgPointsPerMillimeter)
        #expect(try #require(moved.layout.groups.first).frame.minY > 400, "move alone keeps it mid-screen")

        let standIn = DisplayTransfer.standIn(moved.layout, from: bar)
        let group = try #require(standIn.groups.first)
        #expect(group.frame.minY == 0)
        #expect(group.frame.height <= 1440 * DisplayTransfer.standInMaximumHeightFraction)
        // Physical size kept (it fits under the height limit), horizontal position kept.
        #expect(approx(group.frame.width, moved.layout.groups[0].frame.width, 1))
        #expect(approx(group.frame.midX, moved.layout.groups[0].frame.midX, 1))
        #expect(Self.isOnPixelGrid(standIn))
    }

    @Test func standInIsShrunkToAQuarterOfTheDisplayAndKeepsItsBottomMargin() throws {
        var source = Self.lgLayout(.bronxRow)
        for i in source.groups.indices { source.groups[i].frame.origin.y = 40 }
        let short = DisplayFingerprint(name: "Laptop", pixelSize: CGSize(width: 2400, height: 600), pointSize: CGSize(width: 1200, height: 300))
        let moved = DisplayTransfer.move(source, to: short, targetPointsPerMillimeter: Fixtures.lgPointsPerMillimeter)
        let standIn = DisplayTransfer.standIn(moved.layout, from: source)
        let box = standIn.groups.map(\.frame).reduce(standIn.groups[0].frame) { $0.union($1) }
        let movedBox = moved.layout.groups.map(\.frame).reduce(moved.layout.groups[0].frame) { $0.union($1) }
        #expect(approx(box.height, 75, 0.5), "150 pt shrunk to a quarter of 300")
        #expect(approx(box.minY, 40, 0.5), "same scale, so the 40 pt bottom margin stays")
        #expect(approx(box.midX, movedBox.midX, 0.5))
        #expect(approx(box.width, movedBox.width / 2, 1))
        #expect(Self.isOnPixelGrid(standIn))
        // Hidden groups move along but don't count for the box.
        #expect(standIn.groups.count == source.groups.count)
    }
}
