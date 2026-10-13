import AppKit

/// Fonts for one bank geometry; rebuilt only when the geometry changes.
struct FontSet {
    let readout: NSFont
    let name: NSFont
    let minNameSize: CGFloat
    let button: NSFont
    let label: NSFont

    init(geometry: BankGeometry) {
        readout = NSFont.monospacedDigitSystemFont(ofSize: geometry.readoutFontSize, weight: .semibold)
        name = NSFont.systemFont(ofSize: geometry.nameFontSize, weight: .semibold, width: .condensed)
        minNameSize = geometry.minNameFontSize
        button = NSFont.systemFont(ofSize: geometry.buttonFontSize, weight: .heavy)
        label = NSFont.monospacedDigitSystemFont(ofSize: geometry.labelFontSize, weight: .bold)
    }
}

enum TextLayout {
    /// Frame for a one-line `CATextLayer` whose text should sit visually centred (by cap height) in `rect`.
    /// `CATextLayer` draws its first line from the top of its bounds, so the frame's top is placed one ascender
    /// above the desired baseline.
    static func frame(for font: NSFont, centeredIn rect: CGRect, scale: CGFloat) -> CGRect {
        let ascender = font.ascender
        let lineHeight = ceil(ascender - font.descender + font.leading)
        let baseline = pixelAligned(rect.midY - font.capHeight / 2, scale: scale)
        let top = baseline + ascender
        return CGRect(x: rect.minX, y: top - lineHeight, width: rect.width, height: lineHeight)
    }

    /// Width of `string` set in `font`.
    static func width(of string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Font size at which `string` fits `width`, shrinking from `font`'s size down to `minimum`.
    static func fittingSize(for string: String, font: NSFont, width: CGFloat, minimum: CGFloat) -> CGFloat {
        let natural = self.width(of: string, font: font)
        guard natural > width, natural > 0, width > 0 else { return font.pointSize }
        let shrunk = (font.pointSize * width / natural * 4).rounded(.down) / 4
        return max(min(minimum, font.pointSize), shrunk)
    }

    /// A centred, single-line, end-truncating text layer.
    static func makeLayer() -> CATextLayer {
        let layer = CATextLayer()
        layer.alignmentMode = .center
        layer.truncationMode = .end
        layer.isWrapped = false
        return layer
    }

    /// Applies a font (face and size) to a text layer.
    static func apply(_ font: NSFont, size: CGFloat? = nil, to layer: CATextLayer) {
        layer.font = font
        layer.fontSize = size ?? font.pointSize
    }
}
