import AppKit
import BridgeLayout
import MeterCore

// The seam between the app shell and the edit-mode UI.
//
// The shell owns edit mode's on/off state (menu item and ⌃⌥⌘E), turns the banks' guides on, lets panels
// become key, and routes each panel's mouse and key events to the installed `LayoutEditor`. The editor
// owns everything else: selection, moving/resizing with snapping and Shift-fine, nudges, calibration,
// and any overlay views (add them as subviews of `GroupPanelController.hostView`, above `bankView`).
//
// Geometry: a group's `frame` is display-local (origin at its display's bottom-left);
// `GroupPlacement.globalFrame` / `ConnectedDisplay.globalRect(fromLocal:)` give global AppKit
// coordinates. The panel is that frame rounded outward to whole points, and `bankView.frame` is the
// group's exact frame inside `hostView` (see `GroupPanelController.frames(for:)`).
//
// Install an editor in AppDelegate: `controller.layoutEditor = MyLayoutEditor()` (the app installs
// `LayoutEditorController`, see Editing/).

/// Receives a panel's mouse and key events while edit mode is on. All methods have empty defaults.
///
/// In edit mode `BankView` passes its mouse events up the responder chain to the panel's
/// `GroupHostView`, which forwards them here. Locations are in window coordinates
/// (`event.locationInWindow`); convert with `panel.hostView.convert(_:from: nil)`, or use
/// `NSEvent.mouseLocation` for global screen coordinates while dragging across panels.
@MainActor
protocol GroupPanelEventHandler: AnyObject {
    func groupPanel(_ panel: GroupPanelController, mouseDown event: NSEvent)
    func groupPanel(_ panel: GroupPanelController, mouseDragged event: NSEvent)
    func groupPanel(_ panel: GroupPanelController, mouseUp event: NSEvent)
    func groupPanel(_ panel: GroupPanelController, rightMouseDown event: NSEvent)
    /// Only delivered when the panel's `acceptsMouseMovedEvents` is on (the editor turns it on if it needs hover).
    func groupPanel(_ panel: GroupPanelController, mouseMoved event: NSEvent)
    /// Return true when the key was handled. Keys arrive only while the panel is key; call
    /// `panel.panel.makeKey()` (allowed in edit mode, and it does not activate the app).
    func groupPanel(_ panel: GroupPanelController, keyDown event: NSEvent) -> Bool
    func groupPanel(_ panel: GroupPanelController, flagsChanged event: NSEvent)
}

extension GroupPanelEventHandler {
    func groupPanel(_ panel: GroupPanelController, mouseDown event: NSEvent) {}
    func groupPanel(_ panel: GroupPanelController, mouseDragged event: NSEvent) {}
    func groupPanel(_ panel: GroupPanelController, mouseUp event: NSEvent) {}
    func groupPanel(_ panel: GroupPanelController, rightMouseDown event: NSEvent) {}
    func groupPanel(_ panel: GroupPanelController, mouseMoved event: NSEvent) {}
    func groupPanel(_ panel: GroupPanelController, keyDown event: NSEvent) -> Bool { false }
    func groupPanel(_ panel: GroupPanelController, flagsChanged event: NSEvent) {}
}

/// What the edit-mode UI can read and change. Implemented by `AppController`.
@MainActor
protocol LayoutEditHost: AnyObject {
    /// Panels on screen now, one per visible group on a connected display (or on the main display
    /// as a stand-in, see `GroupPlacement.isFallback`).
    var groupPanels: [GroupPanelController] { get }
    /// Displays connected now, main display first.
    var connectedDisplays: [ConnectedDisplay] { get }
    /// The whole layouts document (all profiles).
    var layoutDocument: LayoutDocument { get }
    /// The profile being shown and edited.
    var activeProfile: LayoutProfile? { get }
    /// Current DAW state, e.g. to label groups with their tracks.
    var currentSnapshot: BridgeSnapshot { get }

    /// Live update while dragging: replaces the group (matched by id) in the active profile in memory
    /// and moves/resizes its panel at once. Nothing is saved; call `saveLayouts()` when the gesture ends.
    /// Setting `isVisible` to false removes the panel; a group shown on a stand-in display is first
    /// moved there for good (its frame is relative to the display it is shown on).
    func previewGroup(_ group: StripGroup)
    /// Replaces the active profile (e.g. after a calibration, adding or removing groups) and re-lays out
    /// the panels. Saves layouts.json when `save` is true.
    func updateActiveProfile(_ profile: LayoutProfile, save: Bool)
    /// Saves layouts.json now.
    func saveLayouts()
    /// Leaves edit mode, like the menu item and ⌃⌥⌘E. Saves the layout.
    func finishEditing()
    /// The panel showing the group with `id`.
    func panel(forGroup id: UUID) -> GroupPanelController?

    /// Undo and redo of layout changes (⌘Z / ⇧⌘Z while editing, and the menu).
    var layoutHistory: LayoutHistory { get }
    /// Starts an edit gesture (a drag, a key press): remembers the document so `endLayoutGesture` records
    /// everything `previewGroup` changed in between as one undo step.
    func beginLayoutGesture()
    /// Ends the gesture: records one undo step (joined with the previous one when `coalesceKey` matches,
    /// see `LayoutHistory`) and saves shortly after. Does nothing if nothing changed.
    func endLayoutGesture(_ actionName: String, coalesceKey: String?)
    /// Ends the gesture by putting back the document as it was when it began.
    func cancelLayoutGesture()
    /// Changes the layouts document as one undo step, re-places the panels and saves shortly after.
    /// Returns false (and records nothing) if the change changed nothing.
    @discardableResult
    func performLayoutChange(_ actionName: String, coalesceKey: String?, _ change: (inout LayoutDocument) -> Void) -> Bool
    /// The active profile as it is on screen: a layout shown on a stand-in display (its own display isn't
    /// connected) is moved to that display, so group frames match what the user sees. Not saved by itself.
    func activeProfileMatchingScreen() -> LayoutProfile?
    /// Where new groups and profiles go when nothing else decides: the bridge's display, else the main display.
    var preferredDisplay: ConnectedDisplay? { get }
}

extension LayoutEditHost {
    /// `performLayoutChange` without coalescing.
    @discardableResult
    func performLayoutChange(_ actionName: String, _ change: (inout LayoutDocument) -> Void) -> Bool {
        performLayoutChange(actionName, coalesceKey: nil, change)
    }

    /// Replaces the active profile (made screen-matching first, see `activeProfileMatchingScreen()`) as one
    /// undo step. `change` returns false to cancel.
    @discardableResult
    func performProfileChange(_ actionName: String, coalesceKey: String? = nil, _ change: (inout LayoutProfile) -> Bool) -> Bool {
        guard var profile = activeProfileMatchingScreen(), change(&profile) else { return false }
        return performLayoutChange(actionName, coalesceKey: coalesceKey) { $0.upsert(profile) }
    }
}

/// The edit-mode UI. The shell calls `beginEditing` and `endEditing` around edit mode, and
/// `panelsDidChange` whenever panels were rebuilt (display change, profile switch, profile update).
@MainActor
protocol LayoutEditor: GroupPanelEventHandler {
    func beginEditing(host: any LayoutEditHost)
    func panelsDidChange(host: any LayoutEditHost)
    func endEditing(host: any LayoutEditHost)
    /// Extra items for the menu-bar menu while editing (e.g. "Calibrate…"), placed under "Edit Layout".
    func menuItems(host: any LayoutEditHost) -> [NSMenuItem]
}

extension LayoutEditor {
    func panelsDidChange(host: any LayoutEditHost) {}
    func menuItems(host: any LayoutEditHost) -> [NSMenuItem] { [] }
}
