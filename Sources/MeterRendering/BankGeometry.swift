import CoreGraphics

/// Vertical extent of one row of a strip, in points from the bank's bottom edge.
public struct Band: Hashable, Sendable {
    public var minY: CGFloat
    public var maxY: CGFloat

    public init(minY: CGFloat, maxY: CGFloat) {
        self.minY = minY
        self.maxY = max(minY, maxY)
    }

    public var height: CGFloat { maxY - minY }
    public var midY: CGFloat { (minY + maxY) / 2 }

    func pixelAligned(scale: CGFloat) -> Band {
        Band(minY: MeterRendering.pixelAligned(minY, scale: scale), maxY: MeterRendering.pixelAligned(maxY, scale: scale))
    }
}

/// One LED segment's vertical extent in points from the meter's bottom edge, on the pixel grid.
public struct SegmentSpan: Hashable, Sendable {
    public var bottom: CGFloat
    public var top: CGFloat

    public var height: CGFloat { top - bottom }
}

/// Where everything in a bank goes for a given view size, strip count, style and backing scale.
///
/// Coordinates are AppKit's: points, origin at the bottom-left of the bank. Rows are shared by all strips;
/// horizontal positions come from `strip(_:)`. Every size and font scales with `unit`, so the same layout works
/// on a 1920×515 bar at 1× and on a short strip along a Retina ultrawide.
public struct BankGeometry: Hashable, Sendable {
    public let size: CGSize
    public let stripCount: Int
    public let scale: CGFloat
    /// Layout unit in points: the smaller of strip width / 9 and bank height / 22.
    public let unit: CGFloat
    /// Each strip's frame in the bank, left to right, pixel aligned and touching.
    public let stripFrames: [CGRect]

    public let readoutBand: Band?
    public let clipBand: Band?
    public let meterBand: Band
    public let nameBand: Band?
    public let buttonBand: Band?
    /// LED segments bottom to top, relative to the meter's bottom edge.
    public let segments: [SegmentSpan]

    public let readoutFontSize: CGFloat
    /// Preferred name size; long names shrink toward the style's minimum.
    public let nameFontSize: CGFloat
    public let minNameFontSize: CGFloat
    public let buttonFontSize: CGFloat
    /// Size of strip numbers and the drag overlay text.
    public let labelFontSize: CGFloat

    // Nominal horizontal sizes in device pixels, shared by every strip so LED artwork can be shared.
    let columnWidthPx: Int
    let columnGapPx: Int
    let railWidthPx: Int
    let railOffsetPx: Int
    let capWidthPx: Int
    let capHeightPx: Int
    let showsFaderMarker: Bool

    public init(size: CGSize, stripCount: Int, style: MeterStyle, scale: CGFloat) {
        let s = max(scale, 0.5)
        let n = max(stripCount, 0)
        let width = max(size.width, 0)
        let height = max(size.height, 0)
        let nominal = n > 0 ? width / CGFloat(n) : width
        let u = max(3, min(nominal / 9, height / 22))

        self.size = CGSize(width: width, height: height)
        self.stripCount = n
        self.scale = s
        self.unit = u
        self.stripFrames = (0..<n).map { i in
            let x0 = MeterRendering.pixelAligned(CGFloat(i) * nominal, scale: s)
            let x1 = MeterRendering.pixelAligned(CGFloat(i + 1) * nominal, scale: s)
            return CGRect(x: x0, y: 0, width: x1 - x0, height: height)
        }

        let fontRange = style.nameFontSizeRange
        readoutFontSize = max(6, 0.9 * u)
        nameFontSize = CGFloat(min(max(Double(0.8 * u), fontRange.lowerBound), fontRange.upperBound))
        minNameFontSize = min(CGFloat(fontRange.lowerBound), nameFontSize)
        buttonFontSize = max(5, 0.62 * u)
        labelFontSize = max(7, 0.72 * u)

        // Rows from the top: readout, clip LEDs; from the bottom: buttons, name. The meter takes the rest.
        var top = height - 0.35 * u
        if style.showPeakReadout {
            let band = Band(minY: top - 1.3 * u, maxY: top).pixelAligned(scale: s)
            readoutBand = band
            top = band.minY - 0.26 * u
        } else {
            readoutBand = nil
        }
        if style.showClipIndicators {
            let band = Band(minY: top - max(0.34 * u, 2 / s), maxY: top).pixelAligned(scale: s)
            clipBand = band
            top = band.minY - 0.42 * u
        } else {
            clipBand = nil
        }
        var bottom = 0.35 * u
        if style.showButtons {
            let band = Band(minY: bottom, maxY: bottom + 1.1 * u).pixelAligned(scale: s)
            buttonBand = band
            bottom = band.maxY + 0.3 * u
        } else {
            buttonBand = nil
        }
        if style.showNames {
            let band = Band(minY: bottom, maxY: bottom + max(1.45 * u, nameFontSize * 1.55)).pixelAligned(scale: s)
            nameBand = band
            bottom = band.maxY + 0.42 * u
        } else {
            nameBand = nil
        }
        let meter = Band(minY: bottom, maxY: max(top, bottom + 1 / s)).pixelAligned(scale: s)
        meterBand = meter
        segments = BankGeometry.segmentSpans(
            heightPx: Int((meter.height * s).rounded()),
            count: style.effectiveSegmentCount,
            gapFraction: style.effectiveSegmentGap,
            scale: s
        )

        let meterWidthPx = Int((min(nominal * 0.44, 4.4 * u) * s).rounded())
        let gapPx = max(1, Int((0.16 * u * s).rounded()))
        columnGapPx = gapPx
        columnWidthPx = max(1, (meterWidthPx - gapPx) / 2)
        railWidthPx = max(1, Int((0.14 * u * s).rounded()))
        railOffsetPx = max(1, Int((0.6 * u * s).rounded()))
        capWidthPx = max(3, Int((1.0 * u * s).rounded()))
        capHeightPx = max(2, Int((0.46 * u * s).rounded()))
        showsFaderMarker = style.showFaderMarker
    }

    /// Height of the meter in points; a vertical drag of this distance moves the volume over its full range.
    public var meterHeight: CGFloat { meterBand.height }

    /// Width of one stereo meter column in points.
    public var columnWidth: CGFloat { CGFloat(columnWidthPx) / scale }

    /// Width of the whole meter (both columns and the gap, or the mono column) in points.
    public var meterWidth: CGFloat { CGFloat(2 * columnWidthPx + columnGapPx) / scale }

    /// Height in points of the top edge of the `count`-th lit segment above the meter bottom (0 when none).
    public func litHeight(segments count: Int) -> CGFloat {
        guard count > 0, !segments.isEmpty else { return 0 }
        return segments[min(count, segments.count) - 1].top
    }

    /// Geometry of strip `index` in strip-local coordinates (origin at the strip's bottom-left).
    public func strip(_ index: Int) -> StripGeometry {
        StripGeometry(bank: self, frame: stripFrames[index])
    }

    /// Splits a meter `heightPx` pixels tall into `count` segments with a pixel gap between them.
    /// Segments differ by at most one pixel and the top segment ends exactly at the meter top.
    static func segmentSpans(heightPx: Int, count: Int, gapFraction: Double, scale: CGFloat) -> [SegmentSpan] {
        guard count > 0, heightPx > 0 else { return [] }
        let roughPitch = Double(heightPx) / Double(count)
        var gapPx = gapFraction > 0 ? max(1, (roughPitch * gapFraction).rounded()) : 0
        if roughPitch - gapPx < 1 { gapPx = 0 }
        let pitch = (Double(heightPx) + gapPx) / Double(count)
        return (0..<count).map { i in
            let bottom = (Double(i) * pitch).rounded()
            let top = min(Double(heightPx), max(bottom, (Double(i) * pitch + pitch - gapPx).rounded()))
            return SegmentSpan(bottom: CGFloat(bottom) / scale, top: CGFloat(top) / scale)
        }
    }
}

/// Where one strip's parts go, in strip-local points (origin at the strip's bottom-left).
public struct StripGeometry: Hashable, Sendable {
    public let bounds: CGRect
    public let centerX: CGFloat
    public let unit: CGFloat
    public let scale: CGFloat

    /// Peak readout box, or nil when hidden.
    public let readout: CGRect?
    /// Clip LEDs above the left and right columns (empty when hidden).
    public let clipLEDs: [CGRect]
    /// Clip LED above the single mono column, or nil when hidden.
    public let monoClipLED: CGRect?
    /// Left and right meter columns.
    public let columns: [CGRect]
    /// The single column used for mono strips; also the full meter area.
    public let monoColumn: CGRect
    /// Fader rail beside the meter, or nil when hidden.
    public let rail: CGRect?
    public let capSize: CGSize
    /// Name pill, or nil when hidden.
    public let name: CGRect?
    /// S, M, R buttons in that order (empty when hidden).
    public let buttons: [CGRect]
    /// Outline drawn for empty strips and the selection highlight.
    public let outline: CGRect

    /// The meter area (both columns).
    public var meter: CGRect { monoColumn }

    init(bank: BankGeometry, frame: CGRect) {
        let s = bank.scale
        let u = bank.unit
        let w = frame.width
        let wPx = Int((w * s).rounded())
        let centerPx = wPx / 2
        let meterPx = 2 * bank.columnWidthPx + bank.columnGapPx
        let leftPx = centerPx - meterPx / 2
        func pts(_ px: Int) -> CGFloat { CGFloat(px) / s }

        bounds = CGRect(x: 0, y: 0, width: w, height: frame.height)
        centerX = pts(centerPx)
        unit = u
        scale = s

        let meterBand = bank.meterBand
        let left = CGRect(x: pts(leftPx), y: meterBand.minY, width: pts(bank.columnWidthPx), height: meterBand.height)
        let right = CGRect(
            x: pts(leftPx + bank.columnWidthPx + bank.columnGapPx), y: meterBand.minY,
            width: pts(bank.columnWidthPx), height: meterBand.height
        )
        columns = [left, right]
        monoColumn = CGRect(x: pts(leftPx), y: meterBand.minY, width: pts(meterPx), height: meterBand.height)

        if let clip = bank.clipBand {
            clipLEDs = [
                CGRect(x: left.minX, y: clip.minY, width: left.width, height: clip.height),
                CGRect(x: right.minX, y: clip.minY, width: right.width, height: clip.height),
            ]
            monoClipLED = CGRect(x: monoColumn.minX, y: clip.minY, width: monoColumn.width, height: clip.height)
        } else {
            clipLEDs = []
            monoClipLED = nil
        }

        capSize = CGSize(width: pts(bank.capWidthPx), height: pts(bank.capHeightPx))
        if bank.showsFaderMarker {
            var railPx = leftPx + meterPx + bank.railOffsetPx
            let limitPx = wPx - 1 - bank.capWidthPx / 2 - (bank.railWidthPx + 1) / 2
            railPx = min(railPx, max(leftPx + meterPx + 1, limitPx))
            rail = CGRect(x: pts(railPx), y: meterBand.minY, width: pts(bank.railWidthPx), height: meterBand.height)
        } else {
            rail = nil
        }

        let center = CGPoint(x: pts(centerPx), y: 0)
        let pillWidth = max(1, min(w - 0.5 * u, 9 * u))
        if let band = bank.readoutBand {
            let boxWidth = max(1, min(w - 0.5 * u, max(bank.meterWidth + 1.4 * u, 5 * u)))
            readout = CGRect.centered(at: CGPoint(x: center.x, y: band.midY), width: boxWidth, height: band.height, scale: s)
        } else {
            readout = nil
        }
        if let band = bank.nameBand {
            name = CGRect.centered(at: CGPoint(x: center.x, y: band.midY), width: pillWidth, height: band.height, scale: s)
        } else {
            name = nil
        }
        if let band = bank.buttonBand {
            let gap = 0.26 * u
            let buttonWidth = max(1, min((pillWidth - 2 * gap) / 3, 2.1 * u))
            let total = 3 * buttonWidth + 2 * gap
            let startX = center.x - total / 2
            buttons = (0..<3).map { k in
                CGRect(x: startX + CGFloat(k) * (buttonWidth + gap), y: band.minY, width: buttonWidth, height: band.height)
                    .pixelAligned(scale: s)
            }
        } else {
            buttons = []
        }
        outline = bounds.insetBy(dx: 0.1 * u, dy: 0.1 * u).pixelAligned(scale: s)
    }

    /// Fader cap rect for a normalized volume: centred on the rail at `volume` of the meter height.
    public func capRect(volume: Double) -> CGRect {
        let v = CGFloat(min(max(volume.isFinite ? volume : 0, 0), 1))
        let x = rail?.midX ?? meter.maxX
        let y = meter.minY + v * meter.height
        return CGRect.centered(at: CGPoint(x: x, y: y), width: capSize.width, height: capSize.height, scale: scale)
    }
}
