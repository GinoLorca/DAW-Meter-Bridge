import CoreGraphics

/// Pre-drawn LED column bitmaps. Frames never draw: a column shows `unlit` and, above it, the bottom part of `lit`
/// clipped to the current level, so a meter update is one frame change per column.
struct ColumnArt {
    let lit: CGImage
    let unlit: CGImage
}

enum SegmentArtwork {
    /// Draws a column `widthPx` × `heightPx` with the bank's segments, coloured by zone.
    static func make(widthPx: Int, heightPx: Int, segments: [SegmentSpan], scale: CGFloat, style: MeterStyle, palette: Palette) -> ColumnArt? {
        guard widthPx > 0, heightPx > 0,
              let lit = draw(widthPx: widthPx, heightPx: heightPx, segments: segments, scale: scale, style: style, palette: palette, lit: true),
              let unlit = draw(widthPx: widthPx, heightPx: heightPx, segments: segments, scale: scale, style: style, palette: palette, lit: false)
        else { return nil }
        return ColumnArt(lit: lit, unlit: unlit)
    }

    private static func draw(
        widthPx: Int, heightPx: Int, segments: [SegmentSpan], scale: CGFloat,
        style: MeterStyle, palette: Palette, lit: Bool
    ) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: widthPx, height: heightPx, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.setShouldAntialias(true)
        let width = CGFloat(widthPx)
        let sheen = lit ? sheenGradient(space: space) : nil

        for (index, span) in segments.enumerated() {
            let bottom = (span.bottom * scale).rounded()
            let height = (span.top * scale).rounded() - bottom
            guard height > 0 else { continue }
            let rect = CGRect(x: 0, y: bottom, width: width, height: height)
            let radius = min(height * 0.3, width * 0.2, 1.2 * scale)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            let zone = style.zone(ofSegment: index).rawValue

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(lit ? palette.litSegment[zone] : palette.unlitSegment[zone])
            ctx.fill(rect)
            if let sheen {
                // A soft horizontal sheen reads as a rounded LED rather than a flat bar.
                ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
                if height >= 4 {
                    ctx.setFillColor(CGColor.gray(1, alpha: 0.28))
                    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - max(1, scale.rounded()), width: rect.width, height: max(1, scale.rounded())))
                }
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    private static func sheenGradient(space: CGColorSpace) -> CGGradient? {
        CGGradient(
            colorsSpace: space,
            colors: [CGColor.gray(0, alpha: 0.22), CGColor.gray(1, alpha: 0.16), CGColor.gray(1, alpha: 0.04), CGColor.gray(0, alpha: 0.3)] as CFArray,
            locations: [0, 0.32, 0.6, 1]
        )
    }
}
