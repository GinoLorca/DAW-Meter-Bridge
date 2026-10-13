import AppKit
import MeterCore

// Mouse gestures of a BankView: select, S/M/R, volume drag with Shift for fine, double-click peak reset,
// context menu. Edit mode bypasses all of this (see the overrides in BankView).
extension BankView {
    func handleMouseDown(_ event: NSEvent) {
        cancelPress()
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hit(at: point) else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control) {
            delegate?.bankView(self, didRequestContextMenuForStrip: hit.strip, event: event)
            return
        }
        let state = state(ofStrip: hit.strip)
        guard !state.isEmpty else { return }

        switch hit.region {
        case let .button(button):
            guard state.allows(button) else { return }
            delegate?.bankView(self, didPress: button, onStrip: hit.strip, modifiers: modifiers)
        case .name:
            delegate?.bankView(self, didSelectStrip: hit.strip)
        case .readout:
            delegate?.bankView(self, didRequestPeakResetOnStrip: hit.strip)
        case .meter, .fader:
            if event.clickCount >= 2 {
                delegate?.bankView(self, didRequestPeakResetOnStrip: hit.strip)
                return
            }
            let current = volumeOverride.flatMap { $0.strip == hit.strip && $0.trackID == state.trackID ? $0.value : nil }
            press = Press(
                strip: hit.strip,
                trackID: state.trackID,
                drag: VolumeDrag(startValue: current ?? state.volume, startPoint: point, meterHeight: geometry.meterHeight)
            )
        }
    }

    func handleMouseDragged(_ event: NSEvent) {
        guard var current = press else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fine = event.modifierFlags.contains(.shift)
        // NSEvent.deltaY is positive downward and keeps coming while the pointer is pinned at a screen edge.
        let value = current.drag.update(to: point, fine: fine, pointerDeltaUp: -event.deltaY)
        guard let value else {
            press = current
            return
        }
        // Report only real changes: crossing the drag threshold does not move the volume.
        let changed = value != (current.sentValue ?? current.drag.anchorValue)
        if changed { current.sentValue = value }
        press = current

        volumeOverride = VolumeOverride(strip: current.strip, trackID: current.trackID, value: value, releasedAt: nil)
        showDragOverlay(value: value, strip: current.strip)
        redraw()
        if changed {
            delegate?.bankView(self, didDragVolume: value, track: current.trackID, onStrip: current.strip)
        }
    }

    func handleMouseUp(_ event: NSEvent) {
        guard let finished = press else { return }
        press = nil
        if finished.drag.isDragging {
            endDrag(finished)
        } else {
            delegate?.bankView(self, didSelectStrip: finished.strip)
        }
    }

    func handleContextMenu(_ event: NSEvent) {
        cancelPress()
        let point = convert(event.locationInWindow, from: nil)
        guard let index = geometry.stripIndex(atX: point.x), point.y >= 0, point.y <= bounds.height else { return }
        delegate?.bankView(self, didRequestContextMenuForStrip: index, event: event)
    }

    /// Ends any press in progress; a running drag is reported as ended at its current value, for the
    /// track it grabbed.
    func cancelPress() {
        guard let pending = press else { return }
        press = nil
        if pending.drag.isDragging { endDrag(pending) }
    }

    private func endDrag(_ finished: Press) {
        let value = finished.drag.value
        if volumeOverride?.strip == finished.strip {
            volumeOverride?.releasedAt = ProcessInfo.processInfo.systemUptime
        }
        withoutActions { dragOverlay.hide() }
        // A drag that never changed the volume sent nothing, so there is nothing to end.
        guard finished.sentValue != nil else { return }
        delegate?.bankView(self, didEndVolumeDrag: value, track: finished.trackID, onStrip: finished.strip)
    }

    private func showDragOverlay(value: Double, strip index: Int) {
        let state = state(ofStrip: index)
        let text: String
        if let provider = volumeTextProvider {
            text = provider(value)
        } else if value == state.volume, !state.volumeText.isEmpty {
            text = state.volumeText
        } else {
            text = String(format: "%.0f%%", value * 100)
        }
        let geometry = self.geometry
        guard index < geometry.stripCount else { return }
        let cap = geometry.strip(index).capRect(volume: value)
        withoutActions { dragOverlay.show(text, strip: index, capRect: cap, env: env) }
    }
}
