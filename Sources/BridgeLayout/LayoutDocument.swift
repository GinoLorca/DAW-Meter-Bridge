import Foundation

/// Whether the active profile follows the connected hardware or was chosen by the user.
public enum ProfileSelectionMode: String, Hashable, Sendable, Codable {
    /// Re-pick the best profile whenever displays or surfaces change.
    case automatic
    /// Keep the user's choice until they switch back to automatic.
    case manual
}

/// Everything saved in layouts.json.
public struct LayoutDocument: Hashable, Sendable {
    /// Format version this build reads and writes.
    public static let currentVersion = 1

    /// Format version of the document; decoding refuses versions newer than `currentVersion`.
    public var version: Int
    public var profiles: [LayoutProfile]
    /// The profile in use: the user's choice in `.manual` mode, the last automatic pick otherwise.
    public var activeProfileID: UUID?
    public var selectionMode: ProfileSelectionMode

    public init(
        version: Int = LayoutDocument.currentVersion,
        profiles: [LayoutProfile] = [],
        activeProfileID: UUID? = nil,
        selectionMode: ProfileSelectionMode = .automatic
    ) {
        self.version = version
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.selectionMode = selectionMode
    }

    public static let empty = LayoutDocument()

    public var activeProfile: LayoutProfile? { activeProfileID.flatMap(profile(withID:)) }

    public func profile(withID id: UUID) -> LayoutProfile? {
        profiles.first { $0.id == id }
    }

    /// Adds the profile, or replaces the one with the same id.
    public mutating func upsert(_ profile: LayoutProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    /// Removes a profile. If it was active, nothing is active until the next `selectProfile`.
    public mutating func removeProfile(withID id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = nil
            selectionMode = .automatic
        }
    }

    /// The user picks a profile; it stays active until `chooseAutomatically()`.
    /// Returns false (and changes nothing) if the id is unknown.
    @discardableResult
    public mutating func chooseManually(_ id: UUID) -> Bool {
        guard profile(withID: id) != nil else { return false }
        activeProfileID = id
        selectionMode = .manual
        return true
    }

    /// Goes back to following the connected hardware. Call `selectProfile` afterwards to re-pick.
    public mutating func chooseAutomatically() {
        selectionMode = .automatic
    }

    /// Picks the profile to use now and records it in `activeProfileID`.
    ///
    /// In `.manual` mode the user's profile is kept while it exists. Otherwise the best profile for
    /// the connected displays and surface families wins (see `ProfileSelector`), preferring the
    /// current one on a tie so the bridge doesn't flip between equal profiles.
    @discardableResult
    public mutating func selectProfile(connectedDisplays: [DisplayFingerprint], surfaces: Set<SurfaceHint>) -> LayoutProfile? {
        if selectionMode == .manual, let manual = activeProfile {
            return manual
        }
        selectionMode = .automatic
        let best = ProfileSelector.bestProfile(
            in: profiles,
            connectedDisplays: connectedDisplays,
            surfaces: surfaces,
            currentProfileID: activeProfileID
        )
        activeProfileID = best?.id
        return best
    }
}

/// Why a layouts document could not be used. Both cases mean a newer version of the app wrote the
/// file, so `LayoutStore` leaves it untouched instead of treating it as corrupt.
public enum LayoutDocumentError: Error, Equatable, Sendable {
    /// Written by a newer version of the app.
    case unsupportedVersion(Int)
    /// Holds a value this version doesn't know, e.g. a binding type added by a newer version
    /// (described, e.g. "binding type “returns”").
    case unknownValue(String)
}

extension LayoutDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, profiles, activeProfileID = "activeProfile", selectionMode = "selection"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else {
            throw LayoutDocumentError.unsupportedVersion(version)
        }
        profiles = try c.decodeIfPresent([LayoutProfile].self, forKey: .profiles) ?? []
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        if let raw = try c.decodeIfPresent(String.self, forKey: .selectionMode) {
            guard let mode = ProfileSelectionMode(rawValue: raw) else {
                throw LayoutDocumentError.unknownValue("profile selection “\(raw)”")
            }
            selectionMode = mode
        } else {
            selectionMode = .automatic
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(profiles, forKey: .profiles)
        try c.encodeIfPresent(activeProfileID, forKey: .activeProfileID)
        try c.encode(selectionMode, forKey: .selectionMode)
    }
}
