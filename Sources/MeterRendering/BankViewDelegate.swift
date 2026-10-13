import AppKit
import MeterCore

/// Receives the control gestures of a `BankView`. All methods have empty default implementations.
///
/// Strip indexes are positions in the bank (0 = leftmost); the app maps them to tracks. Gestures on empty
/// strips are not reported, except context-menu requests. Nothing is reported while the bank is in edit mode.
@MainActor
public protocol BankViewDelegate: AnyObject {
    /// The name pill was clicked, or the meter was clicked without dragging.
    func bankView(_ bankView: BankView, didSelectStrip index: Int)

    /// An S, M or R button was pressed (on mouse-down). `modifiers` are the device-independent flags,
    /// so the app can map ⌘-click on S to additive solo.
    func bankView(_ bankView: BankView, didPress button: StripButton, onStrip index: Int, modifiers: NSEvent.ModifierFlags)

    /// A volume drag moved the value (normalized 0...1). Sent continuously while dragging, only when the
    /// value changes. `track` is the track the strip showed at mouse-down: send the volume to it, not to
    /// whatever the strip shows now.
    func bankView(_ bankView: BankView, didDragVolume value: Double, track: TrackID?, onStrip index: Int)

    /// A volume drag ended at `value`, on mouse-up or because the strip changed track (`track` is the
    /// grabbed track, as for `didDragVolume`).
    func bankView(_ bankView: BankView, didEndVolumeDrag value: Double, track: TrackID?, onStrip index: Int)

    /// The meter was double-clicked or the peak readout clicked: reset peak hold, clip and readout.
    func bankView(_ bankView: BankView, didRequestPeakResetOnStrip index: Int)

    /// Right-click or Control-click on a strip. Use `event` with `NSMenu.popUpContextMenu(_:with:for:)`.
    func bankView(_ bankView: BankView, didRequestContextMenuForStrip index: Int, event: NSEvent)
}

extension BankViewDelegate {
    public func bankView(_ bankView: BankView, didSelectStrip index: Int) {}
    public func bankView(_ bankView: BankView, didPress button: StripButton, onStrip index: Int, modifiers: NSEvent.ModifierFlags) {}
    public func bankView(_ bankView: BankView, didDragVolume value: Double, track: TrackID?, onStrip index: Int) {}
    public func bankView(_ bankView: BankView, didEndVolumeDrag value: Double, track: TrackID?, onStrip index: Int) {}
    public func bankView(_ bankView: BankView, didRequestPeakResetOnStrip index: Int) {}
    public func bankView(_ bankView: BankView, didRequestContextMenuForStrip index: Int, event: NSEvent) {}
}
