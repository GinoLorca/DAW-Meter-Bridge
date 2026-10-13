import AppKit

/// Edit-mode guides: a line through each strip centre (line it up with the physical fader),
/// faint strip boundaries and strip numbers.
@MainActor
final class EditGuides {
    let container = CALayer()
    private var centerLines: [CALayer] = []
    private var boundaries: [CALayer] = []
    private var numbers: [CATextLayer] = []

    init() {
        container.isHidden = true
    }

    /// Creates one set of guide layers per strip.
    func setStripCount(_ count: Int) {
        (centerLines + boundaries + numbers).forEach { $0.removeFromSuperlayer() }
        centerLines = (0..<count).map { _ in CALayer() }
        boundaries = (0..<max(count - 1, 0)).map { _ in CALayer() }
        numbers = (0..<count).map { index in
            let label = TextLayout.makeLayer()
            label.string = "\(index + 1)"
            return label
        }
        (boundaries + centerLines + numbers).forEach(container.addSublayer)
    }

    func layout(_ env: RenderEnvironment) {
        let bank = env.geometry
        let s = bank.scale
        let line = max(1 / s, pixelAligned(0.06 * bank.unit, scale: s))
        container.frame = CGRect(origin: .zero, size: bank.size)
        container.contentsScale = s
        let font = env.fonts.label
        for (i, frame) in bank.stripFrames.enumerated() where i < centerLines.count {
            let strip = bank.strip(i)
            let x = frame.minX + strip.centerX
            centerLines[i].frame = CGRect(x: pixelAligned(x - line / 2, scale: s), y: 0, width: line, height: bank.size.height)
            centerLines[i].backgroundColor = env.palette.guide
            centerLines[i].contentsScale = s

            let labelBox = CGRect(x: x - 1.6 * bank.unit, y: bank.size.height - 1.6 * bank.unit, width: 3.2 * bank.unit, height: 1.3 * bank.unit)
            numbers[i].contentsScale = s
            TextLayout.apply(font, to: numbers[i])
            numbers[i].frame = TextLayout.frame(for: font, centeredIn: labelBox, scale: s)
            numbers[i].foregroundColor = env.palette.guideText
            numbers[i].backgroundColor = env.palette.background
            numbers[i].cornerRadius = 0.2 * bank.unit

            if i < boundaries.count {
                boundaries[i].frame = CGRect(x: frame.maxX - 1 / s, y: 0, width: 1 / s, height: bank.size.height)
                boundaries[i].backgroundColor = env.palette.guideFaint
                boundaries[i].contentsScale = s
            }
        }
    }
}

/// The small box showing the volume while a meter is dragged.
@MainActor
final class DragOverlay {
    let container = CALayer()
    private let label = TextLayout.makeLayer()
    private var shownText: String?

    init() {
        container.isHidden = true
        container.addSublayer(label)
    }

    /// Shows `text` above the fader cap of strip `index` (or below it when there is no room above).
    func show(_ text: String, strip index: Int, capRect: CGRect, env: RenderEnvironment) {
        let bank = env.geometry
        guard index < bank.stripFrames.count else { return }
        let s = bank.scale
        let u = bank.unit
        let font = env.fonts.label
        let stripFrame = bank.stripFrames[index]
        let strip = bank.strip(index)

        let width = TextLayout.width(of: text, font: font) + 1.2 * u
        let height = 1.5 * u
        var x = stripFrame.minX + strip.centerX - width / 2
        x = min(max(x, 2), max(2, bank.size.width - width - 2))
        var y = stripFrame.minY + capRect.maxY + 0.35 * u
        if y + height > bank.size.height - 2 {
            y = stripFrame.minY + capRect.minY - 0.35 * u - height
        }
        let box = CGRect(x: x, y: y, width: width, height: height).pixelAligned(scale: s)

        container.contentsScale = s
        label.contentsScale = s
        container.frame = box
        container.cornerRadius = 0.3 * u
        container.backgroundColor = env.palette.overlayFill
        container.borderColor = env.palette.overlayStroke
        container.borderWidth = 1 / s
        TextLayout.apply(font, to: label)
        label.foregroundColor = env.palette.overlayText
        label.frame = TextLayout.frame(for: font, centeredIn: CGRect(origin: .zero, size: box.size), scale: s)
        if shownText != text {
            shownText = text
            label.string = text
        }
        container.isHidden = false
    }

    func hide() {
        container.isHidden = true
    }

    var isVisible: Bool { !container.isHidden }
}
