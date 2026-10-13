import AppKit

/// A borderless, non-activating panel holding one strip group.
///
/// - Level just below the Dock (`GroupPanelController.level(for:)`), or `.statusBar` where it sits over the
///   menu-bar area of a short bar display.
/// - In every Space and beside full-screen apps; never hidden by "Hide Others" or deactivation.
/// - Clicks never activate the app, so Live keeps keyboard focus. The panel becomes key only while
///   `allowsKey` is set (edit mode, for arrow-key nudges).
final class BridgePanel: NSPanel {
    /// Whether the panel may become key; set while editing the layout.
    var allowsKey = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        title = "DAW Meter Bridge"
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Never pushed below the menu bar or back onto the screen: the layout decides the frame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
