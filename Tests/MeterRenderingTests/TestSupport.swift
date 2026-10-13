import AppKit
import Foundation
import MeterCore
@testable import MeterRendering

// Shared fixtures for the MeterRendering tests.

/// A stereo meter reading with explicit bar, peak and readout values.
func makeMeter(
    left: Float,
    right: Float? = nil,
    peak: Float? = nil,
    maxSinceReset: Float? = nil,
    clipped: Bool = false
) -> StripMeterState {
    var meter = StripMeterState()
    let r = right ?? left
    meter.left.bar = left
    meter.left.target = left
    meter.right.bar = r
    meter.right.target = r
    meter.left.peak = peak ?? left
    meter.right.peak = peak ?? r
    meter.left.maxSinceReset = maxSinceReset ?? max(left, peak ?? left)
    meter.right.maxSinceReset = maxSinceReset ?? max(r, peak ?? r)
    meter.left.clipped = clipped
    meter.right.clipped = clipped
    return meter
}

/// A track strip with readable defaults.
func makeStrip(
    _ id: Int64,
    _ name: String,
    color: Int? = nil,
    kind: TrackKind = .audio,
    meter: StripMeterState = .silent,
    focus: StripFocus = .none,
    volume: Double = 0.85,
    isStereo: Bool = true
) -> StripRenderState {
    StripRenderState(
        trackID: TrackID(id),
        name: name,
        color: color.map { MeterCore.RGBColor(hex: $0) },
        kind: kind,
        meter: meter,
        focus: focus,
        volume: volume,
        volumeText: "0.0 dB",
        isStereo: isStereo
    )
}

/// An eight-strip session that exercises every visual state.
func demoSession() -> [StripRenderState] {
    [
        makeStrip(1, "Kick In", color: 0xFF3636, meter: makeMeter(left: 0.97, right: 0.95, peak: 0.99, clipped: true), volume: 0.9),
        makeStrip(2, "Snare Top", color: 0xFFA529, meter: makeMeter(left: 0.84, right: 0.82, peak: 0.88), volume: 0.85),
        makeStrip(3, "Bass DI", color: 0x10A4EE, meter: makeMeter(left: 0.72, right: 0.70, peak: 0.78),
                  focus: StripFocus(isSelected: true), volume: 0.8),
        makeStrip(4, "Rhodes Long Name Here", color: 0xF7F47C, meter: makeMeter(left: 0.55, right: 0.6, peak: 0.66),
                  focus: StripFocus(dim: 0.55, isMuted: true), volume: 0.6),
        makeStrip(5, "Lead Vox", color: 0xD86CE4, meter: makeMeter(left: 0.78, right: 0.77, peak: 0.83),
                  focus: StripFocus(isSoloed: true, isArmed: true), volume: 0.85),
        makeStrip(6, "Gtr", color: 0x3DC300, meter: makeMeter(left: 0.3, right: 0.25, peak: 0.45),
                  focus: StripFocus(dim: 0.65, isMutedViaSolo: true), volume: 0.7, isStereo: false),
        makeStrip(7, "A-Reverb", color: 0x886CE4, kind: .returnTrack, meter: makeMeter(left: 0.62, right: 0.64, peak: 0.7), volume: 0.75),
        makeStrip(8, "Main", kind: .main, meter: makeMeter(left: 0.86, right: 0.87, peak: 0.9), volume: 0.85),
    ]
}

/// Where render tests write their PNGs: `$METER_SNAPSHOT_DIR`, else a temporary folder.
func snapshotDirectory() -> URL {
    let path = ProcessInfo.processInfo.environment["METER_SNAPSHOT_DIR"]
    let url = path.map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("MeterRenderingSnapshots")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// An RGBA pixel.
struct Pixel: Equatable, CustomStringConvertible {
    var r: Int
    var g: Int
    var b: Int
    var a: Int

    var luminance: Double { 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b) }
    var description: String { "rgba(\(r),\(g),\(b),\(a))" }

    var isGreen: Bool { g > 150 && r < 140 && b < 140 }
    var isRed: Bool { r > 190 && g < 110 && b < 110 }
    var isYellow: Bool { r > 190 && g > 150 && b < 110 }
}

/// Reads pixels of a rendered bank by view coordinates (points, origin bottom-left).
struct PixelReader {
    let image: CGImage
    let scale: CGFloat
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    init(_ image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        // Redraw into a known RGBA layout so byte order never depends on the source image.
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        bytes = buffer
        bytesPerRow = width * 4
    }

    /// The pixel under a point in view coordinates.
    func pixel(at point: CGPoint) -> Pixel {
        let x = min(max(Int(point.x * scale), 0), image.width - 1)
        let yFromBottom = min(max(Int(point.y * scale), 0), image.height - 1)
        let row = image.height - 1 - yFromBottom
        let i = row * bytesPerRow + x * 4
        return Pixel(r: Int(bytes[i]), g: Int(bytes[i + 1]), b: Int(bytes[i + 2]), a: Int(bytes[i + 3]))
    }

    /// Every pixel inside a rect in view coordinates.
    func pixels(in rect: CGRect) -> [Pixel] {
        var result: [Pixel] = []
        let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale)
        let y0 = Int(rect.minY * scale), y1 = Int(rect.maxY * scale)
        for y in max(y0, 0)..<min(y1, image.height) {
            for x in max(x0, 0)..<min(x1, image.width) {
                result.append(pixel(at: CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)))
            }
        }
        return result
    }
}

/// Writes a PNG for manual inspection and returns its URL.
@discardableResult
func writeSnapshot(_ image: CGImage, scale: CGFloat, name: String) -> URL? {
    guard let data = BankView.pngData(from: image, scale: scale) else { return nil }
    let url = snapshotDirectory().appendingPathComponent(name)
    try? data.write(to: url)
    return url
}
