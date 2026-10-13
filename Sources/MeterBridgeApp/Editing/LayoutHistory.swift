import BridgeLayout
import Foundation

/// Undo and redo of layout changes.
///
/// Every change stores the whole `LayoutDocument` as it was before, so undo puts back exactly what was
/// there, whatever the change touched: a group's frame, its binding, a profile, the active profile.
/// Undo groups are explicit (`groupsByEvent` is off), so changes made outside an event (menu actions,
/// timers, the scripted `--demo-edit` run) each get their own step.
@MainActor
final class LayoutHistory {
    /// Changes with the same coalescing key this close together become one undo step (held arrow keys).
    static let coalesceWindow: TimeInterval = 1.5

    let undoManager: UndoManager
    private var coalescing: (key: String, until: TimeInterval)?

    init(levels: Int = 200) {
        undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = levels
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }
    var undoActionName: String { undoManager.undoActionName }
    var redoActionName: String { undoManager.redoActionName }

    /// Records a change from `before`; undoing it calls `restore(before)`.
    ///
    /// When `coalesceKey` matches the previous change's key within `coalesceWindow`, nothing new is
    /// recorded, so undo goes back to before the first of those changes.
    func record(
        _ actionName: String,
        before: LayoutDocument,
        coalesceKey: String? = nil,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        restore: @escaping @MainActor (LayoutDocument) -> Void
    ) {
        if let key = coalesceKey, let current = coalescing, current.key == key, now <= current.until, undoManager.canUndo {
            coalescing = (key, now + Self.coalesceWindow)
            return
        }
        coalescing = coalesceKey.map { ($0, now + Self.coalesceWindow) }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { _ in restore(before) }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    /// Called from inside a `restore` while undoing or redoing: registers the opposite step (`restore(current)`).
    func registerInverse(_ actionName: String, current: LayoutDocument, restore: @escaping @MainActor (LayoutDocument) -> Void) {
        coalescing = nil
        undoManager.registerUndo(withTarget: self) { _ in restore(current) }
        undoManager.setActionName(actionName)
    }

    func undo() {
        coalescing = nil
        if undoManager.canUndo { undoManager.undo() }
    }

    func redo() {
        coalescing = nil
        if undoManager.canRedo { undoManager.redo() }
    }

    /// Stops the next change from joining the previous one (e.g. when the selection changes).
    func breakCoalescing() {
        coalescing = nil
    }

    func removeAll() {
        coalescing = nil
        undoManager.removeAllActions()
    }
}
