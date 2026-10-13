import AppKit

/// Content view of a `BridgePanel`: holds the group's `BankView` and, in edit mode, receives the mouse
/// and key events that the bank view passes up the responder chain.
///
/// Outside edit mode `eventHandler` is nil and events behave as usual (the bank view handles them).
final class GroupHostView: NSView {
    /// The panel controller this view belongs to.
    weak var controller: GroupPanelController?
    /// Edit-mode receiver of mouse and key events; nil outside edit mode.
    weak var eventHandler: (any GroupPanelEventHandler)?

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { eventHandler != nil }

    override func mouseDown(with event: NSEvent) {
        if let eventHandler, let controller {
            eventHandler.groupPanel(controller, mouseDown: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let eventHandler, let controller {
            eventHandler.groupPanel(controller, mouseDragged: event)
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let eventHandler, let controller {
            eventHandler.groupPanel(controller, mouseUp: event)
        } else {
            super.mouseUp(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let eventHandler, let controller {
            eventHandler.groupPanel(controller, rightMouseDown: event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if let eventHandler, let controller {
            eventHandler.groupPanel(controller, mouseMoved: event)
        } else {
            super.mouseMoved(with: event)
        }
    }

    /// ⌘-keys (⌘Z, ⇧⌘Z) arrive here first while the panel is key; the editor gets them before AppKit.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let eventHandler, let controller, window?.isKeyWindow == true,
           event.modifierFlags.contains(.command),
           eventHandler.groupPanel(controller, keyDown: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let eventHandler, let controller, eventHandler.groupPanel(controller, keyDown: event) { return }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if let eventHandler, let controller {
            eventHandler.groupPanel(controller, flagsChanged: event)
        }
        super.flagsChanged(with: event)
    }
}
