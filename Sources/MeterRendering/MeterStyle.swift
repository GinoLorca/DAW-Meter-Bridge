import MeterCore

/// Which colour band a meter value falls in.
public enum MeterZone: Int, Hashable, Sendable, CaseIterable {
    /// Below the yellow threshold (green segments, neutral readout).
    case normal
    /// At or above the yellow threshold (yellow segments, amber readout).
    case warning
    /// At or above the red threshold (red segments and readout).
    case over
}

/// How the meter bridge looks. Persisted with the user's settings, so every field
/// decodes with its default when missing (older files keep loading as fields are added).
public struct MeterStyle: Hashable, Sendable, Codable {
    /// LED segments per meter column. Clamped to 1...200 when drawn.
    public var segmentCount: Int
    /// Gap between segments as a fraction of the segment pitch (0...0.8). At least one device pixel when > 0.
    public var segmentGap: Double
    /// Meter value (DAW meter scale, 0...1) at which segments turn yellow and the readout amber.
    public var yellowThreshold: Float
    /// Meter value at which segments and the readout turn red.
    public var redThreshold: Float
    /// Track name pill below each meter.
    public var showNames: Bool
    /// Small S / M / R buttons under the name.
    public var showButtons: Bool
    /// Numeric peak readout above each meter.
    public var showPeakReadout: Bool
    /// Thin fader rail beside the meter with a cap at the track volume.
    public var showFaderMarker: Bool
    /// Clip LEDs between the readout and the meter.
    public var showClipIndicators: Bool
    /// Bank background (default black).
    public var backgroundColor: RGBColor
    /// Lit colour of segments below the yellow threshold.
    public var greenColor: RGBColor
    /// Lit colour of segments from the yellow threshold.
    public var yellowColor: RGBColor
    /// Lit colour of segments from the red threshold.
    public var redColor: RGBColor
    /// Smallest name font size in points; long names shrink down to this, then truncate.
    public var minNameFontSize: Double
    /// Largest name font size in points, however big the strip is.
    public var maxNameFontSize: Double

    public init(
        segmentCount: Int = 40,
        segmentGap: Double = 0.28,
        yellowThreshold: Float = 0.80,
        redThreshold: Float = 0.92,
        showNames: Bool = true,
        showButtons: Bool = true,
        showPeakReadout: Bool = true,
        showFaderMarker: Bool = true,
        showClipIndicators: Bool = true,
        backgroundColor: RGBColor = RGBColor(hex: 0x000000),
        greenColor: RGBColor = RGBColor(hex: 0x2BE24E),
        yellowColor: RGBColor = RGBColor(hex: 0xFFD21A),
        redColor: RGBColor = RGBColor(hex: 0xFF2E2A),
        minNameFontSize: Double = 8,
        maxNameFontSize: Double = 20
    ) {
        self.segmentCount = segmentCount
        self.segmentGap = segmentGap
        self.yellowThreshold = yellowThreshold
        self.redThreshold = redThreshold
        self.showNames = showNames
        self.showButtons = showButtons
        self.showPeakReadout = showPeakReadout
        self.showFaderMarker = showFaderMarker
        self.showClipIndicators = showClipIndicators
        self.backgroundColor = backgroundColor
        self.greenColor = greenColor
        self.yellowColor = yellowColor
        self.redColor = redColor
        self.minNameFontSize = minNameFontSize
        self.maxNameFontSize = maxNameFontSize
    }

    /// The default DAWWAY-like look: black background, 40 green/yellow/red segments.
    public static let standard = MeterStyle()

    private enum CodingKeys: String, CodingKey {
        case segmentCount, segmentGap, yellowThreshold, redThreshold
        case showNames, showButtons, showPeakReadout, showFaderMarker, showClipIndicators
        case backgroundColor, greenColor, yellowColor, redColor
        case minNameFontSize, maxNameFontSize
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeterStyle.standard
        segmentCount = try c.decodeIfPresent(Int.self, forKey: .segmentCount) ?? d.segmentCount
        segmentGap = try c.decodeIfPresent(Double.self, forKey: .segmentGap) ?? d.segmentGap
        yellowThreshold = try c.decodeIfPresent(Float.self, forKey: .yellowThreshold) ?? d.yellowThreshold
        redThreshold = try c.decodeIfPresent(Float.self, forKey: .redThreshold) ?? d.redThreshold
        showNames = try c.decodeIfPresent(Bool.self, forKey: .showNames) ?? d.showNames
        showButtons = try c.decodeIfPresent(Bool.self, forKey: .showButtons) ?? d.showButtons
        showPeakReadout = try c.decodeIfPresent(Bool.self, forKey: .showPeakReadout) ?? d.showPeakReadout
        showFaderMarker = try c.decodeIfPresent(Bool.self, forKey: .showFaderMarker) ?? d.showFaderMarker
        showClipIndicators = try c.decodeIfPresent(Bool.self, forKey: .showClipIndicators) ?? d.showClipIndicators
        backgroundColor = try c.decodeIfPresent(RGBColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        greenColor = try c.decodeIfPresent(RGBColor.self, forKey: .greenColor) ?? d.greenColor
        yellowColor = try c.decodeIfPresent(RGBColor.self, forKey: .yellowColor) ?? d.yellowColor
        redColor = try c.decodeIfPresent(RGBColor.self, forKey: .redColor) ?? d.redColor
        minNameFontSize = try c.decodeIfPresent(Double.self, forKey: .minNameFontSize) ?? d.minNameFontSize
        maxNameFontSize = try c.decodeIfPresent(Double.self, forKey: .maxNameFontSize) ?? d.maxNameFontSize
    }
}

extension MeterStyle {
    /// `segmentCount` clamped to what the renderer draws (1...200).
    public var effectiveSegmentCount: Int { min(max(segmentCount, 1), 200) }

    /// `segmentGap` clamped to 0...0.8.
    public var effectiveSegmentGap: Double { min(max(segmentGap, 0), 0.8) }

    /// Colour band of a meter value: red from `redThreshold`, yellow from `yellowThreshold`, else green.
    public func zone(for value: Float) -> MeterZone {
        if value >= redThreshold { return .over }
        if value >= yellowThreshold { return .warning }
        return .normal
    }

    /// Colour band of segment `index` (0 = bottom), judged at the segment's midpoint.
    public func zone(ofSegment index: Int) -> MeterZone {
        let n = Float(effectiveSegmentCount)
        return zone(for: (Float(index) + 0.5) / n)
    }

    /// How many segments a meter level lights, counting from the bottom.
    /// Segment `i` lights once the level reaches its midpoint `(i + 0.5) / n`.
    public func litSegments(for level: Float) -> Int {
        guard level.isFinite, level > 0 else { return 0 }
        let n = effectiveSegmentCount
        let lit = Int((min(level, 1) * Float(n)).rounded(.toNearestOrAwayFromZero))
        return min(max(lit, 0), n)
    }

    /// Name font size bounds, ordered and kept positive.
    var nameFontSizeRange: ClosedRange<Double> {
        let low = max(1, min(minNameFontSize, maxNameFontSize))
        let high = max(low, max(minNameFontSize, maxNameFontSize))
        return low...high
    }
}
