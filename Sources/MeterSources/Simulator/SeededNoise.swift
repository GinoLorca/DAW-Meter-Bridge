/// Stateless, seeded pseudo-random numbers: the same inputs always give the same output,
/// so simulated meters depend only on the seed and the musical position.
struct SeededNoise: Hashable, Sendable {
    let seed: UInt64

    /// A uniform value in 0..<1 for the given salt (per track/voice) and event index.
    func unit(_ salt: UInt64, _ index: Int, _ channel: UInt64 = 0) -> Double {
        var x = seed
        x = Self.mix(x ^ (salt &* 0x9E37_79B9_7F4A_7C15))
        x = Self.mix(x ^ (UInt64(bitPattern: Int64(index)) &* 0xC2B2_AE3D_27D4_EB4F))
        x = Self.mix(x ^ (channel &* 0x1656_67B1_9E37_79F9))
        return Double(x >> 11) / Double(1 << 53)
    }

    /// A value in `range` for the given salt and event index.
    func value(in range: ClosedRange<Double>, _ salt: UInt64, _ index: Int, _ channel: UInt64 = 0) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit(salt, index, channel)
    }

    /// True with probability `p`.
    func chance(_ p: Double, _ salt: UInt64, _ index: Int, _ channel: UInt64 = 0) -> Bool {
        unit(salt, index, channel) < p
    }

    /// SplitMix64 finalizer.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
