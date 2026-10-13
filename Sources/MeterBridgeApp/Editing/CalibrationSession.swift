import AppKit
import BridgeLayout
import Carbon.HIToolbox

/// "Calibrate…": two draggable markers over a group. The user drags marker 1 onto the centre of the first
/// fader and marker 2 onto the last (Shift = ×0.1 fine), then Apply sets the group's frame with
/// `StripGroup.calibrated(firstCenterX:lastCenterX:)`.
///
/// While it runs, a band across the group's display (the group's height plus room for the markers'
/// knobs and the instructions) takes the mouse and, unless told otherwise, the keyboard.
@MainActor
final class CalibrationSession {
    private(set) var model: CalibrationModel
    let display: ConnectedDisplay
    /// The band, in display-local points.
    let band: CGRect
    /// True when the instructions sit above the group (else below it).
    let infoAbove: Bool
    private(set) var panel: CalibrationPanel?
    /// Global pointer location (the editor's provider, replaced in `--demo-edit`).
    var pointerLocation: () -> CGPoint
    /// Called once with `true` (Apply) or `false` (Cancel).
    var onFinish: ((CalibrationSession, Bool) -> Void)?

    private var drag: (marker: Int, startX: CGFloat, axis: FineDragAxis, lastPointerX: CGFloat)?
    private var isFinished = false

    var groupID: UUID { model.group.id }

    init(group: StripGroup, display: ConnectedDisplay, pointerLocation: @escaping () -> CGPoint) {
        model = CalibrationModel(group: group)
        self.display = display
        self.pointerLocation = pointerLocation
        (band, infoAbove) = Self.band(for: group.frame, display: display.localBounds)
    }

    /// The interactive band: the group's height plus 120 pt for knobs and instructions above it (or below,
    /// when there's no room above), across the whole display width.
    nonisolated static func band(for group: CGRect, display: CGRect) -> (CGRect, Bool) {
        let room: CGFloat = 124, margin: CGFloat = 30
        if group.maxY + room <= display.maxY {
            let minY = max(display.minY, group.minY - margin)
            return (CGRect(x: display.minX, y: minY, width: display.width, height: group.maxY + room - minY), true)
        }
        let minY = max(display.minY, group.minY - room)
        let maxY = min(display.maxY, group.maxY + margin)
        return (CGRect(x: display.minX, y: minY, width: display.width, height: max(1, maxY - minY)), false)
    }

    /// Shows the band; `makeKey` gives it the keyboard (arrows, Tab, Return, Esc).
    func show(makeKey: Bool) {
        let panel = CalibrationPanel(frame: display.globalRect(fromLocal: band), session: self)
        self.panel = panel
        panel.orderFrontRegardless()
        if makeKey {
            panel.makeKey()
            panel.makeFirstResponder(panel.calibrationView)
        }
        panel.calibrationView.needsDisplay = true
    }

    func close() {
        panel?.calibrationView.session = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    // MARK: - Pointer

    private var pointerX: CGFloat { pointerLocation().x - display.frame.minX }

    private var grid: PixelGrid { PixelGrid(scale: display.backingScale) }

    /// Picks the marker nearest the pointer; a press away from it moves it there first.
    func mouseDown() {
        let x = clampX(pointerX)
        let index = model.nearestMarker(to: x)
        if abs(model.markers[index] - x) > 10 { model.setMarker(index, to: grid.snap(x)) }
        model.activeMarker = index
        drag = (index, model.markers[index], FineDragAxis(), x)
        redraw()
    }

    /// Moves the picked marker; with Shift it moves a tenth as far.
    func mouseDragged(fine: Bool) {
        guard var current = drag else { return }
        let x = pointerX
        current.axis.add(Double(x - current.lastPointerX), fine: fine)
        current.lastPointerX = x
        drag = current
        model.setMarker(current.marker, to: clampX(grid.snap(current.startX + CGFloat(current.axis.value))))
        redraw()
    }

    func mouseUp() {
        drag = nil
    }

    // MARK: - Keys

    /// ←/→ move the active marker 1 px (⌥: 10 px), Tab switches markers, Return applies, Esc cancels.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.shift, .option, .command, .control])
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_RightArrow:
            let step = grid.pixel * (flags.contains(.option) ? KeyboardNudge.largeStepPixels : 1)
            let sign: CGFloat = Int(event.keyCode) == kVK_LeftArrow ? -1 : 1
            let index = model.activeMarker
            model.setMarker(index, to: clampX(model.markers[index] + sign * step))
            redraw()
            return true
        case kVK_Tab:
            model.activeMarker = (model.activeMarker + 1) % model.markers.count
            redraw()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            apply()
            return true
        case kVK_Escape:
            cancel()
            return true
        default:
            return false
        }
    }

    // MARK: - Finishing

    /// Applies when the markers give a valid frame; otherwise beeps and keeps going.
    func apply() {
        guard !isFinished else { return }
        guard model.previewFrame != nil else {
            NSSound.beep()
            return
        }
        isFinished = true
        onFinish?(self, true)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        onFinish?(self, false)
    }

    /// Sets a marker directly (display-local x), e.g. from the scripted `--demo-edit` run.
    func setMarker(_ index: Int, to x: CGFloat) {
        model.setMarker(index, to: clampX(x))
        redraw()
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        min(max(x, display.localBounds.minX), display.localBounds.maxX)
    }

    private func redraw() {
        panel?.calibrationView.needsDisplay = true
    }
}

/// The band window of a calibration: takes mouse events (and keys) over its whole frame.
final class CalibrationPanel: NSPanel {
    static let calibrationLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

    let calibrationView: CalibrationView

    init(frame: CGRect, session: CalibrationSession) {
        calibrationView = CalibrationView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        calibrationView.session = session
        level = Self.calibrationLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        title = "DAW Meter Bridge Calibration"
        contentView = calibrationView
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A button that acts on the first click, without the panel having to become key first.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Draws a calibration's markers, the strip centres they imply and the instructions.
final class CalibrationView: NSView {
    weak var session: CalibrationSession? {
        didSet {
            positionButtons()
            needsDisplay = true
        }
    }

    static let markerColors = [
        NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.83, blue: 1.0, alpha: 1),
    ]
    static let infoSize = CGSize(width: 640, height: 82)

    private let applyButton = FirstMouseButton(title: "Apply", target: nil, action: nil)
    private let cancelButton = FirstMouseButton(title: "Cancel", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        for button in [cancelButton, applyButton] {
            button.bezelStyle = .push
            button.controlSize = .regular
            button.target = self
            addSubview(button)
        }
        applyButton.action = #selector(applyPressed)
        applyButton.keyEquivalent = "\r"
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CalibrationView is created in code")
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func applyPressed() { session?.apply() }
    @objc private func cancelPressed() { session?.cancel() }

    override func mouseDown(with event: NSEvent) { session?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { session?.mouseDragged(fine: event.modifierFlags.contains(.shift)) }
    override func mouseUp(with event: NSEvent) { session?.mouseUp() }

    override func keyDown(with event: NSEvent) {
        if session?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    /// The group's rect in this view's coordinates.
    private func local(_ rect: CGRect, band: CGRect) -> CGRect {
        rect.offsetBy(dx: -band.minX, dy: -band.minY)
    }

    /// Where the instructions box goes, in view coordinates.
    func infoBox(groupRect: CGRect, infoAbove: Bool) -> CGRect {
        let size = Self.infoSize
        let x = min(max(groupRect.midX - size.width / 2, 8), max(8, bounds.width - size.width - 8))
        let y = infoAbove ? groupRect.maxY + 40 : groupRect.minY - 40 - size.height
        return CGRect(x: x, y: min(max(y, 2), max(2, bounds.height - size.height - 2)), width: size.width, height: size.height).integral
    }

    override func layout() {
        super.layout()
        positionButtons()
    }

    private func positionButtons() {
        guard let session else { return }
        let groupRect = local(session.model.group.frame, band: session.band)
        let box = infoBox(groupRect: groupRect, infoAbove: session.infoAbove)
        let buttonSize = CGSize(width: 84, height: 28)
        applyButton.frame = CGRect(x: box.maxX - buttonSize.width - 10, y: box.minY + 8, width: buttonSize.width, height: buttonSize.height)
        cancelButton.frame = CGRect(x: box.maxX - buttonSize.width - 10, y: box.minY + 8 + buttonSize.height + 2, width: buttonSize.width, height: buttonSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        guard let session else { return }
        let model = session.model
        let scale = window?.backingScaleFactor ?? 2
        let pixel = 1 / scale
        let groupRect = local(model.group.frame, band: session.band)

        // A faint tint shows the band takes the mouse.
        NSColor(white: 0, alpha: 0.14).setFill()
        bounds.fill(using: .sourceOver)

        // Where the strips would go.
        if let preview = model.previewFrame {
            let rect = local(preview, band: session.band)
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            outline.stroke()
            NSColor.white.withAlphaComponent(0.5).setFill()
            for center in model.previewCenters {
                let x = center - session.band.minX
                CGRect(x: x - pixel / 2, y: rect.minY, width: max(pixel, 1), height: rect.height).fill()
            }
        }

        // Markers.
        let knobY = session.infoAbove ? groupRect.maxY + 18 : groupRect.minY - 18
        for (index, markerX) in model.markers.enumerated() {
            let x = markerX - session.band.minX
            let color = Self.markerColors[index % Self.markerColors.count]
            let active = index == model.activeMarker
            color.setFill()
            let lineWidth: CGFloat = active ? 2 : 1.5
            let lineMin = min(groupRect.minY - 8, knobY)
            let lineMax = max(groupRect.maxY + 8, knobY)
            CGRect(x: x - lineWidth / 2, y: max(0, lineMin), width: lineWidth, height: lineMax - max(0, lineMin)).fill()
            let radius: CGFloat = active ? 12 : 10
            let knob = NSBezierPath(ovalIn: CGRect(x: x - radius, y: knobY - radius, width: radius * 2, height: radius * 2))
            knob.fill()
            if active {
                knob.lineWidth = 2
                NSColor.white.setStroke()
                knob.stroke()
            }
            let label = NSAttributedString(string: "\(model.stripNumber(ofMarker: index))", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.black,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: x - size.width / 2, y: knobY - size.height / 2))
        }

        // Instructions.
        let box = infoBox(groupRect: groupRect, infoAbove: session.infoAbove)
        let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor(white: 0.06, alpha: 0.92).setFill()
        path.fill()
        let lines = Self.instructions(for: model)
        var y = box.maxY - 10
        for (index, line) in lines.enumerated() {
            let font = index == 0 ? NSFont.systemFont(ofSize: 12, weight: .semibold) : NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            let color: NSColor = index == 0 ? Self.markerColors[0] : (line.hasPrefix("!") ? .systemRed : .white)
            let text = NSAttributedString(string: line.hasPrefix("!") ? String(line.dropFirst()) : line, attributes: [.font: font, .foregroundColor: color])
            y -= text.size().height + 2
            text.draw(at: CGPoint(x: box.minX + 10, y: y))
        }
    }

    /// The box's text: a heading, how to use it, and what the markers measure now. A leading "!" marks a
    /// line to draw as a warning.
    nonisolated static func instructions(for model: CalibrationModel) -> [String] {
        let count = model.group.stripCount
        var lines = [
            "Calibrate “\(model.group.name)”",
            count > 1
                ? "Drag marker 1 onto the centre of fader 1 and marker \(count) onto fader \(count). Shift: fine (×0.1)."
                : "Drag the marker onto the centre of the fader. Shift: fine (×0.1).",
            "←→ move the selected marker 1 px (⌥ 10 px) · Tab switches · Return applies · Esc cancels",
        ]
        if model.previewFrame == nil {
            lines.append("!Marker 1 must be left of marker \(count), at least \(Int(StripCalibration.minimumPitch)) pt per strip apart.")
        } else if let pitch = model.pitch {
            var text = String(format: "Pitch %.2f pt", Double(pitch))
            if let physical = model.group.physicalPitchMillimeters, let scale = model.pointsPerMillimeter {
                text += String(format: " = %.1f mm → %.3f pt/mm", physical, scale)
            }
            lines.append(text)
        } else {
            lines.append(String(format: "Centre x %.1f pt", Double(model.firstCenterX)))
        }
        return lines
    }
}
