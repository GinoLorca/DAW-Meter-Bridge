import Foundation

/// How well a profile fits the connected hardware; see `isBetter(than:)`.
///
/// Criteria, in order: surface family, number of matched displays, fewest unmatched displays,
/// strength of the display matches, then whether it is the current profile (for stability).
public struct ProfileMatch: Hashable, Sendable {
    /// The scored profile (`LayoutProfile.id`).
    public var profileID: UUID
    /// +1 when the profile's surface hint is among the connected surfaces, -1 when surfaces are
    /// known and it is not, 0 when either side is unknown.
    public var surfaceScore: Int
    /// Saved displays that matched a connected display.
    public var matchedDisplays: Int
    /// Saved displays with no connected match.
    public var unmatchedDisplays: Int
    /// Sum of the `DisplayMatch` raw values of the matched displays.
    public var matchStrength: Int
    /// Whether this is the profile in use now; breaks ties so the bridge does not flip between equals.
    public var isCurrent: Bool

    public init(profileID: UUID, surfaceScore: Int, matchedDisplays: Int, unmatchedDisplays: Int, matchStrength: Int, isCurrent: Bool) {
        self.profileID = profileID
        self.surfaceScore = surfaceScore
        self.matchedDisplays = matchedDisplays
        self.unmatchedDisplays = unmatchedDisplays
        self.matchStrength = matchStrength
        self.isCurrent = isCurrent
    }

    /// True when this profile fits strictly better than `other`. Neither is better when all criteria tie.
    public func isBetter(than other: ProfileMatch) -> Bool {
        if surfaceScore != other.surfaceScore { return surfaceScore > other.surfaceScore }
        if matchedDisplays != other.matchedDisplays { return matchedDisplays > other.matchedDisplays }
        if unmatchedDisplays != other.unmatchedDisplays { return unmatchedDisplays < other.unmatchedDisplays }
        if matchStrength != other.matchStrength { return matchStrength > other.matchStrength }
        return isCurrent && !other.isCurrent
    }
}

/// Picks the layout profile that fits the connected displays and surfaces.
public enum ProfileSelector {
    /// Scores one profile against the connected displays and surface families.
    public static func match(
        _ profile: LayoutProfile,
        connectedDisplays: [DisplayFingerprint],
        surfaces: Set<SurfaceHint>,
        currentProfileID: UUID? = nil
    ) -> ProfileMatch {
        let assignments = DisplayMatcher.assign(profile.displays.map(\.fingerprint), to: connectedDisplays)
        let surfaceScore: Int
        if let hint = profile.surfaceHint, !surfaces.isEmpty {
            surfaceScore = surfaces.contains(hint) ? 1 : -1
        } else {
            surfaceScore = 0
        }
        return ProfileMatch(
            profileID: profile.id,
            surfaceScore: surfaceScore,
            matchedDisplays: assignments.count,
            unmatchedDisplays: profile.displays.count - assignments.count,
            matchStrength: assignments.reduce(0) { $0 + $1.match.rawValue },
            isCurrent: profile.id == currentProfileID
        )
    }

    /// All profiles scored, best first. Equal scores keep the order of `profiles`.
    public static func ranked(
        _ profiles: [LayoutProfile],
        connectedDisplays: [DisplayFingerprint],
        surfaces: Set<SurfaceHint>,
        currentProfileID: UUID? = nil
    ) -> [ProfileMatch] {
        let scored = profiles.enumerated().map { offset, profile in
            (offset, match(profile, connectedDisplays: connectedDisplays, surfaces: surfaces, currentProfileID: currentProfileID))
        }
        return scored.sorted { a, b in
            if a.1.isBetter(than: b.1) { return true }
            if b.1.isBetter(than: a.1) { return false }
            return a.0 < b.0
        }.map(\.1)
    }

    /// The profile that best fits what is connected, or nil when there are no profiles.
    ///
    /// Always returns a profile when one exists, even if nothing matches, so the bridge has something
    /// to show; check `match(_:...)` if a minimum fit is needed.
    public static func bestProfile(
        in profiles: [LayoutProfile],
        connectedDisplays: [DisplayFingerprint],
        surfaces: Set<SurfaceHint>,
        currentProfileID: UUID? = nil
    ) -> LayoutProfile? {
        guard let best = ranked(profiles, connectedDisplays: connectedDisplays, surfaces: surfaces, currentProfileID: currentProfileID).first else {
            return nil
        }
        return profiles.first { $0.id == best.profileID }
    }
}
