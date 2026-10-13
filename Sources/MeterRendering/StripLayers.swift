import AppKit
import MeterCore

/// What a strip last drew. Frames compare against it and touch only layers whose value changed.
private struct DrawnState {
    var isEmpty: Bool?
    var isStereo: Bool?
    var name: String?
    /// `MeterCore.RGBColor.hex`, -1 for no colour, -2 for unknown.
    var colorKey = -2
    var focus: StripFocus?
    /// Bit k set when button k is allowed; -1 for unknown.
    var buttonMask = -1
    var lit = [-1, -1]
    var peak = [-2, -2]
    /// 0 off, 1 on, -1 unknown.
    var clip = [-1, -1]
    var readoutValue: Float = -1
    var readoutText: String?
    var readoutZone = -2
    var volume: Double = -1
}

/// The Core Animation layers of one strip, from the peak readout at the top to the S/M/R buttons at the bottom.
///
/// `layout` places everything for a geometry (rare); `apply` pushes one frame's state (every display frame)
/// and only mutates layers whose drawn value changed. Callers wrap both in a transaction with actions disabled.
@MainActor
final class StripLayers {
    let container = CALayer()

    private let env: RenderEnvironment
    private var geometry: StripGeometry?
    private var drawn = DrawnState()
    /// Columns in use (two for stereo, one for mono), strip-local.
    private var activeColumns: [CGRect] = []
    private var nameTextRect = CGRect.zero
    /// How many times a text layer's string was set (tests check frames leave text alone).
    private(set) var textWrites = 0

    private let content = CALayer()
    private let emptyOutline = CALayer()
    private let selectionFill = CALayer()
    private let readoutBox = CALayer()
    private let readoutText = TextLayout.makeLayer()
    private let clipLEDs = [CALayer(), CALayer()]
    private let unlitColumns = [CALayer(), CALayer()]
    private let litClips = [CALayer(), CALayer()]
    private let litColumns = [CALayer(), CALayer()]
    private let peakClips = [CALayer(), CALayer()]
    private let peakColumns = [CALayer(), CALayer()]
    private let rail = CALayer()
    private let cap = CALayer()
    private let capLine = CALayer()
    private let pill = CALayer()
    private let nameText = TextLayout.makeLayer()
    private let dim = CALayer()
    private let buttons = [CALayer(), CALayer(), CALayer()]
    private let buttonLabels = [TextLayout.makeLayer(), TextLayout.makeLayer(), TextLayout.makeLayer()]
    private let selectionOutline = CALayer()
    private let pillOutline = CALayer()

    init(environment: RenderEnvironment) {
        env = environment
        container.addSublayer(emptyOutline)
        container.addSublayer(content)

        var stack: [CALayer] = [selectionFill, readoutBox, readoutText]
        stack += clipLEDs + unlitColumns + litClips + peakClips
        stack += [rail, cap, pill, nameText, dim]
        stack += buttons
        stack += [selectionOutline, pillOutline]
        stack.forEach(content.addSublayer)

        for i in 0..<2 {
            litClips[i].masksToBounds = true
            litClips[i].addSublayer(litColumns[i])
            peakClips[i].masksToBounds = true
            peakClips[i].addSublayer(peakColumns[i])
        }
        cap.addSublayer(capLine)
        for (k, button) in StripButton.allCases.enumerated() {
            buttons[k].addSublayer(buttonLabels[k])
            buttonLabels[k].string = button.label
        }
        emptyOutline.isHidden = true
    }

    private var allLayers: [CALayer] {
        [container, content, emptyOutline, selectionFill, readoutBox, readoutText, rail, cap, capLine, pill, nameText,
         dim, selectionOutline, pillOutline]
            + clipLEDs + unlitColumns + litClips + litColumns + peakClips + peakColumns + buttons + buttonLabels
    }

    // MARK: - Layout

    /// Places every layer for a new geometry and forgets what was drawn, so the next `apply` redraws all of it.
    func layout(_ g: StripGeometry) {
        geometry = g
        let s = env.scale
        let u = g.unit
        let palette = env.palette
        let fonts = env.fonts
        func px(_ v: CGFloat) -> CGFloat { max(1 / s, pixelAligned(v, scale: s)) }

        for layer in allLayers { layer.contentsScale = s }
        content.frame = g.bounds

        let outlineRadius = 0.32 * u
        emptyOutline.frame = g.outline
        emptyOutline.cornerRadius = outlineRadius
        emptyOutline.borderWidth = px(0.06 * u)
        emptyOutline.borderColor = palette.emptyOutline

        selectionFill.frame = g.outline
        selectionFill.cornerRadius = outlineRadius
        selectionFill.backgroundColor = palette.selectionFill

        let ring = px(max(1.5, 0.09 * u))
        selectionOutline.frame = g.outline
        selectionOutline.cornerRadius = outlineRadius
        selectionOutline.borderWidth = ring
        selectionOutline.borderColor = palette.selectionStroke
        selectionOutline.shadowColor = palette.selectionGlow
        selectionOutline.shadowOpacity = 0.9
        selectionOutline.shadowRadius = 0.32 * u
        selectionOutline.shadowOffset = .zero
        selectionOutline.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: g.outline.size).insetBy(dx: ring / 2, dy: ring / 2),
            cornerWidth: outlineRadius, cornerHeight: outlineRadius, transform: nil
        ).copy(strokingWithWidth: ring, lineCap: .butt, lineJoin: .round, miterLimit: 4)

        if let box = g.readout {
            readoutBox.isHidden = false
            readoutText.isHidden = false
            readoutBox.frame = box
            readoutBox.cornerRadius = 0.22 * u
            readoutBox.backgroundColor = palette.readoutBox
            TextLayout.apply(fonts.readout, to: readoutText)
            readoutText.frame = TextLayout.frame(for: fonts.readout, centeredIn: box.insetBy(dx: 0.1 * u, dy: 0), scale: s)
        } else {
            readoutBox.isHidden = true
            readoutText.isHidden = true
        }

        if let railRect = g.rail {
            rail.isHidden = false
            cap.isHidden = false
            rail.frame = railRect
            rail.cornerRadius = railRect.width / 2
            rail.backgroundColor = palette.rail
            cap.bounds = CGRect(origin: .zero, size: g.capSize)
            cap.cornerRadius = min(0.12 * u, g.capSize.height / 3)
            cap.backgroundColor = palette.capFill
            let line = 1 / s
            capLine.frame = CGRect(x: 0, y: pixelAligned(g.capSize.height / 2 - line / 2, scale: s), width: g.capSize.width, height: line)
            capLine.backgroundColor = palette.capLine
        } else {
            rail.isHidden = true
            cap.isHidden = true
        }

        if let pillRect = g.name {
            pill.isHidden = false
            nameText.isHidden = false
            pill.frame = pillRect
            pill.cornerRadius = pillRect.height / 2
            nameTextRect = pillRect.insetBy(dx: pillRect.height * 0.45, dy: 0)
            let gap = px(0.08 * u)
            let outer = pillRect.insetBy(dx: -(ring + gap), dy: -(ring + gap))
            pillOutline.frame = outer
            pillOutline.cornerRadius = outer.height / 2
            pillOutline.borderWidth = ring
            pillOutline.borderColor = palette.selectionStroke
        } else {
            pill.isHidden = true
            nameText.isHidden = true
        }

        // Dimming covers everything above the button row, so a lit M stays readable on a muted strip.
        var dimBottom: CGFloat = 0
        if let first = g.buttons.first {
            dimBottom = g.name.map { (first.maxY + $0.minY) / 2 } ?? first.maxY
        }
        dim.frame = CGRect(x: 0, y: pixelAligned(dimBottom, scale: s), width: g.bounds.width, height: g.bounds.height - pixelAligned(dimBottom, scale: s))
        dim.backgroundColor = palette.background

        for (k, rect) in g.buttons.enumerated() {
            buttons[k].frame = rect
            buttons[k].cornerRadius = min(0.2 * u, rect.height / 3)
            buttons[k].borderColor = palette.mutedViaSoloStroke
            TextLayout.apply(fonts.button, to: buttonLabels[k])
            buttonLabels[k].frame = TextLayout.frame(for: fonts.button, centeredIn: CGRect(origin: .zero, size: rect.size), scale: s)
        }
        if g.buttons.isEmpty { buttons.forEach { $0.isHidden = true } }

        drawn = DrawnState()
        layoutColumns(stereo: true)
    }

    /// Places the meter columns and clip LEDs for stereo (two columns) or mono (one wide column).
    private func layoutColumns(stereo: Bool) {
        guard let g = geometry else { return }
        let art = stereo ? env.stereoArt : env.monoArt
        activeColumns = stereo ? g.columns : [g.monoColumn]
        let clipRects: [CGRect] = stereo ? g.clipLEDs : (g.monoClipLED.map { [$0] } ?? [])
        for i in 0..<2 {
            let visible = i < activeColumns.count
            unlitColumns[i].isHidden = !visible
            litClips[i].isHidden = !visible
            peakClips[i].isHidden = true
            clipLEDs[i].isHidden = !(visible && i < clipRects.count)
            guard visible else { continue }
            let column = activeColumns[i]
            let local = CGRect(origin: .zero, size: column.size)
            unlitColumns[i].frame = column
            unlitColumns[i].contents = art?.unlit
            litClips[i].frame = CGRect(x: column.minX, y: column.minY, width: column.width, height: 0)
            litColumns[i].frame = local
            litColumns[i].contents = art?.lit
            peakColumns[i].frame = local
            peakColumns[i].contents = art?.lit
            if i < clipRects.count {
                clipLEDs[i].frame = clipRects[i]
                clipLEDs[i].cornerRadius = min(clipRects[i].height / 2, 1.5)
            }
        }
        drawn.isStereo = stereo
        drawn.lit = [-1, -1]
        drawn.peak = [-2, -2]
        drawn.clip = [-1, -1]
    }

    // MARK: - Frames

    /// Forgets the drawn readout so the next frame re-formats it (calibration changed).
    func invalidateReadout() {
        drawn.readoutValue = -1
        drawn.readoutText = nil
        drawn.readoutZone = -2
    }

    /// Pushes one frame. `volumeOverride` replaces the state's volume while the user drags this strip.
    func apply(_ state: StripRenderState, volumeOverride: Double?) {
        guard let g = geometry else { return }
        if drawn.isEmpty != state.isEmpty {
            content.isHidden = state.isEmpty
            emptyOutline.isHidden = !state.isEmpty
            drawn.isEmpty = state.isEmpty
        }
        guard !state.isEmpty else { return }

        if drawn.isStereo != state.isStereo { layoutColumns(stereo: state.isStereo) }
        if drawn.name != state.name { applyName(state.name) }
        let colorKey = state.color?.hex ?? -1
        if drawn.colorKey != colorKey { applyColor(state.color, key: colorKey) }
        let mask = buttonMask(state)
        if drawn.focus != state.focus || drawn.buttonMask != mask { applyFocus(state, mask: mask, geometry: g) }

        applyMeter(state.meter, stereo: state.isStereo, geometry: g)
        if !readoutText.isHidden { applyReadout(state.meter.maxSinceReset) }

        let volume = volumeOverride ?? state.volume
        if drawn.volume != volume, g.rail != nil {
            cap.frame = g.capRect(volume: volume)
            drawn.volume = volume
        }
    }

    private func applyName(_ name: String) {
        drawn.name = name
        nameText.string = name
        textWrites += 1
        let base = env.fonts.name
        let size = TextLayout.fittingSize(for: name, font: base, width: nameTextRect.width, minimum: env.fonts.minNameSize)
        let font = size == base.pointSize ? base : (NSFont(descriptor: base.fontDescriptor, size: size) ?? base)
        TextLayout.apply(font, to: nameText)
        nameText.frame = TextLayout.frame(for: font, centeredIn: nameTextRect, scale: env.scale)
    }

    private func applyColor(_ color: MeterCore.RGBColor?, key: Int) {
        drawn.colorKey = key
        let palette = env.palette
        if let color {
            pill.backgroundColor = .srgb(color)
            nameText.foregroundColor = color.prefersDarkText ? palette.darkText : palette.lightText
        } else {
            pill.backgroundColor = palette.pillNeutral
            nameText.foregroundColor = palette.lightText
        }
    }

    private func buttonMask(_ state: StripRenderState) -> Int {
        var mask = 0
        for button in StripButton.allCases where state.allows(button) { mask |= 1 << button.rawValue }
        return mask
    }

    private func applyFocus(_ state: StripRenderState, mask: Int, geometry g: StripGeometry) {
        drawn.focus = state.focus
        drawn.buttonMask = mask
        let focus = state.focus
        let palette = env.palette

        selectionFill.isHidden = !focus.isSelected
        selectionOutline.isHidden = !focus.isSelected
        pillOutline.isHidden = !focus.isSelected || g.name == nil

        let amount = min(max(focus.dim.isFinite ? focus.dim : 0, 0), 0.92)
        dim.isHidden = amount < 0.001
        dim.opacity = Float(amount)

        guard !g.buttons.isEmpty else { return }
        let ring = max(1 / env.scale, pixelAligned(0.07 * g.unit, scale: env.scale))
        for button in StripButton.allCases {
            let layer = buttons[button.rawValue]
            let allowed = mask & (1 << button.rawValue) != 0
            layer.isHidden = !allowed
            guard allowed else { continue }
            let lit = state.isLit(button)
            layer.backgroundColor = lit ? palette.buttonOn(button) : palette.buttonOff
            buttonLabels[button.rawValue].foregroundColor = lit ? palette.buttonOnText(button) : palette.buttonOffText
            // Solo-implied mute: a hollow amber M, like Live's.
            layer.borderWidth = (button == .mute && !lit && focus.isMutedViaSolo) ? ring : 0
        }
    }

    private func applyMeter(_ meter: StripMeterState, stereo: Bool, geometry g: StripGeometry) {
        if stereo {
            applyColumn(0, level: meter.left.bar, peak: meter.left.peak, clipped: meter.left.clipped)
            applyColumn(1, level: meter.right.bar, peak: meter.right.peak, clipped: meter.right.clipped)
        } else {
            applyColumn(
                0, level: max(meter.left.bar, meter.right.bar),
                peak: max(meter.left.peak, meter.right.peak), clipped: meter.clipped
            )
        }
    }

    private func applyColumn(_ i: Int, level: Float, peak: Float, clipped: Bool) {
        guard i < activeColumns.count else { return }
        let style = env.style
        let bank = env.geometry
        let column = activeColumns[i]

        let lit = style.litSegments(for: level)
        if drawn.lit[i] != lit {
            drawn.lit[i] = lit
            litClips[i].frame = CGRect(x: column.minX, y: column.minY, width: column.width, height: bank.litHeight(segments: lit))
        }

        let peakSegment = style.litSegments(for: peak) - 1
        let shownPeak = (peakSegment >= lit && peakSegment >= 0 && peakSegment < bank.segments.count) ? peakSegment : -1
        if drawn.peak[i] != shownPeak {
            drawn.peak[i] = shownPeak
            if shownPeak < 0 {
                peakClips[i].isHidden = true
            } else {
                let span = bank.segments[shownPeak]
                peakClips[i].frame = CGRect(x: column.minX, y: column.minY + span.bottom, width: column.width, height: span.height)
                peakColumns[i].frame = CGRect(x: 0, y: -span.bottom, width: column.width, height: column.height)
                peakClips[i].isHidden = false
            }
        }

        let clip = clipped ? 1 : 0
        if drawn.clip[i] != clip {
            drawn.clip[i] = clip
            clipLEDs[i].backgroundColor = clipped ? env.palette.clipOn : env.palette.clipOff
        }
    }

    private func applyReadout(_ value: Float) {
        guard drawn.readoutValue != value else { return }
        drawn.readoutValue = value
        let text = env.readoutText(for: value)
        if drawn.readoutText != text {
            drawn.readoutText = text
            readoutText.string = text
            textWrites += 1
        }
        let zone = env.calibration.decibels(for: value) == nil ? -1 : env.style.zone(for: value).rawValue
        if drawn.readoutZone != zone {
            drawn.readoutZone = zone
            readoutText.foregroundColor = zone < 0 ? env.palette.readoutSilent : env.palette.readoutText[zone]
        }
    }
}
