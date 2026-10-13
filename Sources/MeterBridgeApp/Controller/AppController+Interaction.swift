import AppKit
import MeterCore
import MeterRendering

// Bank gestures to DAW commands.
extension AppController: BankViewDelegate {
    func bankView(_ bankView: BankView, didSelectStrip index: Int) {
        guard let id = bankView.state(ofStrip: index).trackID else { return }
        send(.select(id))
    }

    func bankView(_ bankView: BankView, didPress button: StripButton, onStrip index: Int, modifiers: NSEvent.ModifierFlags) {
        guard let id = bankView.state(ofStrip: index).trackID, let track = snapshot.track(id) else { return }
        switch button {
        case .solo:
            // ⌘-click adds to the soloed tracks; a plain click follows Live's Exclusive Solo preference.
            send(.setSolo(id, !track.isSoloed, exclusive: modifiers.contains(.command) ? false : nil))
        case .mute:
            send(.setMute(id, !track.isMuted))
        case .arm:
            send(.setArm(id, !(track.isArmed ?? false)))
        }
    }

    // Volume drags go to the track grabbed at mouse-down (`track`), never to whatever the strip shows now:
    // a bank change or a new selection mid-drag must not move another fader.
    func bankView(_ bankView: BankView, didDragVolume value: Double, track: TrackID?, onStrip index: Int) {
        guard let id = track else { return }
        keepAwake(for: 0.7)
        send(.setVolume(id, value))
    }

    func bankView(_ bankView: BankView, didEndVolumeDrag value: Double, track: TrackID?, onStrip index: Int) {
        guard let id = track else { return }
        // The bank holds the dragged value for up to 0.5 s until the DAW echoes it; keep drawing.
        keepAwake(for: 0.7)
        // Sent at once with "end": true (docs/PROTOCOL.md, `vol`), so Live closes the drag's gesture and
        // undo step now instead of after its 0.5 s timeout.
        send(.endVolumeDrag(id, value))
    }

    func bankView(_ bankView: BankView, didRequestPeakResetOnStrip index: Int) {
        guard let id = bankView.state(ofStrip: index).trackID else { return }
        store.resetPeaks(for: id)
        keepAwake(for: 0.1)
    }

    func bankView(_ bankView: BankView, didRequestContextMenuForStrip index: Int, event: NSEvent) {
        let track = bankView.state(ofStrip: index).trackID.flatMap { snapshot.track($0) }
        let menu = StripContextMenu.make(for: track, controller: self)
        NSMenu.popUpContextMenu(menu, with: event, for: bankView)
    }
}
