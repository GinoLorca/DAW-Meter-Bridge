import BridgeLayout
import CoreGraphics
import Testing

@Suite struct StripGroupTests {
    let group = StripGroup(
        name: "UF8",
        binding: .surfaceUnit(index: 0, firstStrip: 0),
        stripCount: 8,
        frame: CGRect(x: 100, y: 20, width: 800, height: 150),
        physicalPitchMillimeters: 38.5
    )

    @Test func stripGeometry() {
        #expect(group.stripWidth == 100)
        #expect(group.localStripFrame(at: 2) == CGRect(x: 200, y: 0, width: 100, height: 150))
        #expect(group.stripFrame(at: 2) == CGRect(x: 300, y: 20, width: 100, height: 150))
        #expect(group.stripCenterX(at: 0) == 150)
        #expect(group.stripCenterX(at: 7) == 850)
    }

    @Test func hitTesting() {
        #expect(group.stripIndex(atX: 99.9) == nil)
        #expect(group.stripIndex(atX: 100) == 0)
        #expect(group.stripIndex(atX: 199.99) == 0)
        #expect(group.stripIndex(atX: 200) == 1)
        #expect(group.stripIndex(atX: 899.99) == 7)
        #expect(group.stripIndex(atX: 900) == nil)
        #expect(group.stripIndex(atLocalX: 350) == 3)
        #expect(group.stripIndex(atLocalX: -1) == nil)
    }

    @Test func stripCountIsAtLeastOne() {
        let empty = StripGroup(name: "x", binding: .mainTrack, stripCount: 0, frame: CGRect(x: 0, y: 0, width: 40, height: 10))
        #expect(empty.stripCount == 1)
        #expect(empty.stripWidth == 40)

        var broken = group
        broken.stripCount = 0
        #expect(broken.stripWidth == 800)
        #expect(broken.resolveTracks(in: Fixtures.snapshot()).count == 1)
    }

    @Test func frameIsStandardized() {
        let flipped = StripGroup(name: "x", binding: .mainTrack, stripCount: 1, frame: CGRect(x: 50, y: 50, width: -20, height: -10))
        #expect(flipped.frame == CGRect(x: 30, y: 40, width: 20, height: 10))
    }

    @Test func measuredScaleComesFromThePitch() {
        #expect(group.measuredPointsPerMillimeter.map { approx($0, 100 / 38.5) } == true)
        var noPitch = group
        noPitch.physicalPitchMillimeters = nil
        #expect(noPitch.measuredPointsPerMillimeter == nil)
    }

    @Test func resolvesThroughItsBinding() {
        let snapshot = Fixtures.snapshot(unitCount: 1)
        #expect(group.resolveTracks(in: snapshot) == (0..<8).map { Fixtures.id($0) })
    }
}
