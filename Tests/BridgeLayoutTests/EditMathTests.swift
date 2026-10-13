import BridgeLayout
import CoreGraphics
import Testing

@Suite struct FineDragTests {
    @Test func normalDragFollowsThePointer() {
        var drag = FineDrag(backingScale: 2, start: CGPoint(x: 10, y: 10))
        drag.drag(to: CGPoint(x: 13, y: 8), fine: false)
        drag.drag(to: CGPoint(x: 20, y: 8), fine: false)
        #expect(drag.translation == CGVector(dx: 10, dy: -2))
        #expect(drag.apply(to: CGPoint(x: 100, y: 50)) == CGPoint(x: 110, y: 48))
    }

    @Test func shiftMovesATenthAsFar() {
        var drag = FineDrag(backingScale: 1)
        for _ in 0..<10 { drag.add(CGVector(dx: 1, dy: 0), fine: true) }
        #expect(approx(drag.translation.dx, 1.0, 1e-9))
        #expect(drag.snappedTranslation == CGVector(dx: 1, dy: 0))
    }

    @Test func subPointMotionAccumulatesAndSnapsToDevicePixels() {
        // Retina: one device pixel is 0.5 pt. Fine drags of 3 pt move 0.3 pt each.
        var drag = FineDrag(backingScale: 2)
        let origin = CGPoint(x: 100, y: 0)
        drag.add(CGVector(dx: 3, dy: 0), fine: true)
        #expect(drag.apply(to: origin).x == 100.5)   // 100.3 → nearest half point
        drag.add(CGVector(dx: 3, dy: 0), fine: true)
        #expect(drag.apply(to: origin).x == 100.5)   // 100.6
        drag.add(CGVector(dx: 3, dy: 0), fine: true)
        #expect(drag.apply(to: origin).x == 101)     // 100.9
        #expect(approx(drag.translation.dx, 0.9, 1e-9))

        // Non-Retina: whole points.
        var oneX = FineDrag(backingScale: 1)
        oneX.add(CGVector(dx: 3, dy: 0), fine: true)
        #expect(oneX.apply(to: origin).x == 100)
        oneX.add(CGVector(dx: 3, dy: 0), fine: true)
        #expect(oneX.apply(to: origin).x == 101)
    }

    @Test func togglingShiftMidDragDoesNotJump() {
        var drag = FineDrag(backingScale: 2, start: .zero)
        drag.drag(to: CGPoint(x: 10, y: 0), fine: false)
        drag.drag(to: CGPoint(x: 20, y: 0), fine: true)
        #expect(approx(drag.translation.dx, 11, 1e-9))
        drag.drag(to: CGPoint(x: 25, y: 0), fine: false)
        #expect(approx(drag.translation.dx, 16, 1e-9))
    }

    @Test func firstLocationWithoutAStartOnlyRecordsIt() {
        var drag = FineDrag(backingScale: 1)
        drag.drag(to: CGPoint(x: 500, y: 500), fine: false)
        #expect(drag.translation == .zero)
        #expect(drag.lastLocation == CGPoint(x: 500, y: 500))
        drag.drag(to: CGPoint(x: 504, y: 500), fine: false)
        #expect(drag.translation == CGVector(dx: 4, dy: 0))

        drag.begin(at: CGPoint(x: 0, y: 0))
        #expect(drag.translation == .zero)
    }

    @Test func movedSnapsTheOriginAndKeepsTheSize() {
        var drag = FineDrag(backingScale: 2)
        drag.add(CGVector(dx: 1.2, dy: -0.2), fine: false)
        let moved = drag.moved(CGRect(x: 10.1, y: 0, width: 333.3, height: 120))
        #expect(moved == CGRect(x: 11.5, y: 0, width: 333.3, height: 120))
    }

    @Test func axisAccumulatorForVolumeDrags() {
        var volume = FineDragAxis()
        volume.add(100, fine: false)
        volume.add(100, fine: true)
        #expect(approx(volume.value, 110, 1e-9))
        volume.reset()
        #expect(volume.value == 0)
    }

    @Test func pixelGridSnapsRects() {
        let grid = PixelGrid(scale: 2)
        #expect(grid.pixel == 0.5)
        #expect(grid.snap(CGRect(x: 0.2, y: 0.3, width: 10.1, height: 5)) == CGRect(x: 0, y: 0.5, width: 10.5, height: 5))
        #expect(PixelGrid(scale: 0).scale == 1)
    }
}

@Suite struct KeyboardNudgeTests {
    @Test func onePressIsOneDevicePixel() {
        #expect(KeyboardNudge.offset(.right, largeStep: false, backingScale: 2) == CGVector(dx: 0.5, dy: 0))
        #expect(KeyboardNudge.offset(.left, largeStep: false, backingScale: 1) == CGVector(dx: -1, dy: 0))
    }

    @Test func optionIsTenDevicePixels() {
        #expect(KeyboardNudge.offset(.right, largeStep: true, backingScale: 2) == CGVector(dx: 5, dy: 0))
        #expect(KeyboardNudge.offset(.down, largeStep: true, backingScale: 1) == CGVector(dx: 0, dy: -10))
    }

    @Test func upIsPositiveYAndSizeIsKept() {
        let frame = CGRect(x: 10, y: 10, width: 300, height: 100)
        #expect(KeyboardNudge.nudge(frame, .up, largeStep: false, backingScale: 2) == CGRect(x: 10, y: 10.5, width: 300, height: 100))
    }
}

@Suite struct SnappingTests {
    let display = CGRect(x: 0, y: 0, width: 1920, height: 515)
    let snapper = EdgeSnapper(threshold: 8)

    @Test func snapsToTheDisplayEdge() {
        let result = snapper.snapMove(CGRect(x: 5, y: 300, width: 200, height: 100), display: display, others: [], disabled: false)
        #expect(result.frame == CGRect(x: 0, y: 300, width: 200, height: 100))
        #expect(result.guideX == 0)
        #expect(result.guideY == nil)

        let right = snapper.snapMove(CGRect(x: 1714, y: 300, width: 200, height: 100), display: display, others: [], disabled: false)
        #expect(right.frame.maxX == 1920)
    }

    @Test func snapsBothAxesIndependently() {
        let result = snapper.snapMove(CGRect(x: 1716, y: -6, width: 200, height: 100), display: display, others: [], disabled: false)
        #expect(result.frame == CGRect(x: 1720, y: 0, width: 200, height: 100))
        #expect(result.guideX == 1920 && result.guideY == 0)
    }

    @Test func outsideTheThresholdNothingMoves() {
        let frame = CGRect(x: 9, y: 200, width: 200, height: 100)
        let result = snapper.snapMove(frame, display: display, others: [], disabled: false)
        #expect(result.frame == frame)
        #expect(!result.didSnap)
    }

    @Test func commandDisablesSnapping() {
        let frame = CGRect(x: 2, y: 2, width: 200, height: 100)
        #expect(snapper.snapMove(frame, display: display, others: [], disabled: true).frame == frame)
        #expect(snapper.snapResize(frame, edge: .left, display: display, others: [], disabled: true).frame == frame)
    }

    @Test func abutsAndAlignsWithOtherGroups() {
        let uf8 = CGRect(x: 300, y: 0, width: 1300, height: 120)
        // Moving the UF1 meter so its left edge is 5 pt right of the UF8 group's right edge.
        let abut = snapper.snapMove(CGRect(x: 1605, y: 200, width: 160, height: 120), display: display, others: [uf8], disabled: false)
        #expect(abut.frame.minX == 1600)
        #expect(abut.guideX == 1600)
        // Aligning bottoms with the other group.
        let align = snapper.snapMove(CGRect(x: 900, y: 205, width: 160, height: 120), display: display, others: [CGRect(x: 0, y: 200, width: 10, height: 50)], disabled: false)
        #expect(align.frame.minY == 200)
    }

    @Test func picksTheNearestTarget() {
        let others = [CGRect(x: 103, y: 0, width: 10, height: 10), CGRect(x: 98, y: 0, width: 1, height: 10)]
        // Left edge at 100: 99 (1 away) beats 103 (3 away) and 98 (2 away).
        let result = snapper.snapMove(CGRect(x: 100, y: 200, width: 50, height: 50), display: display, others: others, disabled: false)
        #expect(result.frame.minX == 99)
    }

    @Test func resizeSnapsOnlyTheDraggedEdge() {
        let other = CGRect(x: 1000, y: 0, width: 200, height: 100)
        let right = snapper.snapResize(CGRect(x: 100, y: 0, width: 896, height: 100), edge: .right, display: display, others: [other], disabled: false)
        #expect(right.frame == CGRect(x: 100, y: 0, width: 900, height: 100))
        let left = snapper.snapResize(CGRect(x: 4, y: 0, width: 200, height: 100), edge: .left, display: display, others: [], disabled: false)
        #expect(left.frame == CGRect(x: 0, y: 0, width: 204, height: 100))
        let top = snapper.snapResize(CGRect(x: 0, y: 0, width: 200, height: 510), edge: .top, display: display, others: [], disabled: false)
        #expect(top.frame.height == 515)
    }

    @Test func resizeSnapNeverCollapsesTheFrame() {
        let thin = CGRect(x: 100, y: 0, width: 4, height: 100)
        let result = snapper.snapResize(thin, edge: .right, display: display, others: [CGRect(x: 98, y: 300, width: 1, height: 1)], disabled: false)
        #expect(result.frame.width > 0)
    }
}

@Suite struct GroupGeometryTests {
    let display = CGRect(x: 0, y: 0, width: 1920, height: 515)

    @Test func clampMovesAGroupBackOnScreen() {
        #expect(GroupGeometry.clamp(CGRect(x: -50, y: -10, width: 300, height: 100), to: display) == CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(GroupGeometry.clamp(CGRect(x: 1800, y: 450, width: 300, height: 100), to: display) == CGRect(x: 1620, y: 415, width: 300, height: 100))
        let inside = CGRect(x: 10, y: 10, width: 300, height: 100)
        #expect(GroupGeometry.clamp(inside, to: display) == inside)
    }

    @Test func clampShrinksOnlyWhenLargerThanTheDisplay() {
        #expect(GroupGeometry.clamp(CGRect(x: -100, y: 0, width: 2500, height: 600), to: display) == display)
    }

    @Test func groupClampKeepsEverythingElse() {
        let group = StripGroup(name: "UF8", binding: .surfaceUnit(index: 0, firstStrip: 0), stripCount: 8, frame: CGRect(x: -20, y: 0, width: 800, height: 100))
        let clamped = group.clamped(to: display)
        #expect(clamped.frame.minX == 0)
        #expect(clamped.id == group.id && clamped.stripCount == 8)
    }

    @Test func resizeRespectsTheMinimumSize() {
        let frame = CGRect(x: 100, y: 0, width: 400, height: 100)
        let minimum = CGSize(width: 48, height: 24)
        #expect(GroupGeometry.resize(frame, edge: .right, by: 50, minimumSize: minimum) == CGRect(x: 100, y: 0, width: 450, height: 100))
        #expect(GroupGeometry.resize(frame, edge: .left, by: -30, minimumSize: minimum) == CGRect(x: 70, y: 0, width: 430, height: 100))
        #expect(GroupGeometry.resize(frame, edge: .left, by: 1000, minimumSize: minimum) == CGRect(x: 452, y: 0, width: 48, height: 100))
        #expect(GroupGeometry.resize(frame, edge: .top, by: -500, minimumSize: minimum) == CGRect(x: 100, y: 0, width: 400, height: 24))
        #expect(GroupGeometry.resize(frame, edge: .bottom, by: 10, minimumSize: minimum) == CGRect(x: 100, y: 10, width: 400, height: 90))
    }

    @Test func minimumSizeScalesWithStrips() {
        let group = StripGroup(name: "x", binding: .trackList(offset: 0), stripCount: 4, frame: .zero)
        #expect(group.minimumSize == CGSize(width: 4 * StripGroup.minimumStripWidth, height: StripGroup.minimumHeight))
    }
}
