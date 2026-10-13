import AppKit
import BridgeLayout

/// What one display's edit canvas draws, in display-local points.
struct EditCanvasModel: Equatable {
    struct Group: Equatable {
        var id: UUID
        var frame: CGRect
        /// Group name, shown on a tab above the group.
        var title: String
        /// e.g. "8 strips · Surface unit 1, strips 1–8".
        var detail: String
        var isSelected: Bool
        /// False while the group is being calibrated: its markers' knobs sit where the tab would be.
        var showsTab = true
    }

    /// The floating info box next to the selected group.
    struct HUD: Equatable {
        /// The rect the box keeps clear of (the selected group).
        var anchor: CGRect
        var title: String
        /// Measurements, drawn bright.
        var lines: [String]
        /// Shortcut reminders, drawn dimmer below the lines.
        var hints: [String] = []
    }

    var groups: [Group] = []
    /// Snap guide lines (display-local x and y), while a drag snapped.
    var guideX: CGFloat?
    var guideY: CGFloat?
    var hud: HUD?
    /// A centred note, e.g. when the profile has no groups yet.
    var message: String?
}

/// Where the parts of an `EditCanvasModel` go; shared by drawing and invalidation.
@MainActor
struct EditCanvasLayout {
    static let tabFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let tabDetailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let hudTitleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let hudFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let messageFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    static let tabHeight: CGFloat = 20
    static let hudPadding: CGFloat = 10
    static let hudLineHeight: CGFloat = 15

    var tabs: [UUID: CGRect] = [:]
    var hud: CGRect?
    var message: CGRect?

    init(model: EditCanvasModel, bounds: CGRect) {
        for group in model.groups where group.showsTab {
            let width = Self.tabText(group).size().width + 14
            var tab = CGRect(x: group.frame.minX, y: group.frame.maxY + 3, width: width, height: Self.tabHeight)
            if tab.maxY > bounds.maxY { tab.origin.y = group.frame.maxY - Self.tabHeight - 3 }
            tab.origin.x = min(max(tab.minX, bounds.minX + 2), max(bounds.minX + 2, bounds.maxX - width - 2))
            tabs[group.id] = tab.integral
        }
        if let hud = model.hud {
            let titleWidth = NSAttributedString(string: hud.title, attributes: [.font: Self.hudTitleFont]).size().width
            let lineWidth = (hud.lines + hud.hints).map { NSAttributedString(string: $0, attributes: [.font: Self.hudFont]).size().width }.max() ?? 0
            let size = CGSize(
                width: ceil(max(titleWidth, lineWidth)) + 2 * Self.hudPadding,
                height: CGFloat(hud.lines.count + hud.hints.count + 1) * Self.hudLineHeight + 2 * Self.hudPadding + 2
            )
            let clearance = Self.tabHeight + 10
            var origin = CGPoint(x: hud.anchor.minX, y: hud.anchor.maxY + clearance)
            if origin.y + size.height > bounds.maxY {
                origin.y = hud.anchor.minY - size.height - 10
                if origin.y < bounds.minY { origin.y = max(bounds.minY + 4, bounds.maxY - size.height - 4) }
            }
            origin.x = min(max(origin.x, bounds.minX + 4), max(bounds.minX + 4, bounds.maxX - size.width - 4))
            self.hud = CGRect(origin: origin, size: size).integral
        }
        if let text = model.message {
            let size = NSAttributedString(string: text, attributes: [.font: Self.messageFont]).size()
            let box = CGSize(width: ceil(size.width) + 40, height: ceil(size.height) + 24)
            message = CGRect(x: bounds.midX - box.width / 2, y: bounds.midY - box.height / 2, width: box.width, height: box.height).integral
        }
    }

    static func tabText(_ group: EditCanvasModel.Group) -> NSAttributedString {
        let color: NSColor = group.isSelected ? .black : .white
        let text = NSMutableAttributedString(string: group.title, attributes: [.font: tabFont, .foregroundColor: color])
        if !group.detail.isEmpty {
            text.append(NSAttributedString(string: "  \(group.detail)", attributes: [
                .font: tabDetailFont, .foregroundColor: color.withAlphaComponent(0.75),
            ]))
        }
        return text
    }

    /// Everything the model draws, for invalidation.
    func regions(of model: EditCanvasModel, bounds: CGRect) -> [CGRect] {
        var rects = model.groups.map { $0.frame.insetBy(dx: -6, dy: -6) }
        rects += tabs.values.map { $0.insetBy(dx: -2, dy: -2) }
        if let hud { rects.append(hud.insetBy(dx: -4, dy: -4)) }
        if let message { rects.append(message.insetBy(dx: -4, dy: -4)) }
        if let x = model.guideX { rects.append(CGRect(x: x - 2, y: bounds.minY, width: 4, height: bounds.height)) }
        if let y = model.guideY { rects.append(CGRect(x: bounds.minX, y: y - 2, width: bounds.width, height: 4)) }
        return rects
    }
}

/// Draws the edit-mode decorations of one display: an outline, name tab and edge handles per group, snap
/// guides, the HUD and messages. It never takes mouse events, so clicks reach the group panels below.
final class EditCanvasView: NSView {
    static let accent = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    static let guideColor = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.83, alpha: 0.95)

    private(set) var model = EditCanvasModel()
    private var layout = EditCanvasLayout(model: EditCanvasModel(), bounds: .zero)

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Replaces what is drawn, redrawing only what changed.
    func setModel(_ newModel: EditCanvasModel) {
        guard newModel != model else { return }
        let oldRegions = layout.regions(of: model, bounds: bounds)
        model = newModel
        layout = EditCanvasLayout(model: newModel, bounds: bounds)
        for rect in oldRegions + layout.regions(of: newModel, bounds: bounds) {
            setNeedsDisplay(rect.intersection(bounds))
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layout = EditCanvasLayout(model: model, bounds: bounds)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        let scale = window?.backingScaleFactor ?? 2
        for group in model.groups where !group.isSelected { drawGroup(group, scale: scale) }
        for group in model.groups where group.isSelected { drawGroup(group, scale: scale) }
        drawGuides(scale: scale)
        drawHUD()
        drawMessage()
    }

    // MARK: - Parts

    private func drawGroup(_ group: EditCanvasModel.Group, scale: CGFloat) {
        let pixel = 1 / scale
        let frame = group.frame
        if group.isSelected {
            let outer = NSBezierPath(rect: frame.insetBy(dx: 1, dy: 1))
            outer.lineWidth = 2
            Self.accent.setStroke()
            outer.stroke()
            let inner = NSBezierPath(rect: frame.insetBy(dx: 2 + pixel / 2, dy: 2 + pixel / 2))
            inner.lineWidth = pixel
            NSColor.black.withAlphaComponent(0.6).setStroke()
            inner.stroke()
        } else {
            let path = NSBezierPath(rect: frame.insetBy(dx: pixel / 2 + 0.5, dy: pixel / 2 + 0.5))
            path.lineWidth = 1
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.7).setStroke()
            path.stroke()
        }
        drawHandles(frame, selected: group.isSelected)
        if let tab = layout.tabs[group.id] {
            let background = NSBezierPath(roundedRect: tab, xRadius: 5, yRadius: 5)
            (group.isSelected ? Self.accent : NSColor(white: 0.12, alpha: 0.92)).setFill()
            background.fill()
            let text = EditCanvasLayout.tabText(group)
            let size = text.size()
            text.draw(at: CGPoint(x: tab.minX + 7, y: tab.midY - size.height / 2))
        }
    }

    private func drawHandles(_ frame: CGRect, selected: Bool) {
        let long = min(28, frame.width / 3, frame.height / 3)
        let short: CGFloat = selected ? 5 : 4
        guard long >= 6 else { return }
        let inset: CGFloat = 1.5
        let handles = [
            CGRect(x: frame.minX + inset, y: frame.midY - long / 2, width: short, height: long),
            CGRect(x: frame.maxX - inset - short, y: frame.midY - long / 2, width: short, height: long),
            CGRect(x: frame.midX - long / 2, y: frame.minY + inset, width: long, height: short),
            CGRect(x: frame.midX - long / 2, y: frame.maxY - inset - short, width: long, height: short),
        ]
        for rect in handles {
            let path = NSBezierPath(roundedRect: rect, xRadius: short / 2, yRadius: short / 2)
            NSColor.white.withAlphaComponent(selected ? 1 : 0.55).setFill()
            path.fill()
            if selected {
                path.lineWidth = 1
                Self.accent.setStroke()
                path.stroke()
            }
        }
    }

    private func drawGuides(scale: CGFloat) {
        Self.guideColor.setFill()
        let width = max(1, 1 / scale)
        if let x = model.guideX {
            CGRect(x: x - width / 2, y: bounds.minY, width: width, height: bounds.height).fill()
        }
        if let y = model.guideY {
            CGRect(x: bounds.minX, y: y - width / 2, width: bounds.width, height: width).fill()
        }
    }

    private func drawHUD() {
        guard let hud = model.hud, let box = layout.hud else { return }
        let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor(white: 0.06, alpha: 0.9).setFill()
        path.fill()
        path.lineWidth = 1
        NSColor(white: 1, alpha: 0.22).setStroke()
        path.stroke()
        var y = box.maxY - EditCanvasLayout.hudPadding - EditCanvasLayout.hudLineHeight
        NSAttributedString(string: hud.title, attributes: [.font: EditCanvasLayout.hudTitleFont, .foregroundColor: Self.accent])
            .draw(at: CGPoint(x: box.minX + EditCanvasLayout.hudPadding, y: y))
        y -= 2
        let rows = hud.lines.map { ($0, NSColor.white) } + hud.hints.map { ($0, NSColor(white: 1, alpha: 0.6)) }
        for (line, color) in rows {
            y -= EditCanvasLayout.hudLineHeight
            NSAttributedString(string: line, attributes: [.font: EditCanvasLayout.hudFont, .foregroundColor: color])
                .draw(at: CGPoint(x: box.minX + EditCanvasLayout.hudPadding, y: y))
        }
    }

    private func drawMessage() {
        guard let text = model.message, let box = layout.message else { return }
        let path = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
        NSColor(white: 0.06, alpha: 0.9).setFill()
        path.fill()
        let string = NSAttributedString(string: text, attributes: [.font: EditCanvasLayout.messageFont, .foregroundColor: NSColor.white])
        let size = string.size()
        string.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
    }
}

/// A click-through, transparent window covering one display while editing, above the bridge panels.
final class EditCanvasPanel: NSPanel {
    /// Just above the bridge panels (`.statusBar`).
    static let canvasLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    let canvasView: EditCanvasView

    init(frame: CGRect) {
        canvasView = EditCanvasView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Self.canvasLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        title = "DAW Meter Bridge Edit Guides"
        contentView = canvasView
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Covers `frame` (a display's global frame).
    func cover(_ frame: CGRect) {
        guard self.frame != frame else { return }
        setFrame(frame, display: true)
    }
}
