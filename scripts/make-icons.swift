#!/usr/bin/env swift
// Draws every DAW Meter Bridge icon in code, so the art is reproducible and easy to tweak.
//
// The mark is a miniature hardware meter bridge: a row of segmented LED meter columns at
// IRREGULAR levels (never a rising staircase, so it can't read as cellular signal bars),
// short peak-hold ticks floating above some columns, all standing on a thin metallic rail.
// Colour versions light the segments green → yellow → red on a black panel. The monochrome
// bridge glyphs put a row of equal-height meters (faint tracks, lit from the bottom) in a wide
// housing, like the menu-bar icon. Small sizes are hand-snapped to the pixel grid with fewer,
// chunkier columns and segments.
//
// Usage (any working directory):
//   swift scripts/make-icons.swift              # writes into this repo
//   swift scripts/make-icons.swift --out <dir>  # writes the same tree under <dir> instead
//
// Writes (paths relative to the repo root or --out):
//   Resources/AppIcon.icns                                   macOS app icon, 16…1024 px (iconutil)
//   StreamDeckPlugin/com.ginolorca.dawmeterbridge.sdPlugin/imgs/
//     plugin/icon(.png, @2x.png)        256/512   plugin icon, full colour
//     plugin/category(.png, @2x.png)    28/56     category icon, white on transparent
//     actions/bridge/icon(…)            20/40     action-list icon, white on transparent
//     actions/bridge/off(…), on(…)      72/144    key states 0 (bridge hidden) and 1 (shown)
//     actions/main/icon(…)              20/40     action-list icon, white on transparent
//     actions/main/off(…), on(…)        72/144    key states 0 (Main meter hidden) and 1 (shown)
//   docs/images/icons-preview.png                            contact sheet of every asset
//
// The menu-bar icon is drawn in code by the app (Sources/MeterBridgeApp/Menu/MenuBarIcon.swift). The
// monochrome Stream Deck bridge glyphs (category and action list) follow it: a wide housing holding a row
// of equal-height meters with faint tracks, lit from the bottom, with peak ticks. The Main action-list glyph
// uses the same housing, with one wide L/R pair and a fader in it.

import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colour

/// An sRGB colour with alpha, 0…1 per channel.
struct RGBA: Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            r: CGFloat((hex >> 16) & 0xFF) / 255, g: CGFloat((hex >> 8) & 0xFF) / 255,
            b: CGFloat(hex & 0xFF) / 255, a: alpha
        )
    }

    init(gray: CGFloat, alpha: CGFloat = 1) {
        self.init(r: gray, g: gray, b: gray, a: alpha)
    }

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    func mixed(with other: RGBA, _ t: CGFloat) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    /// Scaled toward black, with a minimum level (how an unlit LED keeps a hint of its colour).
    func scaled(_ k: CGFloat, floor f: CGFloat = 0) -> RGBA {
        RGBA(r: f + r * k * (1 - f), g: f + g * k * (1 - f), b: f + b * k * (1 - f), a: a)
    }

    func alpha(_ value: CGFloat) -> RGBA { RGBA(r: r, g: g, b: b, a: value) }

    static let black = RGBA(gray: 0)
    static let white = RGBA(gray: 1)
}

/// Every colour the art uses. LED colours follow the app's own meter style (green 2BE24E,
/// yellow FFD21A, red FF2E2A) with a little shading inside each zone.
enum Ink {
    static let greenLow = RGBA(0x1BBF41)
    static let greenHigh = RGBA(0x4DED4E)
    static let lime = RGBA(0xC9EE24)
    static let yellow = RGBA(0xFFD21A)
    static let amber = RGBA(0xFFA21C)
    static let redLow = RGBA(0xFF5626)
    static let red = RGBA(0xFF2E2A)
    static let peakTick = RGBA(0xF2F5F7)

    /// Name-label pills, like the app's track-colour pills.
    static let pills: [RGBA] = [
        RGBA(0xFF453A), RGBA(0xFF9F0A), RGBA(0x1E9BFF), RGBA(0xE45EE8), RGBA(0x8E7CF3), RGBA(0x30C9B9),
    ]
    static let mainPill = RGBA(0x45484E)
}

/// Deterministic noise for the brushed-metal texture, so every run draws the same pixels.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low + (high - low) * CGFloat(Double(next() >> 11) / Double(1 << 53))
    }
}

// MARK: - Canvas

/// An sRGB bitmap with y pointing DOWN, so layouts read top to bottom like the specs.
/// Note: Core Graphics shadow offsets ignore the CTM, so a positive "down" offset is negative height.
final class Canvas {
    let ctx: CGContext
    let width: Int
    let height: Int

    init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { fatalError("cannot create a \(width)×\(height) bitmap") }
        self.ctx = ctx
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldSmoothFonts(false)
        ctx.interpolationQuality = .high
    }

    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    func image() -> CGImage {
        guard let image = ctx.makeImage() else { fatalError("cannot snapshot the bitmap") }
        return image
    }
}

func linearGradient(_ stops: [(CGFloat, RGBA)]) -> CGGradient {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(
            colorsSpace: space, colors: stops.map(\.1.cg) as CFArray, locations: stops.map(\.0)
          )
    else { fatalError("cannot build a gradient") }
    return gradient
}

/// A rounded rect with continuous ("squircle") corners, the shape of a macOS Big Sur app icon.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let k: CGFloat = 1.528_664_83
    let r = min(radius, min(rect.width, rect.height) / 2 / k)
    // Each corner: its point, the unit vector back along the edge we arrive on, and the one along the edge we leave on.
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0)),
    ]
    func point(_ c: (CGPoint, CGVector, CGVector), _ along: CGFloat, _ across: CGFloat) -> CGPoint {
        CGPoint(x: c.0.x + (c.1.dx * along + c.2.dx * across) * r, y: c.0.y + (c.1.dy * along + c.2.dy * across) * r)
    }
    let path = CGMutablePath()
    path.move(to: point(corners[3], 0, k))
    for c in corners {
        path.addLine(to: point(c, k, 0))
        path.addCurve(to: point(c, 0.631_494, 0.074_912), control1: point(c, 1.088_493, 0), control2: point(c, 0.868_407, 0))
        path.addCurve(to: point(c, 0.074_912, 0.631_494), control1: point(c, 0.372_824, 0.169_060), control2: point(c, 0.169_060, 0.372_824))
        path.addCurve(to: point(c, 0, k), control1: point(c, 0, 0.868_407), control2: point(c, 0, 1.088_493))
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    let r = max(0, min(radius, rect.width / 2, rect.height / 2))
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Draws one line of text centred on `center` (glyph bounds, so caps sit exactly in the middle).
func drawText(
    _ string: String, in ctx: CGContext, center: CGPoint, size: CGFloat,
    weight: NSFont.Weight, color: RGBA, kern: CGFloat = 0, snap: Bool = true
) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cg,
        .kern: kern,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    var x = center.x - glyphs.midX
    var baseline = center.y + glyphs.midY
    if snap {
        x = x.rounded()
        baseline = baseline.rounded()
    }
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: x, y: baseline)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - The meter row

/// One meter column: `level` lit segments from the bottom, and an optional peak-hold tick at segment index `peak`.
struct Meter: Sendable {
    var level: Int
    var peak: Int?
}

/// Converts level and peak fractions into segment counts for `segments` segments.
func meters(_ levels: [Double], peaks: [Double?], segments: Int) -> [Meter] {
    zip(levels, peaks).map { level, peak in
        let lit = min(segments, max(1, Int((level * Double(segments)).rounded())))
        var hold: Int?
        if let peak {
            let index = max(lit + 1, Int((peak * Double(segments)).rounded()) - 1)
            if index < segments { hold = index }
        }
        return Meter(level: lit, peak: hold)
    }
}

/// The bridge's signature levels: irregular on purpose, the tallest column off-centre, never a staircase.
enum Levels {
    static let six = [0.55, 0.85, 0.40, 1.00, 0.70, 0.60]
    static let sixPeaks: [Double?] = [0.80, nil, 0.66, nil, 0.92, nil]
    static let five = [0.55, 0.85, 0.40, 1.00, 0.65]
    static let fivePeaks: [Double?] = [0.80, nil, 0.66, nil, 0.92]
}

/// Columns of LED segments in pixels (y down). Segment 0 is the bottom one.
struct LEDGrid {
    var columnX: [CGFloat]
    var columnWidth: CGFloat
    var bottom: CGFloat
    var segments: Int
    var segmentHeight: CGFloat
    var segmentGap: CGFloat

    /// Evenly spaced columns centred on `centerX`, standing on `bottom`. Positions are snapped to whole pixels.
    init(
        columns: Int, columnWidth: CGFloat, columnGap: CGFloat, centerX: CGFloat, bottom: CGFloat,
        segments: Int, segmentHeight: CGFloat, segmentGap: CGFloat
    ) {
        let total = CGFloat(columns) * columnWidth + CGFloat(columns - 1) * columnGap
        let left = (centerX - total / 2).rounded()
        columnX = (0..<columns).map { left + CGFloat($0) * (columnWidth + columnGap) }
        self.columnWidth = columnWidth
        self.bottom = bottom.rounded()
        self.segments = segments
        self.segmentHeight = segmentHeight
        self.segmentGap = segmentGap
    }

    init(columnX: [CGFloat], columnWidth: CGFloat, bottom: CGFloat, segments: Int, segmentHeight: CGFloat, segmentGap: CGFloat) {
        self.columnX = columnX
        self.columnWidth = columnWidth
        self.bottom = bottom
        self.segments = segments
        self.segmentHeight = segmentHeight
        self.segmentGap = segmentGap
    }

    var height: CGFloat { CGFloat(segments) * segmentHeight + CGFloat(segments - 1) * segmentGap }
    var top: CGFloat { bottom - height }
    var minX: CGFloat { columnX.first ?? 0 }
    var maxX: CGFloat { (columnX.last ?? 0) + columnWidth }
    var frame: CGRect { CGRect(x: minX, y: top, width: maxX - minX, height: height) }

    func segment(_ column: Int, _ index: Int) -> CGRect {
        let y = bottom - CGFloat(index + 1) * segmentHeight - CGFloat(index) * segmentGap
        return CGRect(x: columnX[column], y: y, width: columnWidth, height: segmentHeight)
    }
}

/// The lit colour of segment `index` of `count`: green, then lime/yellow/amber, then red at the top.
func ledColor(_ index: Int, of count: Int) -> RGBA {
    let reds = max(1, Int((Double(count) * 0.12).rounded()))
    let yellows = max(1, Int((Double(count) * 0.22).rounded()))
    let greens = count - reds - yellows
    if index >= count - reds {
        let t = reds == 1 ? 1 : CGFloat(index - (count - reds)) / CGFloat(reds - 1)
        return Ink.redLow.mixed(with: Ink.red, t)
    }
    if index >= greens {
        let t = yellows == 1 ? 0.5 : CGFloat(index - greens) / CGFloat(yellows - 1)
        return t < 0.5 ? Ink.lime.mixed(with: Ink.yellow, t * 2) : Ink.yellow.mixed(with: Ink.amber, (t - 0.5) * 2)
    }
    let t = greens <= 1 ? 1 : CGFloat(index) / CGFloat(greens - 1)
    return Ink.greenLow.mixed(with: Ink.greenHigh, t)
}

/// How a meter row is painted.
struct LEDLook {
    /// Every segment unlit (the OFF key states).
    var allUnlit = false
    /// Unlit segments: zone colour scaled to `unlitBrightness` over `unlitFloor`, then pulled toward neutral grey.
    var unlitBrightness: CGFloat = 0.13
    var unlitFloor: CGFloat = 0.05
    var unlitNeutral: CGFloat = 0.35
    /// LED bloom radius in pixels (0 = none).
    var glow: CGFloat = 0
    /// A soft horizontal sheen and a top highlight on lit segments.
    var sheen = false
    var cornerRadius: CGFloat = 0
    /// Peak-hold tick height as a fraction of a segment, and its colour (nil = the segment's LED colour).
    var peakHeight: CGFloat = 1
    var peakColor: RGBA?
}

func peakRect(_ cell: CGRect, fraction: CGFloat) -> CGRect {
    guard fraction < 1 else { return cell }
    let h = max(1, (cell.height * fraction).rounded())
    let y = cell.minY + ((cell.height - h) / 2).rounded(.down)
    return CGRect(x: cell.minX, y: y, width: cell.width, height: h)
}

func drawLEDs(_ ctx: CGContext, grid: LEDGrid, meters: [Meter], look: LEDLook) {
    let n = grid.segments
    func isLit(_ m: Meter, _ s: Int) -> Bool { !look.allUnlit && s < m.level }
    func isPeak(_ m: Meter, _ s: Int) -> Bool { !look.allUnlit && s == m.peak }

    // 1. Unlit housings.
    for (c, m) in meters.enumerated() {
        for s in 0..<n where !isLit(m, s) && !isPeak(m, s) {
            let zone = ledColor(s, of: n)
            let dark = zone.scaled(look.unlitBrightness, floor: look.unlitFloor)
            let grey = (dark.r * 0.3 + dark.g * 0.55 + dark.b * 0.15)
            ctx.setFillColor(dark.mixed(with: RGBA(gray: grey), look.unlitNeutral).cg)
            ctx.addPath(roundedRect(grid.segment(c, s), look.cornerRadius))
            ctx.fillPath()
        }
    }

    // The lit shapes: segments below the level, and the peak-hold ticks.
    var lit: [(CGRect, RGBA, Bool)] = []
    for (c, m) in meters.enumerated() {
        for s in 0..<n {
            if isLit(m, s) {
                lit.append((grid.segment(c, s), ledColor(s, of: n), false))
            } else if isPeak(m, s) {
                lit.append((peakRect(grid.segment(c, s), fraction: look.peakHeight), look.peakColor ?? ledColor(s, of: n), true))
            }
        }
    }

    // 2. Bloom: the lit shapes with a coloured blur, in one layer so neighbours don't tint each other.
    if look.glow > 0 {
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for (rect, color, _) in lit {
            ctx.setShadow(offset: .zero, blur: look.glow, color: color.alpha(0.85).cg)
            ctx.setFillColor(color.cg)
            ctx.addPath(roundedRect(rect, look.cornerRadius))
            ctx.fillPath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // 3. The crisp LEDs on top.
    let sheen = linearGradient([
        (0, RGBA(gray: 0, alpha: 0.20)), (0.30, RGBA(gray: 1, alpha: 0.14)),
        (0.62, RGBA(gray: 1, alpha: 0.03)), (1, RGBA(gray: 0, alpha: 0.26)),
    ])
    for (rect, color, _) in lit {
        ctx.saveGState()
        ctx.addPath(roundedRect(rect, look.cornerRadius))
        ctx.clip()
        ctx.setFillColor(color.cg)
        ctx.fill(rect)
        if look.sheen {
            ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
            if rect.height >= 4 {
                let line = max(1, (rect.height * 0.14).rounded())
                ctx.setFillColor(RGBA(gray: 1, alpha: 0.30).cg)
                ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: line))
            }
        }
        ctx.restoreGState()
    }
}

/// The thin metallic rail the meters stand on: the bridge's bottom trim.
func drawRail(_ ctx: CGContext, _ rect: CGRect, dim: Bool = false, detail: Bool = true) {
    let k: CGFloat = dim ? 0.5 : 1
    let path = roundedRect(rect, rect.height / 2)
    if rect.height < 3 {
        ctx.setFillColor(RGBA(gray: 0.66 * k).cg)
        ctx.fill(rect)
        return
    }
    // Drop shadow under the rail.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.height * 0.25), blur: rect.height * 0.7, color: RGBA(gray: 0, alpha: 0.8).cg)
    ctx.setFillColor(RGBA(gray: 0.3 * k).cg)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let metal = linearGradient([
        (0, RGBA(0xF7F9FB).scaled(k)), (0.16, RGBA(0xD3D8DD).scaled(k)), (0.48, RGBA(0x9198A0).scaled(k)),
        (0.80, RGBA(0x5C636B).scaled(k)), (1, RGBA(0x30353B).scaled(k)),
    ])
    ctx.drawLinearGradient(metal, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    if detail {
        brush(ctx, rect, step: max(0.6, rect.height / 22), seed: 0xBA11, strength: 0.10 * k)
        // A soft specular glint, left of centre.
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let glint = CGGradient(colorsSpace: space, colors: [RGBA(gray: 1, alpha: 0.55 * k).cg, RGBA(gray: 1, alpha: 0).cg] as CFArray, locations: [0, 1]) {
            let center = CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.3)
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: rect.width * 0.28 / rect.height, y: 1)
            ctx.drawRadialGradient(glint, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rect.height, options: [])
            ctx.restoreGState()
        }
    }
    ctx.restoreGState()
}

/// Fine horizontal streaks, like brushed aluminium. Deterministic.
func brush(_ ctx: CGContext, _ rect: CGRect, step: CGFloat, seed: UInt64, strength: CGFloat) {
    var rng = SplitMix64(seed: seed)
    var y = rect.minY
    while y < rect.maxY {
        let h = step * rng.unit(0.5, 1.3)
        let light = rng.next() & 1 == 0
        let alpha = strength * rng.unit(0.15, 1)
        let x = rect.minX + rect.width * rng.unit(-0.3, 0.7)
        let w = rect.width * rng.unit(0.25, 1.1)
        ctx.setFillColor(light ? RGBA(gray: 1, alpha: alpha).cg : RGBA(gray: 0, alpha: alpha * 1.3).cg)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
        y += step * rng.unit(0.5, 1.5)
    }
}

/// Name-label pills under the columns.
func drawPills(_ ctx: CGContext, grid: LEDGrid, y: CGFloat, height: CGFloat, dim: Bool) {
    for (c, x) in grid.columnX.enumerated() {
        let base = Ink.pills[c % Ink.pills.count]
        let color = dim ? base.scaled(0.28, floor: 0.06) : base
        let rect = CGRect(x: x, y: y, width: grid.columnWidth, height: height)
        ctx.setFillColor(color.cg)
        ctx.addPath(roundedRect(rect, height / 2))
        ctx.fillPath()
        if !dim && height >= 6 {
            // A faint top sheen so the pill reads as a lit label.
            ctx.saveGState()
            ctx.addPath(roundedRect(rect, height / 2))
            ctx.clip()
            ctx.setFillColor(RGBA(gray: 1, alpha: 0.18).cg)
            ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: (height * 0.42).rounded()))
            ctx.restoreGState()
        }
    }
}

// MARK: - App icon (and plugin icon)

struct AppIconSpec {
    var bodyInset: CGFloat
    var shadow: Bool
    var columns: Int
    var segments: Int
    var columnWidth: CGFloat
    var columnGap: CGFloat
    var segmentHeight: CGFloat
    var segmentGap: CGFloat
    /// Space between the LEDs and the recessed meter window's edge (0 = no window).
    var windowPad: CGFloat
    var railGap: CGFloat
    var railHeight: CGFloat
    /// The rail's length; it always stays inside the housing's curved corners.
    var railWidth: CGFloat
    var pillGap: CGFloat
    var pillHeight: CGFloat
    var meters: [Meter]
    var glow: CGFloat
    var texture: Bool
    var sheen: Bool
    var cornerRadius: CGFloat
    /// Peak-hold ticks: height as a fraction of a segment (white when < 1), or 0 for none.
    var peakHeight: CGFloat
}

/// The app-icon layout for a pixel size. 128 px and up scale one design; 16…64 are hand-snapped pixel art.
func appIconSpec(size: Int, bodyInsetFraction: CGFloat = 100.0 / 1024, shadow: Bool = true) -> AppIconSpec {
    let s = CGFloat(size)
    switch size {
    case ..<24:
        // 16 px: four columns of three chunky segments on a one-pixel rail.
        return AppIconSpec(
            bodyInset: 1, shadow: false, columns: 4, segments: 3, columnWidth: 2, columnGap: 1,
            segmentHeight: 2, segmentGap: 1, windowPad: 0, railGap: 1, railHeight: 1, railWidth: 11,
            pillGap: 0, pillHeight: 0,
            meters: [Meter(level: 2), Meter(level: 3), Meter(level: 1), Meter(level: 2)],
            glow: 0, texture: false, sheen: false, cornerRadius: 0, peakHeight: 0
        )
    case ..<48:
        // 32 px: five columns, six segments, one-pixel peak ticks.
        return AppIconSpec(
            bodyInset: 2, shadow: false, columns: 5, segments: 6, columnWidth: 3, columnGap: 2,
            segmentHeight: 2, segmentGap: 1, windowPad: 2, railGap: 2, railHeight: 2, railWidth: 23,
            pillGap: 0, pillHeight: 0,
            meters: [Meter(level: 3, peak: 5), Meter(level: 5), Meter(level: 2, peak: 4), Meter(level: 6), Meter(level: 4)],
            glow: 0, texture: false, sheen: false, cornerRadius: 0, peakHeight: 0.5
        )
    case ..<96:
        // 64 px: five columns, nine segments.
        return AppIconSpec(
            bodyInset: 6, shadow: true, columns: 5, segments: 9, columnWidth: 6, columnGap: 2,
            segmentHeight: 2, segmentGap: 1, windowPad: 4, railGap: 3, railHeight: 3, railWidth: 44,
            pillGap: 0, pillHeight: 0,
            meters: [Meter(level: 5, peak: 7), Meter(level: 8), Meter(level: 4, peak: 6), Meter(level: 9), Meter(level: 6, peak: 8)],
            glow: 1.5, texture: false, sheen: false, cornerRadius: 0, peakHeight: 0.5
        )
    default:
        let body = s - 2 * (s * bodyInsetFraction)
        let u = body / 824
        let segments = size >= 512 ? 22 : size >= 256 ? 16 : 11
        let pitch = 500 * u / CGFloat(segments)
        let segmentGap = max(1, (pitch * 0.27).rounded())
        let segmentHeight = max(1, (pitch - segmentGap).rounded())
        var columnWidth = (80 * u).rounded()
        let columnGap = max(1, (28 * u).rounded())
        if 6 * columnWidth + 5 * columnGap > 624 * u { columnWidth -= 1 }
        let detail = size >= 256
        return AppIconSpec(
            bodyInset: s * bodyInsetFraction, shadow: shadow, columns: 6, segments: segments,
            columnWidth: columnWidth, columnGap: columnGap, segmentHeight: segmentHeight, segmentGap: segmentGap,
            windowPad: (40 * u).rounded(), railGap: (26 * u).rounded(), railHeight: max(3, (24 * u).rounded()),
            railWidth: (750 * u).rounded(),
            pillGap: detail ? (30 * u).rounded() : 0, pillHeight: detail ? max(4, (22 * u).rounded()) : 0,
            meters: meters(Levels.six, peaks: Levels.sixPeaks, segments: segments),
            glow: max(1.5, 12 * u), texture: detail, sheen: true, cornerRadius: size >= 256 ? 3 * u : 0,
            peakHeight: 0.62
        )
    }
}

func drawAppIcon(_ ctx: CGContext, size: Int, spec: AppIconSpec) {
    let s = CGFloat(size)
    let body = CGRect(x: spec.bodyInset, y: spec.bodyInset, width: s - 2 * spec.bodyInset, height: s - 2 * spec.bodyInset)
    let u = body.width / 824
    let bodyPath = continuousRoundedRect(body, radius: body.width * 185.4 / 824)

    // Vertical stack: [window pad, LEDs, window pad], rail gap, rail, pill gap, pills — centred in the body.
    let ledHeight = CGFloat(spec.segments) * spec.segmentHeight + CGFloat(spec.segments - 1) * spec.segmentGap
    let stack = spec.windowPad * 2 + ledHeight + spec.railGap + spec.railHeight
        + (spec.pillHeight > 0 ? spec.pillGap + spec.pillHeight : 0)
    let top = (body.midY - stack / 2 + (spec.pillHeight > 0 ? 0 : -spec.railHeight * 0.2)).rounded()
    let grid = LEDGrid(
        columns: spec.columns, columnWidth: spec.columnWidth, columnGap: spec.columnGap, centerX: body.midX,
        bottom: top + spec.windowPad + ledHeight, segments: spec.segments,
        segmentHeight: spec.segmentHeight, segmentGap: spec.segmentGap
    )

    // 1. The housing: near-black, lighter at the top, with a soft drop shadow.
    ctx.saveGState()
    if spec.shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 22 * u, color: RGBA(gray: 0, alpha: 0.42).cg)
    }
    ctx.setFillColor(RGBA(0x111215).cg)
    ctx.addPath(bodyPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let housing = linearGradient([(0, RGBA(0x30333A)), (0.42, RGBA(0x17191D)), (1, RGBA(0x08090B))])
    ctx.drawLinearGradient(housing, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
    if spec.texture {
        brush(ctx, body, step: 1.4 * u * 2, seed: 0xD4A7, strength: 0.034)
    }
    // A broad, soft top light.
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let light = CGGradient(colorsSpace: space, colors: [RGBA(gray: 1, alpha: 0.10).cg, RGBA(gray: 1, alpha: 0).cg] as CFArray, locations: [0, 1]) {
        ctx.saveGState()
        ctx.translateBy(x: body.midX, y: body.minY)
        ctx.scaleBy(x: 1.6, y: 1)
        ctx.drawRadialGradient(light, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: body.height * 0.55, options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // 2. The recessed meter window: black glass with an inner shadow and a lit lower bevel.
    let ledFrame = grid.frame
    if spec.windowPad > 0 {
        let window = CGRect(
            x: ledFrame.minX - spec.windowPad, y: ledFrame.minY - spec.windowPad,
            width: ledFrame.width + spec.windowPad * 2, height: ledFrame.height + spec.windowPad * 2
        )
        let windowPath = roundedRect(window, spec.windowPad * 1.05)
        if size >= 64 {
            // Bevel: a highlight just below the window's lower edge.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: max(1, 2 * u))
            ctx.setFillColor(RGBA(gray: 1, alpha: 0.10).cg)
            ctx.addPath(windowPath)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.setFillColor(RGBA(0x020203).cg)
        ctx.addPath(windowPath)
        ctx.fillPath()
        if size >= 64 {
            ctx.saveGState()
            ctx.addPath(windowPath)
            ctx.clip()
            let frame = CGMutablePath()
            frame.addRect(window.insetBy(dx: -60 * u - 8, dy: -60 * u - 8))
            frame.addPath(windowPath)
            ctx.setShadow(offset: CGSize(width: 0, height: -7 * u), blur: 18 * u, color: RGBA(gray: 0, alpha: 1).cg)
            ctx.setFillColor(RGBA(gray: 0).cg)
            ctx.addPath(frame)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }
    }

    // 3. The meters.
    let shownMeters = spec.peakHeight > 0 ? spec.meters : spec.meters.map { Meter(level: $0.level) }
    drawLEDs(ctx, grid: grid, meters: shownMeters, look: LEDLook(
        unlitBrightness: 0.12, unlitFloor: 0.05, unlitNeutral: 0.8, glow: spec.glow, sheen: spec.sheen,
        cornerRadius: spec.cornerRadius, peakHeight: max(spec.peakHeight, 0.01), peakColor: Ink.peakTick
    ))

    // 4. Glass: a soft reflection falling from the window's top-left corner.
    if spec.windowPad > 0 && size >= 128 {
        let window = ledFrame.insetBy(dx: -spec.windowPad, dy: -spec.windowPad)
        ctx.saveGState()
        ctx.addPath(roundedRect(window, spec.windowPad * 1.05))
        ctx.clip()
        let glass = linearGradient([(0, RGBA(gray: 1, alpha: 0.07)), (0.55, RGBA(gray: 1, alpha: 0.025)), (1, RGBA(gray: 1, alpha: 0))])
        ctx.translateBy(x: window.minX, y: window.minY)
        ctx.scaleBy(x: 1.15, y: 0.75)
        ctx.drawRadialGradient(glass, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: window.width, options: [])
        ctx.restoreGState()
    }

    // 5. The rail, then the name-label pills on the console below it.
    let railY = ledFrame.maxY + spec.windowPad + spec.railGap
    let rail = CGRect(x: (body.midX - spec.railWidth / 2).rounded(), y: railY, width: spec.railWidth, height: spec.railHeight)
    drawRail(ctx, rail, detail: size >= 256)
    if spec.pillHeight > 0 {
        drawPills(ctx, grid: grid, y: rail.maxY + spec.pillGap, height: spec.pillHeight, dim: false)
    }

    // 6. Rim light along the top edge, and a dark hairline around the housing.
    if size >= 64 {
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.addPath(bodyPath)
        ctx.setLineWidth(max(1, 5 * u))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let rim = linearGradient([(0, RGBA(gray: 1, alpha: 0.30)), (0.22, RGBA(gray: 1, alpha: 0.06)), (0.8, RGBA(gray: 1, alpha: 0.02)), (1, RGBA(gray: 1, alpha: 0.08))])
        ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        ctx.restoreGState()
    }
}

// MARK: - Stream Deck keys (designed on a 72-px grid, drawn at scale 1 or 2)

func drawKeyBackground(_ ctx: CGContext, scale k: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: 72 * k, height: 72 * k)
    let panel = linearGradient([(0, RGBA(0x16181C)), (0.55, RGBA(0x0A0B0D)), (1, RGBA(0x050506))])
    ctx.drawLinearGradient(panel, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
}

/// The Show/Hide Bridge key: five meters with name pills. ON is lit; OFF has the same geometry with every LED dark.
func drawBridgeKey(_ ctx: CGContext, scale k: CGFloat, on: Bool) {
    drawKeyBackground(ctx, scale: k)
    let segments = 11
    let grid = LEDGrid(
        columns: 5, columnWidth: 9 * k, columnGap: 3 * k, centerX: 36 * k, bottom: 51 * k,
        segments: segments, segmentHeight: 3 * k, segmentGap: 1 * k
    )
    let row = [Meter(level: 6, peak: 8), Meter(level: 9), Meter(level: 4, peak: 7), Meter(level: 11), Meter(level: 7, peak: 9)]
    drawLEDs(ctx, grid: grid, meters: row, look: LEDLook(
        allUnlit: !on, unlitBrightness: on ? 0.12 : 0.26, unlitFloor: on ? 0.05 : 0.12, unlitNeutral: on ? 0.6 : 0.85,
        glow: on ? 2.2 * k : 0, sheen: true, cornerRadius: 0.5 * k, peakHeight: 0.67, peakColor: Ink.peakTick
    ))
    drawRail(ctx, CGRect(x: grid.minX - 3 * k, y: 54 * k, width: grid.maxX - grid.minX + 6 * k, height: 3 * k), dim: !on, detail: k > 1)
    drawPills(ctx, grid: grid, y: 60 * k, height: 4 * k, dim: !on)
}

/// The Show/Hide Main Meter key: one wide stereo pair (L/R) with its fader and a "MAIN" label, like the app's Main strip.
func drawMainKey(_ ctx: CGContext, scale k: CGFloat, on: Bool) {
    drawKeyBackground(ctx, scale: k)
    let segments = 10
    let grid = LEDGrid(
        columnX: [13 * k, 30 * k], columnWidth: 15 * k, bottom: 46 * k,
        segments: segments, segmentHeight: 3 * k, segmentGap: 1 * k
    )
    let pair = [Meter(level: 8, peak: 9), Meter(level: 6, peak: 8)]
    drawLEDs(ctx, grid: grid, meters: pair, look: LEDLook(
        allUnlit: !on, unlitBrightness: on ? 0.12 : 0.26, unlitFloor: on ? 0.05 : 0.12, unlitNeutral: on ? 0.6 : 0.85,
        glow: on ? 2.2 * k : 0, sheen: true, cornerRadius: 0.5 * k, peakHeight: 0.67, peakColor: Ink.peakTick
    ))

    // The master fader: a slot and a cap, to the right of the pair.
    let slot = CGRect(x: 52 * k, y: grid.top, width: 2 * k, height: grid.height)
    ctx.setFillColor(RGBA(gray: on ? 0.30 : 0.18).cg)
    ctx.addPath(roundedRect(slot, k))
    ctx.fillPath()
    let cap = CGRect(x: 48 * k, y: 15 * k, width: 10 * k, height: 6 * k)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -k), blur: 2 * k, color: RGBA(gray: 0, alpha: 0.8).cg)
    ctx.setFillColor((on ? RGBA(0xE4E7EA) : RGBA(gray: 0.34)).cg)
    ctx.addPath(roundedRect(cap, 1.2 * k))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.setFillColor(RGBA(gray: on ? 0.16 : 0.12).cg)
    ctx.fill(CGRect(x: cap.minX + k, y: cap.midY - 0.5 * k, width: cap.width - 2 * k, height: k))

    drawRail(ctx, CGRect(x: 10 * k, y: 49 * k, width: 52 * k, height: 3 * k), dim: !on, detail: k > 1)

    // The "MAIN" pill, grey like the app's Main track pill.
    let pill = CGRect(x: 15 * k, y: 55 * k, width: 42 * k, height: 13 * k)
    ctx.setFillColor((on ? Ink.mainPill : RGBA(0x1E2023)).cg)
    ctx.addPath(roundedRect(pill, pill.height / 2))
    ctx.fillPath()
    drawText(
        "MAIN", in: ctx, center: CGPoint(x: pill.midX, y: pill.midY), size: 10 * k, weight: .heavy,
        color: on ? RGBA(gray: 0.98) : RGBA(gray: 0.40), kern: 0.9 * k
    )
}

// MARK: - Monochrome icons (Stream Deck action list and category)

/// The bridge glyph for a small square canvas, in one colour. Same design as the menu-bar icon
/// (Sources/MeterBridgeApp/Menu/MenuBarIcon.swift): a wide, low housing holding a row of meters, each
/// showing its whole track faintly with the lit part solid from the bottom, and peak-hold ticks. All the
/// meters have the same height, so it reads as a meter bridge, never as bars of different heights.
func drawBridgeGlyph(_ ctx: CGContext, size: Int, scale k: CGFloat, color: RGBA) {
    // Designed in 1x pixels (y down); every number is a whole pixel, so 2x is exact too.
    let housing: CGRect
    let meterX: CGFloat, meterTop: CGFloat, meterHeight: CGFloat
    let lit: [CGFloat]
    let peakGaps: [CGFloat?]
    switch size {
    case 20:
        // Action list, 20 px: a 20 × 12 housing, five meters 2 px wide and 8 px tall, 1 px apart.
        housing = CGRect(x: 0, y: 4, width: 20, height: 12)
        meterX = 3
        meterTop = 6
        meterHeight = 8
        lit = [4, 6, 3, 7, 5]
        peakGaps = [1, nil, 2, nil, 1]
    default:
        // Category, 28 px: a 26 × 14 housing, seven meters 2 px wide and 10 px tall, 1 px apart.
        housing = CGRect(x: 1, y: 7, width: 26, height: 14)
        meterX = 4
        meterTop = 9
        meterHeight = 10
        lit = [5, 8, 4, 9, 6, 4, 7]
        peakGaps = [1, nil, 2, nil, 1, 2, nil]
    }
    let meterWidth: CGFloat = 2
    let meterPitch: CGFloat = 3
    let trackAlpha: CGFloat = 0.32

    // The housing: a 1-px rounded outline.
    ctx.setStrokeColor(color.cg)
    ctx.setLineWidth(k)
    ctx.addPath(roundedRect(
        CGRect(x: housing.minX * k, y: housing.minY * k, width: housing.width * k, height: housing.height * k)
            .insetBy(dx: k / 2, dy: k / 2),
        2 * k
    ))
    ctx.strokePath()

    let bottom = meterTop + meterHeight
    for (index, level) in lit.enumerated() {
        let x = (meterX + CGFloat(index) * meterPitch) * k
        // The faint track above the lit part, then the lit part.
        ctx.setFillColor(color.alpha(color.a * trackAlpha).cg)
        ctx.fill(CGRect(x: x, y: meterTop * k, width: meterWidth * k, height: (meterHeight - level) * k))
        ctx.setFillColor(color.cg)
        ctx.fill(CGRect(x: x, y: (bottom - level) * k, width: meterWidth * k, height: level * k))
        // The peak-hold tick, 1 px, `gap` px above the lit top.
        if let gap = peakGaps[index], level + gap + 1 <= meterHeight {
            ctx.fill(CGRect(x: x, y: (bottom - level - gap - 1) * k, width: meterWidth * k, height: k))
        }
    }
}

/// The Main glyph for the 20-px action list, in one colour: the bridge glyph's housing (same size and
/// outline) holding one wide L/R meter pair, with faint tracks lit from the bottom and a peak tick, and the
/// master fader (slot and cap) beside it. The two actions in the list look like one set.
func drawMainGlyph(_ ctx: CGContext, scale k: CGFloat, color: RGBA) {
    // Designed in 1x pixels (y down); every number is a whole pixel, so 2x is exact too.
    let housing = CGRect(x: 0, y: 4, width: 20, height: 12)
    let meterTop: CGFloat = 6
    let meterHeight: CGFloat = 8
    let meterWidth: CGFloat = 3
    let trackAlpha: CGFloat = 0.32
    // L and R, 2 px apart: x, lit height, and the gap from the lit top to a peak tick.
    let pair: [(x: CGFloat, lit: CGFloat, peakGap: CGFloat?)] = [(3, 6, nil), (8, 5, 1)]

    ctx.setStrokeColor(color.cg)
    ctx.setLineWidth(k)
    ctx.addPath(roundedRect(
        CGRect(x: housing.minX * k, y: housing.minY * k, width: housing.width * k, height: housing.height * k)
            .insetBy(dx: k / 2, dy: k / 2),
        2 * k
    ))
    ctx.strokePath()

    let bottom = meterTop + meterHeight
    for meter in pair {
        ctx.setFillColor(color.alpha(color.a * trackAlpha).cg)
        ctx.fill(CGRect(x: meter.x * k, y: meterTop * k, width: meterWidth * k, height: (meterHeight - meter.lit) * k))
        ctx.setFillColor(color.cg)
        ctx.fill(CGRect(x: meter.x * k, y: (bottom - meter.lit) * k, width: meterWidth * k, height: meter.lit * k))
        if let gap = meter.peakGap, meter.lit + gap + 1 <= meterHeight {
            ctx.fill(CGRect(x: meter.x * k, y: (bottom - meter.lit - gap - 1) * k, width: meterWidth * k, height: k))
        }
    }

    // The master fader inside the right of the housing: a 1-px slot and a cap with its centre line cut out.
    ctx.setFillColor(color.cg)
    ctx.fill(CGRect(x: 15 * k, y: meterTop * k, width: k, height: meterHeight * k))
    ctx.fill(CGRect(x: 13 * k, y: 8 * k, width: 5 * k, height: 3 * k))
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    ctx.fill(CGRect(x: 14 * k, y: 9 * k, width: 3 * k, height: k))
    ctx.restoreGState()
}

// MARK: - Output

func writePNG(_ image: CGImage, _ url: URL) {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
        fatalError("cannot create \(url.deletingLastPathComponent().path): \(error)")
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
}

func render(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let canvas = Canvas(width, height)
    draw(canvas.ctx)
    return canvas.image()
}

/// One image on the contact sheet.
struct Tile {
    var name: String
    var detail: String
    var image: CGImage
}

/// An image drawn at 1x and 2x, for `<base>.png` and `<base>@2x.png`.
func pair(
    _ base: String, name: String, width: Int, height: Int, _ draw: (CGContext, CGFloat) -> Void
) -> [(path: String, tile: Tile)] {
    [1, 2].map { k in
        let image = render(width * k, height * k) { draw($0, CGFloat(k)) }
        let tile = Tile(name: name, detail: "\(k)x · \(width * k)×\(height * k)", image: image)
        return ("\(base)\(k == 2 ? "@2x" : "").png", tile)
    }
}

func appIcon(_ size: Int) -> CGImage {
    render(size, size) { drawAppIcon($0, size: size, spec: appIconSpec(size: size)) }
}

func pluginIcon(_ size: Int) -> CGImage {
    render(size, size) { drawAppIcon($0, size: size, spec: appIconSpec(size: size, bodyInsetFraction: 0.035, shadow: false)) }
}

let fileManager = FileManager.default
var outRoot: URL = {
    let script = URL(fileURLWithPath: #filePath, relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath))
    return script.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
}()
var argumentIterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = argumentIterator.next() {
    switch argument {
    case "--out":
        guard let value = argumentIterator.next() else { fatalError("--out needs a directory") }
        outRoot = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    default:
        fatalError("unknown argument \(argument); usage: swift scripts/make-icons.swift [--out <dir>]")
    }
}

let plugin = "StreamDeckPlugin/com.ginolorca.dawmeterbridge.sdPlugin/imgs"
let appSizes = [16, 32, 64, 128, 256, 512, 1024]
let appImages = Dictionary(uniqueKeysWithValues: appSizes.map { ($0, appIcon($0)) })

let pluginIcons: [(path: String, tile: Tile)] = [(1, 256), (2, 512)].map { k, size in
    ("\(plugin)/plugin/icon\(k == 2 ? "@2x" : "").png",
     Tile(name: "plugin icon", detail: "\(k)x · \(size)×\(size)", image: pluginIcon(size)))
}
let keys = pair("\(plugin)/actions/bridge/off", name: "bridge · off", width: 72, height: 72) { drawBridgeKey($0, scale: $1, on: false) }
    + pair("\(plugin)/actions/bridge/on", name: "bridge · on", width: 72, height: 72) { drawBridgeKey($0, scale: $1, on: true) }
    + pair("\(plugin)/actions/main/off", name: "main · off", width: 72, height: 72) { drawMainKey($0, scale: $1, on: false) }
    + pair("\(plugin)/actions/main/on", name: "main · on", width: 72, height: 72) { drawMainKey($0, scale: $1, on: true) }
let glyphs = pair("\(plugin)/plugin/category", name: "category", width: 28, height: 28) { drawBridgeGlyph($0, size: 28, scale: $1, color: .white) }
    + pair("\(plugin)/actions/bridge/icon", name: "bridge icon", width: 20, height: 20) { drawBridgeGlyph($0, size: 20, scale: $1, color: .white) }
    + pair("\(plugin)/actions/main/icon", name: "main icon", width: 20, height: 20) { drawMainGlyph($0, scale: $1, color: .white) }

for (path, tile) in pluginIcons + keys + glyphs {
    writePNG(tile.image, outRoot.appendingPathComponent(path))
}

// The .icns, through an .iconset in a temporary folder.
let iconset = fileManager.temporaryDirectory.appendingPathComponent("DAWMeterBridge-\(UUID().uuidString).iconset")
for (name, size) in [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
] {
    guard let image = appImages[size] else { fatalError("missing \(size) px app icon") }
    writePNG(image, iconset.appendingPathComponent("icon_\(name).png"))
}
let icns = outRoot.appendingPathComponent("Resources/AppIcon.icns")
do {
    // iconutil fails when the output folder doesn't exist yet (a fresh --out tree).
    try fileManager.createDirectory(at: icns.deletingLastPathComponent(), withIntermediateDirectories: true)
} catch {
    fatalError("cannot create \(icns.deletingLastPathComponent().path): \(error)")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    fatalError("cannot run iconutil: \(error)")
}
try? fileManager.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed (\(iconutil.terminationStatus))") }

// MARK: - Contact sheet

/// Every asset at 1x and 2x, at real pixel size, on black (left half) and on mid-grey (right half).
func contactSheet(_ groups: [(title: String, tiles: [Tile])]) -> CGImage {
    let margin: CGFloat = 40
    let gap: CGFloat = 22
    let minSlot: CGFloat = 96
    let titleHeight: CGFloat = 40
    let captionHeight: CGFloat = 40
    let groupGap: CGFloat = 30
    let header: CGFloat = 64

    func slot(_ tile: Tile) -> CGFloat { max(minSlot, CGFloat(tile.image.width)) }
    func tallest(_ tiles: [Tile]) -> CGFloat { tiles.map { CGFloat($0.image.height) }.max() ?? 0 }

    var halfWidth: CGFloat = 0
    var height = header
    for group in groups {
        var width = margin * 2 + gap * CGFloat(group.tiles.count - 1)
        for tile in group.tiles { width += slot(tile) }
        halfWidth = max(halfWidth, width)
        height += titleHeight + tallest(group.tiles) + captionHeight + groupGap
    }
    height += margin - groupGap

    let canvas = Canvas(Int(halfWidth * 2), Int(height))
    let ctx = canvas.ctx
    let halves: [(x: CGFloat, background: RGBA, text: RGBA, dim: RGBA, title: String)] = [
        (0, RGBA(gray: 0), RGBA(gray: 0.92), RGBA(gray: 0.58), "DAW Meter Bridge icons · on black"),
        (halfWidth, RGBA(gray: 0.5), RGBA(gray: 0.04), RGBA(gray: 0.2), "on mid-grey"),
    ]
    for half in halves {
        ctx.setFillColor(half.background.cg)
        ctx.fill(CGRect(x: half.x, y: 0, width: halfWidth, height: height))
        drawLeftText(half.title, in: ctx, origin: CGPoint(x: half.x + margin, y: header / 2 + 4), size: 22, weight: .semibold, color: half.text)
    }

    var y = header
    for group in groups {
        let rowHeight = tallest(group.tiles)
        for half in halves {
            drawLeftText(group.title, in: ctx, origin: CGPoint(x: half.x + margin, y: y + titleHeight / 2), size: 15, weight: .medium, color: half.text)
            var x = half.x + margin
            for tile in group.tiles {
                let w = CGFloat(tile.image.width)
                let h = CGFloat(tile.image.height)
                let width = slot(tile)
                let rect = CGRect(x: x + ((width - w) / 2).rounded(), y: y + titleHeight + rowHeight - h, width: w, height: h)
                drawImage(tile.image, in: ctx, rect: rect)
                let captionTop = y + titleHeight + rowHeight
                drawText(tile.name, in: ctx, center: CGPoint(x: x + width / 2, y: captionTop + 13), size: 12, weight: .semibold, color: half.dim)
                drawText(tile.detail, in: ctx, center: CGPoint(x: x + width / 2, y: captionTop + 29), size: 11, weight: .regular, color: half.dim)
                x += width + gap
            }
        }
        y += titleHeight + rowHeight + captionHeight + groupGap
    }
    return canvas.image()
}

func drawLeftText(_ string: String, in ctx: CGContext, origin: CGPoint, size: CGFloat, weight: NSFont.Weight, color: RGBA) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
    ]))
    let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    drawText(string, in: ctx, center: CGPoint(x: origin.x + glyphs.maxX - glyphs.width / 2, y: origin.y), size: size, weight: weight, color: color)
}

/// Draws an image at its pixel size on the y-down canvas, unsmoothed.
func drawImage(_ image: CGImage, in ctx: CGContext, rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

let appTiles = appSizes.filter { $0 <= 512 }.compactMap { size in
    appImages[size].map { Tile(name: "\(size) px", detail: size == 512 ? "(1024 = 512@2x)" : "", image: $0) }
}
let sheet = contactSheet([
    ("App icon · Resources/AppIcon.icns", appTiles),
    ("Stream Deck plugin icon · imgs/plugin/icon", pluginIcons.map(\.tile)),
    ("Stream Deck keys · imgs/actions/{bridge,main}/{off,on} (state 0 = off, 1 = on)", keys.map(\.tile)),
    ("Stream Deck category and action-list icons · white on transparent", glyphs.map(\.tile)),
])
writePNG(sheet, outRoot.appendingPathComponent("docs/images/icons-preview.png"))
print("Wrote icons under \(outRoot.path)")
