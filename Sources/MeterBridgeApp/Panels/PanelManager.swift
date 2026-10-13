import AppKit
import MeterCore
import MeterRendering

/// Keeps one `GroupPanelController` per placed strip group, reusing panels across layout changes.
@MainActor
final class PanelManager {
    /// Panels in placement order.
    private(set) var controllers: [GroupPanelController] = []
    /// Whether panels are ordered in (Show/Hide Bridge).
    private(set) var isVisible = false
    /// Edit mode on every panel.
    private(set) var isEditing = false
    /// Edit-mode receiver of panel events (installed on every panel while editing).
    weak var eventHandler: (any GroupPanelEventHandler)? {
        didSet { controllers.forEach { $0.hostView.eventHandler = isEditing ? eventHandler : nil } }
    }

    private weak var renderer: (any GroupPanelRenderer)?
    private weak var bankDelegate: (any BankViewDelegate)?
    private var style: MeterStyle
    private var calibration: MeterCalibration

    init(renderer: any GroupPanelRenderer, bankDelegate: any BankViewDelegate, style: MeterStyle, calibration: MeterCalibration) {
        self.renderer = renderer
        self.bankDelegate = bankDelegate
        self.style = style
        self.calibration = calibration
    }

    /// Creates, moves and closes panels so there is exactly one per placement.
    func apply(_ placements: [GroupPlacement]) {
        guard let renderer, let bankDelegate else { return }
        var existing: [UUID: GroupPanelController] = [:]
        for controller in controllers {
            if existing[controller.groupID] == nil {
                existing[controller.groupID] = controller
            } else {
                controller.close()
            }
        }
        var result: [GroupPanelController] = []
        var placed = Set<UUID>()
        // One panel per group id, even if a hand-edited layouts.json repeats an id.
        for placement in placements where placed.insert(placement.group.id).inserted {
            if let controller = existing.removeValue(forKey: placement.group.id) {
                controller.update(placement)
                result.append(controller)
            } else {
                let controller = GroupPanelController(
                    placement: placement,
                    style: style,
                    calibration: calibration,
                    renderer: renderer,
                    bankDelegate: bankDelegate
                )
                controller.isEditing = isEditing
                controller.hostView.eventHandler = isEditing ? eventHandler : nil
                result.append(controller)
            }
        }
        existing.values.forEach { $0.close() }
        controllers = result
        if isVisible { controllers.forEach { $0.show() } }
    }

    /// Shows or hides every panel (and runs or stops their display links).
    func setVisible(_ visible: Bool) {
        isVisible = visible
        controllers.forEach { visible ? $0.show() : $0.hide() }
    }

    /// Turns edit mode on or off for every panel.
    func setEditing(_ editing: Bool) {
        isEditing = editing
        for controller in controllers {
            controller.isEditing = editing
            controller.hostView.eventHandler = editing ? eventHandler : nil
        }
    }

    /// Applies a new meter style to every bank.
    func setStyle(_ newStyle: MeterStyle) {
        style = newStyle
        controllers.forEach { $0.bankView.style = newStyle }
    }

    /// Applies a new meter calibration to every bank.
    func setCalibration(_ newCalibration: MeterCalibration) {
        calibration = newCalibration
        controllers.forEach { $0.bankView.calibration = newCalibration }
    }

    /// Resumes idle display links.
    func wakeAll() {
        controllers.forEach { $0.wake() }
    }

    /// The panel showing `bankView`.
    func controller(for bankView: BankView) -> GroupPanelController? {
        controllers.first { $0.bankView === bankView }
    }

    /// The panel showing the group with `id`.
    func controller(forGroup id: UUID) -> GroupPanelController? {
        controllers.first { $0.groupID == id }
    }

    /// Closes every panel.
    func closeAll() {
        controllers.forEach { $0.close() }
        controllers = []
    }
}
