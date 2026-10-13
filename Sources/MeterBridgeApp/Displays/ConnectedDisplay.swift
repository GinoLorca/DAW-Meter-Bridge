import AppKit
import BridgeLayout

/// A display connected now, as the layout code sees it.
struct ConnectedDisplay: Equatable, Sendable {
    /// CoreGraphics display id; changes across reconnects, so layouts key on `fingerprint` instead.
    var displayID: CGDirectDisplayID
    var fingerprint: DisplayFingerprint
    /// Frame in global AppKit coordinates (points, origin at the bottom-left of the main display).
    var frame: CGRect
    /// Device pixels per point.
    var backingScale: CGFloat
    /// Physical size reported by EDID (`CGDisplayScreenSize`), in millimetres; zero when unknown.
    var physicalSizeMillimeters: CGSize
    /// Points per millimetre from EDID when the reported size is plausible, else nil.
    var pointsPerMillimeter: Double?
    /// The display with the menu bar.
    var isMain: Bool

    var name: String { fingerprint.name }

    /// The display's bounds in display-local points (origin at its bottom-left).
    var localBounds: CGRect { CGRect(origin: .zero, size: frame.size) }

    /// A display-local rect in global coordinates.
    func globalRect(fromLocal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// A global rect in display-local coordinates.
    func localRect(fromGlobal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    /// The NSScreen for this display, if it is still connected.
    @MainActor var screen: NSScreen? {
        NSScreen.screens.first { DisplayManager.displayID(of: $0) == displayID }
    }

    /// Height of a Dock that stays visible along the display's bottom edge (0 when the Dock is hidden,
    /// on another side or on another display).
    @MainActor var bottomDockInset: CGFloat {
        guard let screen else { return 0 }
        return max(0, screen.visibleFrame.minY - screen.frame.minY)
    }

    /// Short description for menus, e.g. "LG HDR WQHD (2560 × 1067 pt)".
    var menuTitle: String {
        "\(name.isEmpty ? "Display \(displayID)" : name) (\(Int(frame.width)) × \(Int(frame.height)) pt)"
    }
}
