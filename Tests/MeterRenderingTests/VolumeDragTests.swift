import CoreGraphics
@testable import MeterRendering
import Testing

/// Volume drag math: full-range drags, Shift for fine, threshold and clamping.
@Suite struct VolumeDragTests {
    private func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func fullMeterHeightMovesTheFullRange() {
        #expect(isClose(VolumeDrag.value(startValue: 0, upwardDistance: 300, meterHeight: 300, fine: false), 1))
        #expect(isClose(VolumeDrag.value(startValue: 0.5, upwardDistance: 30, meterHeight: 300, fine: false), 0.6))
        #expect(isClose(VolumeDrag.value(startValue: 0.5, upwardDistance: -60, meterHeight: 300, fine: false), 0.3))
    }

    @Test func shiftIsTenTimesFiner() {
        #expect(isClose(VolumeDrag.value(startValue: 0.5, upwardDistance: 30, meterHeight: 300, fine: true), 0.51))
        #expect(isClose(VolumeDrag.value(startValue: 0.5, upwardDistance: -300, meterHeight: 300, fine: true), 0.4))
    }

    @Test func valueIsClamped() {
        #expect(VolumeDrag.value(startValue: 0.9, upwardDistance: 300, meterHeight: 300, fine: false) == 1)
        #expect(VolumeDrag.value(startValue: 0.1, upwardDistance: -300, meterHeight: 300, fine: false) == 0)
        #expect(VolumeDrag.value(startValue: 0.5, upwardDistance: 10, meterHeight: 0, fine: false) == 0.5)
    }

    @Test func nothingHappensUntilTheThresholdAndTheDragStartsThere() {
        #expect(VolumeDrag.startThreshold == 4)
        var drag = VolumeDrag(startValue: 0.5, startPoint: CGPoint(x: 100, y: 100), meterHeight: 200)
        #expect(drag.update(to: CGPoint(x: 100, y: 103.5), fine: false) == nil)
        #expect(drag.update(to: CGPoint(x: 140, y: 103.5), fine: false) == nil, "horizontal movement alone never starts a drag")
        #expect(!drag.isDragging)
        // Crossing the threshold starts the drag without moving the volume: click wobble is not a fader move.
        let value = drag.update(to: CGPoint(x: 100, y: 104), fine: false)
        #expect(drag.isDragging)
        #expect(value == 0.5)
        // From there on it tracks: 20 pt up on a 200 pt meter is +0.1.
        let moved = drag.update(to: CGPoint(x: 100, y: 124), fine: false)
        #expect(moved.map { isClose($0, 0.6) } == true)
    }

    @Test func dragDownLowersTheVolume() {
        var drag = VolumeDrag(startValue: 0.85, startPoint: CGPoint(x: 0, y: 200), meterHeight: 400)
        #expect(drag.update(to: CGPoint(x: 0, y: 196), fine: false) == 0.85)
        let value = drag.update(to: CGPoint(x: 0, y: 96), fine: false)
        #expect(value.map { isClose($0, 0.6) } == true)
    }

    @Test func pressingShiftMidDragReanchorsWithoutAJump() throws {
        var drag = VolumeDrag(startValue: 0.5, startPoint: CGPoint(x: 0, y: 0), meterHeight: 100)
        _ = drag.update(to: CGPoint(x: 0, y: 4), fine: false)
        _ = drag.update(to: CGPoint(x: 0, y: 14), fine: false)
        #expect(isClose(drag.value, 0.6))
        // Shift goes down at the same spot: the value must not move.
        let same = drag.update(to: CGPoint(x: 0, y: 14), fine: true)
        #expect(isClose(try #require(same), 0.6))
        // Then 10 pt more with Shift adds a tenth of 0.1.
        let fine = drag.update(to: CGPoint(x: 0, y: 24), fine: true)
        #expect(isClose(try #require(fine), 0.61))
        // Releasing Shift re-anchors again.
        let coarse = drag.update(to: CGPoint(x: 0, y: 34), fine: false)
        #expect(isClose(try #require(coarse), 0.71))
    }

    @Test func pointerPinnedAtTheScreenEdgeKeepsDraggingWithDeviceDeltas() throws {
        // The bridge sits on the bottom edge: the pointer stops at y 0 but the mouse keeps reporting movement.
        var drag = VolumeDrag(startValue: 0.5, startPoint: CGPoint(x: 0, y: 4), meterHeight: 100)
        #expect(drag.update(to: CGPoint(x: 0, y: 0), fine: false, pointerDeltaUp: -4) == 0.5)
        let first = drag.update(to: CGPoint(x: 0, y: 0), fine: false, pointerDeltaUp: -10)
        #expect(isClose(try #require(first), 0.4))
        let second = drag.update(to: CGPoint(x: 0, y: 0), fine: false, pointerDeltaUp: -10)
        #expect(isClose(try #require(second), 0.3))
        // Synthesized events without a device delta use the position, which did not move.
        let still = drag.update(to: CGPoint(x: 0, y: 0), fine: false)
        #expect(isClose(try #require(still), 0.3))
        // Fine (Shift) works at the edge too.
        let fine = drag.update(to: CGPoint(x: 0, y: 0), fine: true, pointerDeltaUp: -50)
        #expect(isClose(try #require(fine), 0.25))
    }

    @Test func thePositionIsUsedWheneverThePointerMoves() throws {
        // Device deltas may differ from the pointer's movement (acceleration, units): a pointer that
        // moves is followed exactly.
        var drag = VolumeDrag(startValue: 0.5, startPoint: .zero, meterHeight: 100)
        _ = drag.update(to: CGPoint(x: 0, y: 4), fine: false, pointerDeltaUp: 8)
        let up = drag.update(to: CGPoint(x: 0, y: 14), fine: false, pointerDeltaUp: 3)
        #expect(isClose(try #require(up), 0.6))
        let down = drag.update(to: CGPoint(x: 0, y: 4), fine: false, pointerDeltaUp: -25)
        #expect(isClose(try #require(down), 0.5))
    }

    @Test func startValueIsClamped() {
        let drag = VolumeDrag(startValue: 1.4, startPoint: .zero, meterHeight: 100)
        #expect(drag.value == 1)
    }
}
