import MeterCore

// Shared fixtures and comparison helpers for the MeterCore tests.

/// True when two values differ by at most `tolerance`.
func isClose(_ a: Double, _ b: Double, within tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

/// True when two values differ by at most `tolerance`.
func isClose(_ a: Float, _ b: Float, within tolerance: Float = 1e-5) -> Bool {
    abs(a - b) <= tolerance
}

/// dB comparison where `nil` means -inf: both -inf, or both finite and within `tolerance`.
func isSameDecibels(_ a: Double?, _ b: Double?, within tolerance: Double = 1e-9) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return abs(a - b) <= tolerance
    default: return false
    }
}

/// dB comparison where `nil` means -inf: both -inf, or both finite and within `tolerance`.
func isSameDecibels(_ a: Float?, _ b: Float?, within tolerance: Float = 1e-4) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return abs(a - b) <= tolerance
    default: return false
    }
}

/// A track record with readable defaults; only the fields a test cares about need naming.
func makeTrack(
    _ id: Int64,
    index: Int = 0,
    name: String? = nil,
    kind: TrackKind = .audio,
    isMuted: Bool = false,
    isSoloed: Bool = false,
    isArmed: Bool? = false,
    isMutedViaSolo: Bool = false,
    volume: Double = 0.85
) -> TrackInfo {
    TrackInfo(
        id: TrackID(id),
        index: index,
        name: name ?? "Track \(id)",
        kind: kind,
        isMuted: isMuted,
        isSoloed: isSoloed,
        isArmed: isArmed,
        isMutedViaSolo: isMutedViaSolo,
        volume: volume
    )
}
