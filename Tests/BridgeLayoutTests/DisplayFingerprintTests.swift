import BridgeLayout
import CoreGraphics
import Testing

@Suite struct DisplayFingerprintTests {
    @Test func sameUUIDWinsEvenWhenEverythingElseChanged() {
        var renamed = Fixtures.lg
        renamed.name = "Renamed"
        renamed.pointSize = CGSize(width: 1720, height: 720)
        renamed.serialNumber = 1
        #expect(Fixtures.lg.match(renamed) == .uuid)
    }

    @Test func vendorModelAndNonZeroSerialMatchWithoutUUID() {
        var other = Fixtures.lg
        other.uuid = "DIFFERENT"
        other.name = "LG HDR WQHD"
        #expect(Fixtures.lg.match(other) == .vendorModelSerial)

        other.uuid = nil
        #expect(Fixtures.lg.match(other) == .vendorModelSerial)
    }

    @Test func zeroSerialFallsBackToNameAndSize() {
        var a = Fixtures.bar
        a.uuid = nil
        var b = a
        b.uuid = "OTHER-PORT"
        #expect(a.match(b) == .vendorModelNameSize)

        // A different pixel size but the same point size still counts as the same size.
        b.pixelSize = CGSize(width: 3840, height: 1030)
        #expect(a.match(b) == .vendorModelNameSize)

        // Both sizes different: only the name is left.
        b.pointSize = CGSize(width: 1280, height: 343)
        #expect(a.match(b) == .name)
    }

    @Test func nameOnlyAndNoMatch() {
        let a = DisplayFingerprint(name: "Bar", pixelSize: CGSize(width: 1920, height: 515), pointSize: CGSize(width: 1920, height: 515))
        var b = DisplayFingerprint(vendorID: 9, name: "Bar", pixelSize: .zero, pointSize: .zero)
        #expect(a.match(b) == .name)
        b.name = "Other"
        #expect(a.match(b) == .none)
    }

    @Test func emptyNamesNeverMatch() {
        let a = DisplayFingerprint(name: "", pixelSize: CGSize(width: 10, height: 10), pointSize: CGSize(width: 10, height: 10))
        #expect(a.match(a) == .none)
    }

    @Test func matchTiersAreOrdered() {
        #expect(DisplayMatch.uuid > .vendorModelSerial)
        #expect(DisplayMatch.vendorModelSerial > .vendorModelNameSize)
        #expect(DisplayMatch.vendorModelNameSize > .name)
        #expect(DisplayMatch.name > .none)
        #expect(!DisplayMatch.none.isMatch)
    }

    @Test func backingScaleAndBounds() {
        #expect(Fixtures.brooklyn.backingScale == 2)
        #expect(Fixtures.lg.backingScale == 1)
        #expect(Fixtures.bar.bounds == CGRect(x: 0, y: 0, width: 1920, height: 515))
        #expect(DisplayFingerprint(name: "x", pixelSize: .zero, pointSize: .zero).backingScale == 1)
    }

    @Test func assignmentTellsIdenticalBarsApartByUUID() {
        var left = Fixtures.bar
        left.uuid = "LEFT"
        var right = Fixtures.bar
        right.uuid = "RIGHT"
        // Connected in the opposite order to the saved one.
        let assignments = DisplayMatcher.assign([left, right], to: [right, left])
        #expect(assignments == [
            DisplayAssignment(layoutIndex: 0, displayIndex: 1, match: .uuid),
            DisplayAssignment(layoutIndex: 1, displayIndex: 0, match: .uuid),
        ])
    }

    @Test func assignmentUsesEachDisplayOnceAndSkipsUnmatched() {
        var lgElsewhere = Fixtures.lg
        lgElsewhere.uuid = nil
        let assignments = DisplayMatcher.assign([Fixtures.brooklyn, lgElsewhere, Fixtures.lg], to: [Fixtures.lg, Fixtures.bar])
        // The exact LG (uuid) wins the only LG; the uuid-less copy and the Brooklyn display get nothing.
        #expect(assignments == [DisplayAssignment(layoutIndex: 2, displayIndex: 0, match: .uuid)])
    }
}
