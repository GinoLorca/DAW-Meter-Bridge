import CoreGraphics

// Helpers that put geometry on the device pixel grid so 1-pixel lines and LED gaps stay crisp.

/// Rounds a point value to the nearest device pixel at `scale`.
@inline(__always)
func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
    (value * scale).rounded() / scale
}

extension CGRect {
    /// The rect with each edge rounded to the nearest device pixel at `scale`.
    func pixelAligned(scale: CGFloat) -> CGRect {
        let x0 = MeterRendering.pixelAligned(minX, scale: scale)
        let y0 = MeterRendering.pixelAligned(minY, scale: scale)
        let x1 = MeterRendering.pixelAligned(maxX, scale: scale)
        let y1 = MeterRendering.pixelAligned(maxY, scale: scale)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// A rect of `width` × `height` centred on `center`, pixel aligned.
    static func centered(at center: CGPoint, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            .pixelAligned(scale: scale)
    }
}
