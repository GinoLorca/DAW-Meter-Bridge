import Foundation

/// Mapping between a DAW's normalized fader value (0...1) and decibels,
/// as a monotonic table sampled by the DAW. `nil` dB means -inf.
public struct VolumeCurve: Hashable, Sendable {
    public private(set) var samples: [Sample]

    public struct Sample: Hashable, Sendable {
        public var normalized: Double
        public var decibels: Double?

        public init(normalized: Double, decibels: Double?) {
            self.normalized = normalized
            self.decibels = decibels
        }
    }

    /// Samples are sorted by `normalized`. Returns nil if fewer than two samples have finite dB.
    public init?(samples: [Sample]) {
        let sorted = samples.sorted { $0.normalized < $1.normalized }
        guard sorted.filter({ $0.decibels != nil }).count >= 2 else { return nil }
        self.samples = sorted
    }

    /// Builds the curve from the protocol's parallel arrays (`vc.x`, `vc.db`).
    public init?(normalized: [Double], decibels: [Double?]) {
        guard normalized.count == decibels.count else { return nil }
        self.init(samples: zip(normalized, decibels).map { Sample(normalized: $0, decibels: $1) })
    }

    /// dB at a normalized value, linearly interpolated. nil = -inf.
    public func decibels(atNormalized value: Double) -> Double? {
        let v = min(max(value, samples.first!.normalized), samples.last!.normalized)
        guard let upperIndex = samples.firstIndex(where: { $0.normalized >= v }) else {
            return samples.last!.decibels
        }
        let upper = samples[upperIndex]
        if upperIndex == 0 || upper.normalized == v { return upper.decibels }
        let lower = samples[upperIndex - 1]
        guard let lowerDB = lower.decibels else {
            // Between -inf and the first finite sample: report -inf until the finite sample.
            return v >= upper.normalized ? upper.decibels : nil
        }
        guard let upperDB = upper.decibels else { return nil }
        let t = (v - lower.normalized) / (upper.normalized - lower.normalized)
        return lowerDB + t * (upperDB - lowerDB)
    }

    /// Normalized value for a dB value, linearly interpolated. -inf (nil) maps to the lowest sample.
    public func normalized(atDecibels db: Double?) -> Double {
        guard let db else { return samples.first!.normalized }
        let finite = samples.filter { $0.decibels != nil }
        if db <= finite.first!.decibels! { return finite.first!.normalized }
        if db >= finite.last!.decibels! { return finite.last!.normalized }
        for (lower, upper) in zip(finite, finite.dropFirst()) where db <= upper.decibels! {
            let t = (db - lower.decibels!) / (upper.decibels! - lower.decibels!)
            return lower.normalized + t * (upper.normalized - lower.normalized)
        }
        return finite.last!.normalized
    }

    /// Display text such as "-6.0 dB" or "-inf dB".
    public func text(atNormalized value: Double) -> String {
        guard let db = decibels(atNormalized: value) else { return "-inf dB" }
        // Values that round to zero read "0.0 dB", never "-0.0 dB".
        if db > -0.05 && db < 0.05 { return "0.0 dB" }
        return String(format: "%.1f dB", db)
    }

    /// Approximation of Ableton Live's mixer fader (0.85 = 0 dB, 1.0 = +6 dB).
    /// Used by the simulator and until the DAW reports its real curve.
    public static let liveApproximation: VolumeCurve = {
        var samples: [Sample] = [Sample(normalized: 0, decibels: nil)]
        for k in 1...100 {
            let v = Double(k) / 100
            let db: Double
            if v >= 0.4 {
                db = (v - 0.85) / 0.15 * 6
            } else {
                // Logarithmic tail from -18 dB at 0.4 down to about -70 dB near 0.
                db = -18 + 52 * log10(v / 0.4) / 1.6
            }
            samples.append(Sample(normalized: v, decibels: db))
        }
        return VolumeCurve(samples: samples)!
    }()
}
