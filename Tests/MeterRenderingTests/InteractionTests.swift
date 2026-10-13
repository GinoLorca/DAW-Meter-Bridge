import AppKit
import MeterCore
@testable import MeterRendering
import Testing

/// Records every delegate call.
@MainActor
final class RecordingDelegate: BankViewDelegate {
    enum Call: Equatable {
        case select(Int)
        case press(StripButton, Int, NSEvent.ModifierFlags)
        case drag(Double, Int, TrackID?)
        case endDrag(Double, Int, TrackID?)
        case resetPeaks(Int)
        case contextMenu(Int)
    }

    var calls: [Call] = []

    func bankView(_ bankView: BankView, didSelectStrip index: Int) { calls.append(.select(index)) }
    func bankView(_ bankView: BankView, didPress button: StripButton, onStrip index: Int, modifiers: NSEvent.ModifierFlags) {
        calls.append(.press(button, index, modifiers))
    }
    func bankView(_ bankView: BankView, didDragVolume value: Double, track: TrackID?, onStrip index: Int) {
        calls.append(.drag(value, index, track))
    }
    func bankView(_ bankView: BankView, didEndVolumeDrag value: Double, track: TrackID?, onStrip index: Int) {
        calls.append(.endDrag(value, index, track))
    }
    func bankView(_ bankView: BankView, didRequestPeakResetOnStrip index: Int) { calls.append(.resetPeaks(index)) }
    func bankView(_ bankView: BankView, didRequestContextMenuForStrip index: Int, event: NSEvent) { calls.append(.contextMenu(index)) }
}

/// Mouse gestures on a window-less BankView, driven with synthesized events.
@MainActor
@Suite struct InteractionTests {
    let view: BankView
    let delegate = RecordingDelegate()
    let geometry: BankGeometry

    init() {
        view = BankView(frame: CGRect(x: 0, y: 0, width: 1920, height: 515), stripCount: 8)
        view.fixedScale = 1
        var strips = demoSession()
        strips[7] = .empty
        view.update(strips: strips)
        view.delegate = delegate
        geometry = view.geometry
    }

    private func at(_ strip: Int, _ local: CGPoint) -> CGPoint {
        CGPoint(x: geometry.stripFrames[strip].minX + local.x, y: local.y)
    }

    private func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
        )!
    }

    private func click(_ point: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) {
        view.mouseDown(with: event(.leftMouseDown, point, flags: flags, clicks: clicks))
        view.mouseUp(with: event(.leftMouseUp, point, flags: flags, clicks: clicks))
    }

    /// Presses at `start` and moves up just past the drag threshold; returns where the drag is anchored.
    private func beginDrag(at start: CGPoint) -> CGPoint {
        view.mouseDown(with: event(.leftMouseDown, start))
        let anchor = CGPoint(x: start.x, y: start.y + VolumeDrag.startThreshold)
        view.mouseDragged(with: event(.leftMouseDragged, anchor))
        return anchor
    }

    @Test func acceptsFirstMouse() {
        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test func clickOnNameSelects() throws {
        let name = try #require(geometry.strip(2).name)
        click(at(2, CGPoint(x: name.midX, y: name.midY)))
        #expect(delegate.calls == [.select(2)])
    }

    @Test func clickOnMeterWithoutDragSelects() {
        let meter = geometry.strip(4).meter
        click(at(4, CGPoint(x: meter.midX, y: meter.midY)))
        #expect(delegate.calls == [.select(4)])
    }

    @Test func buttonsReportPressWithModifiers() {
        let buttons = geometry.strip(0).buttons
        click(at(0, CGPoint(x: buttons[0].midX, y: buttons[0].midY)), flags: .command)
        click(at(0, CGPoint(x: buttons[1].midX, y: buttons[1].midY)))
        click(at(0, CGPoint(x: buttons[2].midX, y: buttons[2].midY)), flags: .option)
        #expect(delegate.calls == [.press(.solo, 0, .command), .press(.mute, 0, []), .press(.arm, 0, .option)])
    }

    @Test func unavailableButtonsAreIgnored() {
        // Strip 6 is a return track: no R.
        let arm = geometry.strip(6).buttons[2]
        click(at(6, CGPoint(x: arm.midX, y: arm.midY)))
        #expect(delegate.calls.isEmpty)
    }

    @Test func verticalDragSetsVolumeAfterThreshold() throws {
        let strip = geometry.strip(1)
        let start = at(1, CGPoint(x: strip.meter.midX, y: strip.meter.midY))
        let startVolume = view.state(ofStrip: 1).volume
        view.mouseDown(with: event(.leftMouseDown, start))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 1)))
        #expect(delegate.calls.isEmpty, "1 pt is below the drag threshold")
        let anchor = CGPoint(x: start.x, y: start.y + VolumeDrag.startThreshold)
        view.mouseDragged(with: event(.leftMouseDragged, anchor))
        #expect(delegate.calls.isEmpty, "crossing the threshold does not change the volume")
        #expect(view.dragOverlay.isVisible)

        let up = geometry.meterHeight * 0.05
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: anchor.y + up)))
        guard case let .drag(dragged, 1, track) = try #require(delegate.calls.last) else {
            Issue.record("expected a drag call, got \(delegate.calls)")
            return
        }
        #expect(abs(dragged - (startVolume + 0.05)) < 1e-9)
        #expect(track == TrackID(2))
        #expect(view.dragOverlay.isVisible)

        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: anchor.y + up)))
        guard case let .endDrag(final, 1, TrackID(2)?) = try #require(delegate.calls.last) else {
            Issue.record("expected a drag-ended call, got \(delegate.calls)")
            return
        }
        #expect(abs(final - (startVolume + 0.05)) < 1e-9)
        #expect(!view.dragOverlay.isVisible)
        #expect(!delegate.calls.contains(.select(1)), "a drag is not a click")
    }

    @Test func shiftDragIsFine() throws {
        let strip = geometry.strip(3)
        let start = beginDrag(at: at(3, CGPoint(x: strip.rail!.midX, y: strip.meter.midY)))
        let startVolume = view.state(ofStrip: 3).volume
        let down = geometry.meterHeight * 0.5
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y - down), flags: .shift))
        guard case let .drag(value, 3, _) = try #require(delegate.calls.last) else {
            Issue.record("expected a drag call, got \(delegate.calls)")
            return
        }
        #expect(abs(value - (startVolume - 0.05)) < 1e-9)
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y - down)))
    }

    @Test func dragOverlayUsesTheTextProvider() throws {
        view.volumeTextProvider = { String(format: "%.2f", $0) }
        let strip = geometry.strip(0)
        let start = at(0, CGPoint(x: strip.meter.midX, y: strip.meter.midY))
        view.mouseDown(with: event(.leftMouseDown, start))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y - 40)))
        let image = try #require(view.renderImage())
        writeSnapshot(image, scale: 1, name: "bank-dragging@1x.png")
        #expect(view.dragOverlay.isVisible)
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y - 40)))
    }

    @Test func doubleClickOnMeterResetsPeaks() {
        let meter = geometry.strip(5).meter
        let point = at(5, CGPoint(x: meter.midX, y: meter.midY))
        click(point)
        click(point, clicks: 2)
        #expect(delegate.calls == [.select(5), .resetPeaks(5)])
    }

    @Test func clickOnReadoutResetsPeaks() throws {
        let readout = try #require(geometry.strip(0).readout)
        click(at(0, CGPoint(x: readout.midX, y: readout.midY)))
        #expect(delegate.calls == [.resetPeaks(0)])
    }

    @Test func rightAndControlClickRequestAContextMenu() {
        let meter = geometry.strip(3).meter
        view.rightMouseDown(with: event(.rightMouseDown, at(3, CGPoint(x: meter.midX, y: meter.midY))))
        click(at(2, CGPoint(x: meter.midX, y: meter.midY)), flags: .control)
        view.rightMouseDown(with: event(.rightMouseDown, at(7, CGPoint(x: meter.midX, y: meter.midY))))
        #expect(delegate.calls == [.contextMenu(3), .contextMenu(2), .contextMenu(7)], "empty strips still get a menu")
    }

    @Test func emptyStripsIgnoreGestures() throws {
        let strip = geometry.strip(7)
        let name = try #require(strip.name)
        click(at(7, CGPoint(x: name.midX, y: name.midY)))
        click(at(7, CGPoint(x: strip.buttons[0].midX, y: strip.buttons[0].midY)))
        let start = at(7, CGPoint(x: strip.meter.midX, y: strip.meter.midY))
        view.mouseDown(with: event(.leftMouseDown, start))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 50)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y + 50)))
        #expect(delegate.calls.isEmpty)
    }

    @Test func editModeIgnoresControlGestures() throws {
        view.isEditing = true
        let strip = geometry.strip(1)
        let name = try #require(strip.name)
        click(at(1, CGPoint(x: name.midX, y: name.midY)))
        click(at(1, CGPoint(x: strip.buttons[0].midX, y: strip.buttons[0].midY)))
        let start = at(1, CGPoint(x: strip.meter.midX, y: strip.meter.midY))
        view.mouseDown(with: event(.leftMouseDown, start))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 50)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y + 50)))
        #expect(delegate.calls.isEmpty)
    }

    @Test func enteringEditModeMidDragEndsTheDrag() {
        let strip = geometry.strip(2)
        let start = beginDrag(at: at(2, CGPoint(x: strip.meter.midX, y: strip.meter.midY)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 20)))
        view.isEditing = true
        guard case .endDrag(_, 2, TrackID(3)?) = delegate.calls.last else {
            Issue.record("expected the drag to end, got \(delegate.calls)")
            return
        }
    }

    @Test func capFollowsTheDragBeforeTheDAWEchoes() throws {
        let strip = geometry.strip(0)
        let start = beginDrag(at: at(0, CGPoint(x: strip.meter.midX, y: strip.meter.midY)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y - geometry.meterHeight * 0.4)))
        let image = try #require(view.renderImage())
        let reader = PixelReader(image, scale: 1)
        let target = view.state(ofStrip: 0).volume - 0.4
        let cap = strip.capRect(volume: target)
        let pixel = reader.pixel(at: CGPoint(x: geometry.stripFrames[0].minX + cap.minX + 2, y: cap.midY + 3))
        #expect(pixel.luminance > 150, "the cap is drawn at the dragged value, got \(pixel)")
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y - geometry.meterHeight * 0.4)))
    }

    @Test func clickWobbleBelowTheThresholdStillSelects() {
        let meter = geometry.strip(4).meter
        let point = at(4, CGPoint(x: meter.midX, y: meter.midY))
        view.mouseDown(with: event(.leftMouseDown, point))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: point.x + 1, y: point.y + 3)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: point.x + 1, y: point.y + 3)))
        #expect(delegate.calls == [.select(4)])
    }

    @Test func aDragThatNeverChangesTheVolumeSendsNothing() {
        let meter = geometry.strip(4).meter
        let anchor = beginDrag(at: at(4, CGPoint(x: meter.midX, y: meter.midY)))
        view.mouseUp(with: event(.leftMouseUp, anchor))
        #expect(delegate.calls.isEmpty, "no volume, no end, and no select: it was a drag")
    }

    @Test func aDragStaysWithTheGrabbedTrackAndEndsWhenTheStripChangesTrack() throws {
        let strip = geometry.strip(1)
        let start = beginDrag(at: at(1, CGPoint(x: strip.meter.midX, y: strip.meter.midY)))
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 20)))
        guard case let .drag(value, 1, TrackID(2)?) = try #require(delegate.calls.last) else {
            Issue.record("expected a drag of track 2, got \(delegate.calls)")
            return
        }

        // The hardware banks: strip 1 now shows another track. The drag ends for the grabbed track.
        var banked = demoSession()
        banked[1] = makeStrip(42, "Banked In", volume: 0.3)
        view.update(strips: banked)
        #expect(delegate.calls.last == .endDrag(value, 1, TrackID(2)))
        #expect(!view.dragOverlay.isVisible)

        // The rest of the gesture does nothing: no volume for track 42, no select.
        let count = delegate.calls.count
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 60)))
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y + 60)))
        #expect(delegate.calls.count == count)
        #expect(!delegate.calls.contains { call in
            if case .drag(_, _, TrackID(42)?) = call { return true }
            if case .endDrag(_, _, TrackID(42)?) = call { return true }
            return false
        })
    }

    @Test func refreshingTheSameTrackKeepsTheDrag() throws {
        let strip = geometry.strip(1)
        let start = beginDrag(at: at(1, CGPoint(x: strip.meter.midX, y: strip.meter.midY)))
        view.update(strips: demoSession().enumerated().map { $0.offset == 7 ? .empty : $0.element })
        view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x, y: start.y + 20)))
        guard case .drag(_, 1, TrackID(2)?) = try #require(delegate.calls.last) else {
            Issue.record("expected the drag to continue, got \(delegate.calls)")
            return
        }
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x, y: start.y + 20)))
    }
}
