import CoreGraphics
import Foundation
import MeterCore

/// Every colour a bank draws, resolved once per style so frames only swap existing `CGColor`s.
struct Palette {
    let background: CGColor
    let litSegment: [CGColor]
    let unlitSegment: [CGColor]

    let readoutBox: CGColor
    let readoutText: [CGColor]
    let readoutSilent: CGColor
    let clipOff: CGColor
    let clipOn: CGColor

    let rail: CGColor
    let capFill: CGColor
    let capLine: CGColor

    let pillNeutral: CGColor
    let lightText: CGColor
    let darkText: CGColor

    let buttonOff: CGColor
    let buttonOffText: CGColor
    let soloOn: CGColor
    let muteOn: CGColor
    let armOn: CGColor
    let mutedViaSoloStroke: CGColor

    let selectionStroke: CGColor
    let selectionGlow: CGColor
    let selectionFill: CGColor
    let emptyOutline: CGColor

    let guide: CGColor
    let guideFaint: CGColor
    let guideText: CGColor
    let overlayFill: CGColor
    let overlayStroke: CGColor
    let overlayText: CGColor

    init(style: MeterStyle) {
        background = .srgb(style.backgroundColor)
        let lit = [style.greenColor, style.yellowColor, style.redColor]
        litSegment = lit.map { .srgb($0) }
        unlitSegment = lit.map { .srgb($0, brightness: 0.15, floor: 0.035) }

        readoutBox = .gray(0.075)
        readoutText = [.gray(0.86), .srgb(RGBColor(hex: 0xFFB020)), .srgb(RGBColor(hex: 0xFF3B30))]
        readoutSilent = .gray(0.42)
        clipOff = .srgb(RGBColor(hex: 0x3A0C0C))
        clipOn = .srgb(RGBColor(hex: 0xFF2A22))

        rail = .gray(0.22)
        capFill = .gray(0.88)
        capLine = .gray(0.15)

        pillNeutral = .gray(0.26)
        lightText = .gray(0.97)
        darkText = .gray(0.06)

        buttonOff = .gray(0.15)
        buttonOffText = .gray(0.55)
        soloOn = .srgb(RGBColor(hex: 0x2F8CFF))
        muteOn = .srgb(RGBColor(hex: 0xFFAE1F))
        armOn = .srgb(RGBColor(hex: 0xFF3B30))
        mutedViaSoloStroke = .srgb(RGBColor(hex: 0xFFAE1F), alpha: 0.75)

        selectionStroke = .gray(0.96)
        selectionGlow = .srgb(RGBColor(hex: 0xBFE4FF))
        selectionFill = .gray(1, alpha: 0.07)
        emptyOutline = .gray(0.2)

        guide = .srgb(RGBColor(hex: 0x29D3FF), alpha: 0.85)
        guideFaint = .srgb(RGBColor(hex: 0x29D3FF), alpha: 0.28)
        guideText = .srgb(RGBColor(hex: 0x29D3FF))
        overlayFill = .gray(0.04, alpha: 0.92)
        overlayStroke = .gray(0.75)
        overlayText = .gray(0.98)
    }

    func buttonOn(_ button: StripButton) -> CGColor {
        switch button {
        case .solo: return soloOn
        case .mute: return muteOn
        case .arm: return armOn
        }
    }

    /// Label colour on a lit button: dark on the amber mute, light on blue solo and red arm.
    func buttonOnText(_ button: StripButton) -> CGColor {
        button == .mute ? darkText : lightText
    }
}

extension CGColor {
    /// An sRGB colour from an 8-bit `RGBColor`, optionally scaled toward black (`brightness`) with a minimum level.
    static func srgb(_ c: RGBColor, alpha: CGFloat = 1, brightness: CGFloat = 1, floor: CGFloat = 0) -> CGColor {
        func channel(_ v: UInt8) -> CGFloat { floor + CGFloat(v) / 255 * brightness * (1 - floor) }
        return CGColor(srgbRed: channel(c.red), green: channel(c.green), blue: channel(c.blue), alpha: alpha)
    }

    /// A neutral sRGB grey.
    static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }
}

extension RGBColor {
    /// WCAG relative luminance (0 = black, 1 = white).
    var relativeLuminance: Double {
        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.040_45 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// True when black text has more contrast on this colour than white text (WCAG contrast ratio).
    var prefersDarkText: Bool {
        let l = relativeLuminance
        return (l + 0.05) / 0.05 > 1.05 / (l + 0.05)
    }
}
