import AppKit
import ImageIO
import MeterCore

// Offscreen rendering of a bank to a bitmap or PNG, for tests and the app's --snapshot mode.
extension BankView {
    /// Renders the given states into a bitmap of `size` points at `scale` pixels per point.
    /// `stripCount` defaults to `strips.count`.
    public static func renderImage(
        strips: [StripRenderState],
        style: MeterStyle = .standard,
        size: CGSize,
        scale: CGFloat,
        stripCount: Int? = nil,
        calibration: MeterCalibration = .uncalibrated,
        isEditing: Bool = false
    ) -> CGImage? {
        let view = BankView(frame: CGRect(origin: .zero, size: size), stripCount: stripCount ?? strips.count, style: style)
        view.fixedScale = scale
        view.calibration = calibration
        view.isEditing = isEditing
        view.update(strips: strips)
        return view.renderImage()
    }

    /// PNG of `renderImage(strips:style:size:scale:stripCount:calibration:isEditing:)`, tagged with the scale's DPI.
    public static func renderPNG(
        strips: [StripRenderState],
        style: MeterStyle = .standard,
        size: CGSize,
        scale: CGFloat,
        stripCount: Int? = nil,
        calibration: MeterCalibration = .uncalibrated,
        isEditing: Bool = false
    ) -> Data? {
        guard let image = renderImage(
            strips: strips, style: style, size: size, scale: scale,
            stripCount: stripCount, calibration: calibration, isEditing: isEditing
        ) else { return nil }
        return pngData(from: image, scale: scale)
    }

    /// Renders this view's current state (including any drag overlay) at its current backing scale.
    public func renderImage() -> CGImage? {
        redraw()
        let geometry = env.geometry
        let scale = geometry.scale
        let width = Int((geometry.size.width * scale).rounded())
        let height = Int((geometry.size.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        canvas.render(in: context)
        return context.makeImage()
    }

    /// Encodes a bitmap as PNG. `scale` sets the DPI metadata (72 × scale) so viewers show it at point size.
    public nonisolated static func pngData(from image: CGImage, scale: CGFloat = 1) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * max(scale, 0.01)
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
