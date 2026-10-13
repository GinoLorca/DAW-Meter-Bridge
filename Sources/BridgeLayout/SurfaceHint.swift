import Foundation

/// A family of control surface, used to pick the profile that fits the hardware that is connected.
///
/// Stored uppercased, so `"ssl"` and `"SSL"` are the same hint.
public struct SurfaceHint: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// SSL UF8 / UF1 / UC1 (through SSL 360°).
    public static let ssl: SurfaceHint = "SSL"
    /// Behringer WING in DAW-controller mode.
    public static let wing: SurfaceHint = "WING"

    public var description: String { rawValue }

    /// Surface families named by MIDI device or port names, e.g. "SSL V-MIDI Port 1" → `.ssl`,
    /// "WING 1" → `.wing`. Matches whole words, case-insensitively.
    public static func detect(inDeviceNames names: [String]) -> Set<SurfaceHint> {
        var found = Set<SurfaceHint>()
        for name in names {
            let words = Set(name.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            if !words.isDisjoint(with: ["SSL", "UF8", "UF1", "UC1"]) { found.insert(.ssl) }
            if words.contains("WING") { found.insert(.wing) }
        }
        return found
    }

    /// The surface families to pick a profile for, from MIDI device or port names.
    ///
    /// Like `detect`, except that a WING wins over SSL: the WING's MIDI ports exist only while the
    /// console is connected over USB, but SSL 360°'s virtual "SSL V-MIDI" ports exist whenever SSL 360°
    /// runs (it is usually a login item), with or without a UF8. A Mac that moves between the two
    /// studios would otherwise keep the SSL profile in front of the WING.
    public static func connectedFamilies(inDeviceNames names: [String]) -> Set<SurfaceHint> {
        var found = detect(inDeviceNames: names)
        if found.contains(.wing) { found.remove(.ssl) }
        return found
    }
}
