import BridgeLayout
import CoreGraphics
import Foundation
import MeterCore
import Testing

@Suite struct MainMeterTests {
    /// The user's LG HDR WQHD at "looks like 2560 × 1067" (2x).
    static let lgWQHD = DisplayFingerprint(
        uuid: "LG-WQHD",
        vendorID: 7789,
        modelID: 30_000,
        serialNumber: 77,
        name: "LG HDR WQHD",
        pixelSize: CGSize(width: 5120, height: 2134),
        pointSize: CGSize(width: 2560, height: 1067)
    )

    static func group(_ name: String, _ binding: StripBinding, strips: Int, _ frame: CGRect, visible: Bool = true) -> StripGroup {
        StripGroup(name: name, binding: binding, stripCount: strips, frame: frame, isVisible: visible)
    }

    /// The Bronx profile as saved on the user's Mac (UF8 and UF1 along the bottom of the LG).
    static func bronx() -> LayoutProfile {
        LayoutProfile(name: "Bronx — UF8", displays: [
            DisplayLayout(fingerprint: lgWQHD, groups: [
                group("UF8", .surfaceUnit(index: 0, firstStrip: 0), strips: 8, CGRect(x: 106, y: 0, width: 897.5, height: 200)),
                group("UF1", .selectedTrack, strips: 1, CGRect(x: 1247, y: 0, width: 112.5, height: 200)),
            ], pointsPerMillimeter: 2.913),
        ], surfaceHint: .ssl)
    }

    /// The Brooklyn profile as saved on the user's Mac: R1-4 ends 83.5 pt from the right edge.
    static func brooklyn() -> LayoutProfile {
        let frames: [(String, Int, Int, CGFloat, CGFloat)] = [
            ("L1-4", 0, 0, 158, 274), ("L5-8", 0, 4, 464, 271.5), ("L9-12", 1, 0, 768, 274),
            ("C1-4", 1, 4, 1153.5, 274), ("C5-8", 2, 0, 1458, 273.5), ("R1-4", 2, 4, 2204, 272.5),
        ]
        return LayoutProfile(name: "Brooklyn — WING", displays: [
            DisplayLayout(fingerprint: lgWQHD, groups: frames.map { name, unit, first, x, width in
                group(name, .surfaceUnit(index: unit, firstStrip: first), strips: 4, CGRect(x: x, y: 0, width: width, height: 200))
            }),
        ], surfaceHint: .wing)
    }

    // MARK: - Placement

    @Test func bronxMainMeterStandsAtTheRightEdgeLevelWithTheUF8() throws {
        var profile = Self.bronx()
        let added = profile.addMainMeter()
        let id = try #require(added)
        let main = try #require(profile.group(withID: id))
        #expect(main.name == "Main")
        #expect(main.binding == .mainTrack)
        #expect(main.stripCount == 1)
        #expect(main.isVisible)
        #expect(main.physicalPitchMillimeters == nil)
        // 1.5 × the UF8's 112.19 pt pitch, 8 pt from the right edge, snapped to the 2x pixel grid.
        #expect(main.frame == CGRect(x: 2383.5, y: 0, width: 168.5, height: 200))
        #expect(profile.displays[0].groups.last?.id == id)
        #expect(profile.isMainMeterVisible)
    }

    @Test func brooklynMainMeterNarrowsToFitBesideR1to4() throws {
        var profile = Self.brooklyn()
        let added = profile.addMainMeter()
        let main = try #require(added.flatMap(profile.group(withID:)))
        // R1-4 ends at 2476.5; the meter takes the 67.5 pt left between it and the 8 pt margin.
        #expect(main.frame == CGRect(x: 2484.5, y: 0, width: 67.5, height: 200))
        let others = profile.allGroups.filter { !$0.isMainMeter }
        #expect(!others.contains { $0.frame.intersects(main.frame) })
    }

    @Test func frameFollowsTheReferenceAndSnapsToPixels() {
        let bounds = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let reference = Self.group("UF8", .surfaceUnit(index: 0, firstStrip: 0), strips: 8, CGRect(x: 1000, y: 37, width: 561, height: 180.5))
        let frame = MainMeter.frame(alignedWith: reference, others: [reference.frame], in: bounds, backingScale: 1)
        // pitch 70.125 × 1.5 = 105.19 → left edge 3326.8 snapped to 3327 at 1x.
        #expect(frame == CGRect(x: 3327, y: 37, width: 105, height: 181))
        #expect(frame.maxX == bounds.maxX - MainMeter.margin)
    }

    @Test func withoutAReferenceItUsesTheFallbackSize() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = MainMeter.frame(alignedWith: nil, others: [], in: bounds, backingScale: 2, fallbackY: 60, fallbackHeight: 200)
        #expect(frame == CGRect(x: 1920 - 8 - 90, y: 60, width: 90, height: 200))
    }

    @Test func widthIsCappedAndFloored() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 300)
        let wide = Self.group("Big", .trackList(offset: 0), strips: 1, CGRect(x: 0, y: 0, width: 300, height: 100))
        // 1.5 × 300 would be 450: capped at a quarter of the display.
        #expect(MainMeter.frame(alignedWith: wide, others: [], in: narrow, backingScale: 1).width == 100)
        let thin = Self.group("Thin", .trackList(offset: 0), strips: 16, CGRect(x: 0, y: 0, width: 160, height: 100))
        // 1.5 × 10 = 15 is too thin to read: at least the minimum width.
        #expect(MainMeter.frame(alignedWith: thin, others: [], in: narrow, backingScale: 1).width == MainMeter.minimumWidth)
    }

    @Test func noRoomBesideAGroupLiftsItAbove() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let reference = Self.group("A", .trackList(offset: 0), strips: 4, CGRect(x: 100, y: 0, width: 240, height: 150))
        // A group runs right up to the edge: no room beside it.
        let blocker = CGRect(x: 1700, y: 0, width: 220, height: 150)
        let frame = MainMeter.frame(alignedWith: reference, others: [reference.frame, blocker], in: bounds, backingScale: 1)
        #expect(frame == CGRect(x: 1822, y: 158, width: 90, height: 150))
        #expect(!frame.intersects(blocker))
    }

    @Test func noRoomAnywhereKeepsTheRightEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 200)
        let reference = Self.group("A", .trackList(offset: 0), strips: 4, CGRect(x: 100, y: 0, width: 240, height: 200))
        let blocker = CGRect(x: 1700, y: 0, width: 220, height: 200)
        let frame = MainMeter.frame(alignedWith: reference, others: [blocker], in: bounds, backingScale: 1)
        #expect(frame == CGRect(x: 1822, y: 0, width: 90, height: 200))
    }

    // MARK: - Show / hide

    @Test func showCreatesHideKeepsAndShowRestores() throws {
        var profile = Self.bronx()
        #expect(!profile.hasMainMeter)
        #expect(!profile.isMainMeterVisible)
        let hidNothing = profile.setMainMeterVisible(false)
        #expect(!hidNothing)

        let createdOne = profile.setMainMeterVisible(true)
        #expect(createdOne)
        let created = try #require(profile.mainMeterGroups.first)
        #expect(profile.mainMeterGroups.count == 1)
        let createdAgain = profile.setMainMeterVisible(true)
        #expect(!createdAgain)

        // The user moved it; hiding keeps the group and its place.
        var moved = created
        moved.frame = CGRect(x: 2000, y: 300, width: 150, height: 180)
        profile.updateGroup(moved)
        let hid = profile.setMainMeterVisible(false)
        #expect(hid)
        #expect(profile.hasMainMeter)
        #expect(!profile.isMainMeterVisible)
        #expect(profile.group(withID: created.id)?.frame == moved.frame)
        #expect(profile.group(withID: created.id)?.isVisible == false)

        let showed = profile.setMainMeterVisible(true)
        #expect(showed)
        #expect(profile.mainMeterGroups == [moved])
    }

    @Test func showBringsAnOffDisplayMainMeterBack() throws {
        var profile = Self.bronx()
        profile.displays[0].groups.append(Self.group("Main", .mainTrack, strips: 1, CGRect(x: 2700, y: -300, width: 100, height: 200), visible: false))
        let showed = profile.setMainMeterVisible(true)
        #expect(showed)
        let main = try #require(profile.mainMeterGroups.first)
        #expect(main.isVisible)
        #expect(main.frame == CGRect(x: 2460, y: 0, width: 100, height: 200))
    }

    @Test func aMainMeterOffItsDisplayDoesNotCountAsShown() throws {
        var profile = Self.bronx()
        profile.displays[0].groups.append(Self.group("Main", .mainTrack, strips: 1, CGRect(x: 4827, y: 0, width: 100, height: 200)))
        #expect(profile.hasMainMeter)
        #expect(!profile.isMainMeterVisible)
        // Showing it puts it back on the display.
        let showed = profile.setMainMeterVisible(true)
        #expect(showed)
        #expect(profile.isMainMeterVisible)
        let main = try #require(profile.mainMeterGroups.first)
        #expect(main.frame.intersects(Self.lgWQHD.bounds))
    }

    // MARK: - Moving the bridge

    @Test func movingTheBridgeToABarDisplayKeepsTheMainMeterAtItsRightEdge() throws {
        var profile = Self.bronx()
        let added = profile.addMainMeter()
        let id = try #require(added)
        let result = profile.moveAllGroups(to: Fixtures.bar, targetPointsPerMillimeter: Fixtures.barPointsPerMillimeter)
        #expect(result.mode == .physical)
        // Its physical offset from the UF8 leaves the Main meter off the 1920-pt bar.
        #expect(result.offscreenGroupIDs.contains(id))
        #expect(!profile.isMainMeterVisible)

        let reanchored = profile.reanchorMainMeters()
        #expect(reanchored)
        let main = try #require(profile.group(withID: id))
        let uf8 = try #require(profile.allGroups.first { $0.name == "UF8" })
        #expect(main.isVisible)
        #expect(main.frame.maxX == Fixtures.bar.bounds.maxX - MainMeter.margin)
        #expect(main.frame.minY == uf8.frame.minY)
        #expect(main.frame.height == uf8.frame.height)
        #expect(Fixtures.bar.bounds.contains(main.frame))
        #expect(profile.isMainMeterVisible)
        // The other groups stay where the move put them.
        #expect(profile.allGroups.filter { !$0.isMainMeter } == result.layout.groups.filter { !$0.isMainMeter })
    }

    @Test func reanchoringKeepsAHiddenMainMeterHidden() throws {
        var profile = Self.bronx()
        profile.displays[0].groups.append(Self.group("Main", .mainTrack, strips: 1, CGRect(x: 4827, y: 0, width: 100, height: 200), visible: false))
        profile.reanchorMainMeters()
        let main = try #require(profile.mainMeterGroups.first)
        #expect(!main.isVisible)
        #expect(main.frame == CGRect(x: 2383.5, y: 0, width: 168.5, height: 200))
        // Already in place: nothing to do.
        let again = profile.reanchorMainMeters()
        #expect(!again)
    }

    @Test func everyMainMeterGroupSwitchesTogether() {
        var profile = Self.bronx()
        profile.displays[0].groups.append(Self.group("Main", .mainTrack, strips: 1, CGRect(x: 2400, y: 0, width: 100, height: 200)))
        profile.displays[0].groups.append(Self.group("Main 2", .mainTrack, strips: 1, CGRect(x: 1400, y: 0, width: 100, height: 200), visible: false))
        let others = profile.allGroups.filter { !$0.isMainMeter }
        #expect(profile.isMainMeterVisible)
        let hid = profile.setMainMeterVisible(false)
        #expect(hid)
        #expect(profile.mainMeterGroups.allSatisfy { !$0.isVisible })
        let showed = profile.setMainMeterVisible(true)
        #expect(showed)
        #expect(profile.mainMeterGroups.allSatisfy { $0.isVisible })
        #expect(profile.mainMeterGroups.count == 2)
        // Other groups are untouched.
        #expect(profile.allGroups.filter { !$0.isMainMeter } == others)
    }

    @Test func linesUpWithTheFirstVisibleGroupOnItsDisplay() throws {
        let bar = Fixtures.bar
        var profile = LayoutProfile(name: "Two displays", displays: [
            DisplayLayout(fingerprint: Fixtures.lg, groups: [
                Self.group("Hidden", .trackList(offset: 0), strips: 8, CGRect(x: 0, y: 500, width: 800, height: 300), visible: false),
            ]),
            DisplayLayout(fingerprint: bar, groups: [
                Self.group("UF8", .surfaceUnit(index: 0, firstStrip: 0), strips: 8, CGRect(x: 200, y: 20, width: 640, height: 400)),
            ]),
        ])
        let added = profile.addMainMeter()
        let id = try #require(added)
        #expect(profile.location(ofGroup: id)?.display == 1)
        #expect(profile.group(withID: id)?.frame == CGRect(x: 1920 - 8 - 120, y: 20, width: 120, height: 400))
    }

    @Test func aProfileWithoutGroupsUsesTheFallback() throws {
        var empty = LayoutProfile(name: "Empty")
        let addedWithoutFallback = empty.addMainMeter()
        #expect(addedWithoutFallback == nil)
        let showedWithoutFallback = empty.setMainMeterVisible(true)
        #expect(!showedWithoutFallback)

        let fallback = MainMeterFallback(display: Fixtures.brooklyn, y: 70, height: 200)
        let showedWithFallback = empty.setMainMeterVisible(true, fallback: fallback)
        #expect(showedWithFallback)
        #expect(empty.displays.count == 1)
        #expect(empty.displays[0].fingerprint == Fixtures.brooklyn)
        #expect(empty.mainMeterGroups.first?.frame == CGRect(x: 1920 - 8 - 90, y: 70, width: 90, height: 200))

        // An existing layout for the fallback display is reused.
        var withLayout = LayoutProfile(name: "Layout only", displays: [DisplayLayout(fingerprint: Fixtures.brooklyn)])
        let addedToLayout = withLayout.addMainMeter(fallback: fallback)
        #expect(addedToLayout != nil)
        #expect(withLayout.displays.count == 1)
    }

    @Test func aNewMainMeterGetsAFreeName() throws {
        var profile = Self.bronx()
        profile.displays[0].groups[1].name = "Main"
        let added = profile.addMainMeter()
        let id = try #require(added)
        #expect(profile.group(withID: id)?.name == "Main 2")
    }

    // MARK: - Migration and persistence

    @Test func migrationAddsOneVisibleMainMeterWhereMissing() throws {
        var hiddenMain = Self.brooklyn()
        hiddenMain.displays[0].groups.append(Self.group("Main", .mainTrack, strips: 1, CGRect(x: 2484.5, y: 0, width: 67.5, height: 200), visible: false))
        var document = LayoutDocument(profiles: [Self.bronx(), hiddenMain, LayoutProfile(name: "Empty")], activeProfileID: nil)
        let addedCount = document.addMainMetersWhereMissing()
        #expect(addedCount == 1)
        #expect(document.profiles[0].isMainMeterVisible)
        // A profile that already has one (even hidden, i.e. the user turned it off) is left alone.
        #expect(document.profiles[1] == hiddenMain)
        #expect(!document.profiles[2].hasMainMeter)

        let fallback = MainMeterFallback(display: Self.lgWQHD, y: 0, height: 200)
        let addedWithFallback = document.addMainMetersWhereMissing(fallback: fallback)
        #expect(addedWithFallback == 1)
        #expect(document.profiles[2].isMainMeterVisible)
        let addedAgain = document.addMainMetersWhereMissing(fallback: fallback)
        #expect(addedAgain == 0)
    }

    @Test func aHiddenMainMeterSurvivesSaving() throws {
        var profile = Self.bronx()
        profile.setMainMeterVisible(true)
        profile.setMainMeterVisible(false)
        let document = LayoutDocument(profiles: [profile], activeProfileID: profile.id)
        let decoded = try JSONDecoder().decode(LayoutDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded == document)
        #expect(decoded.activeProfile?.hasMainMeter == true)
        #expect(decoded.activeProfile?.isMainMeterVisible == false)
    }

    @Test func theMainMeterShowsTheMainTrackWithoutWatchingIt() {
        let main = Self.group("Main", .mainTrack, strips: 1, CGRect(x: 0, y: 0, width: 90, height: 200))
        let snapshot = Fixtures.snapshot(tracks: 12, unitCount: 1)
        #expect(main.resolveTracks(in: snapshot) == [TrackID(9999)])
        // The script meters the main track on its own, so it never goes into `watch`.
        #expect([main].watchedTracks(in: snapshot).isEmpty)
    }
}
