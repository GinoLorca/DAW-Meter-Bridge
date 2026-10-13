/// How strongly mix state dims a strip, mirroring DAWWAY's "Mix Focus".
public struct MixFocusSettings: Hashable, Sendable, Codable {
    /// Dim amount (0 = none, 1 = invisible) for tracks silenced by someone else's solo.
    public var soloDim: Double
    /// Dim amount for muted tracks.
    public var muteDim: Double

    public init(soloDim: Double = 0.65, muteDim: Double = 0.55) {
        self.soloDim = soloDim
        self.muteDim = muteDim
    }

    public static let standard = MixFocusSettings()
}

/// Visual mix state of one strip.
public struct StripFocus: Hashable, Sendable {
    public var dim: Double
    public var isSelected: Bool
    public var isSoloed: Bool
    public var isMuted: Bool
    public var isMutedViaSolo: Bool
    public var isArmed: Bool

    public init(
        dim: Double = 0,
        isSelected: Bool = false,
        isSoloed: Bool = false,
        isMuted: Bool = false,
        isMutedViaSolo: Bool = false,
        isArmed: Bool = false
    ) {
        self.dim = dim
        self.isSelected = isSelected
        self.isSoloed = isSoloed
        self.isMuted = isMuted
        self.isMutedViaSolo = isMutedViaSolo
        self.isArmed = isArmed
    }

    public static let none = StripFocus()
}

public enum MixFocus {
    /// Focus for a track. Uses the DAW's own `isMutedViaSolo`, so solo-in-place rules
    /// (returns, main, groups) come out exactly as the DAW applies them.
    public static func focus(for track: TrackInfo, selected: TrackID?, settings: MixFocusSettings = .standard) -> StripFocus {
        var dim = 0.0
        if track.isMuted { dim = max(dim, settings.muteDim) }
        if track.isMutedViaSolo && !track.isSoloed { dim = max(dim, settings.soloDim) }
        return StripFocus(
            dim: dim,
            isSelected: track.id == selected,
            isSoloed: track.isSoloed,
            isMuted: track.isMuted,
            isMutedViaSolo: track.isMutedViaSolo && !track.isSoloed,
            isArmed: track.isArmed ?? false
        )
    }
}
