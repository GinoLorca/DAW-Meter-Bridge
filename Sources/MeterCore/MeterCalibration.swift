import Foundation

/// Converts a DAW's normalized meter value (0...1) to dBFS for numeric readouts.
///
/// Live documents its meter values only as "0.0 to 1.0", so the exact curve must be measured
/// with test tones (see docs/ARCHITECTURE.md, open items). Meter *height* never uses this;
/// it is drawn in the DAW's own scale so the bridge matches the DAW's meters.
public struct MeterCalibration: Hashable, Sendable, Codable {
    public struct Point: Hashable, Sendable, Codable {
        public var value: Float
        public var decibels: Float

        public init(value: Float, decibels: Float) {
            self.value = value
            self.decibels = decibels
        }
    }

    /// Piecewise-linear table sorted by value. Empty = treat the value as linear amplitude.
    public var points: [Point]
    /// Normalized value at or above which the clip indicator latches (0 dBFS).
    public var clipValue: Float
    /// Whether the table came from a real measurement; readouts show "≈" when false.
    public var isMeasured: Bool

    public init(points: [Point] = [], clipValue: Float = 0.999, isMeasured: Bool = false) {
        self.points = points.sorted { $0.value < $1.value }
        self.clipValue = clipValue
        self.isMeasured = isMeasured
    }

    private enum CodingKeys: String, CodingKey {
        case points, clipValue, isMeasured
    }

    /// Decodes through `init(points:clipValue:isMeasured:)` so a hand-written table is sorted too.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            points: try container.decodeIfPresent([Point].self, forKey: .points) ?? [],
            clipValue: try container.decodeIfPresent(Float.self, forKey: .clipValue) ?? 0.999,
            isMeasured: try container.decodeIfPresent(Bool.self, forKey: .isMeasured) ?? false
        )
    }

    /// Default until measured: value is linear amplitude, so dBFS = 20·log10(value).
    public static let uncalibrated = MeterCalibration()

    /// dBFS for a meter value; nil means silence (-inf).
    public func decibels(for value: Float) -> Float? {
        guard value > 0.000_01 else { return nil }
        guard points.count >= 2 else { return 20 * log10(value) }
        if value <= points.first!.value { return points.first!.decibels }
        if value >= points.last!.value { return points.last!.decibels }
        for (lower, upper) in zip(points, points.dropFirst()) where value <= upper.value {
            let t = (value - lower.value) / (upper.value - lower.value)
            return lower.decibels + t * (upper.decibels - lower.decibels)
        }
        return points.last!.decibels
    }

    /// Readout text such as "-3.2" or "≈-3.2" ("≈" when uncalibrated). Silence is always "-inf",
    /// without "≈", because it is exact whatever the calibration.
    public func readout(for value: Float) -> String {
        let prefix = isMeasured ? "" : "≈"
        guard let db = decibels(for: value) else { return "-inf" }
        if db > -0.05 && db < 0.05 { return prefix + "0.0" }
        return prefix + String(format: "%.1f", db)
    }
}
