/// Stable identifier of a DAW track. For Ableton Live this is the track's `_live_ptr`.
public struct TrackID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var rawValue: Int64

    public init(_ rawValue: Int64) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: TrackID, rhs: TrackID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "track#\(rawValue)" }
}

public enum TrackKind: String, Sendable, Codable, CaseIterable {
    case audio
    case midi
    case group
    case returnTrack = "return"
    /// Live's master track (renamed "Main" in Live 12).
    case main
}

/// 8-bit sRGB colour, as Live reports it (`0xRRGGBB`).
public struct RGBColor: Hashable, Sendable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: Int) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    public var hex: Int { Int(red) << 16 | Int(green) << 8 | Int(blue) }
}

/// Everything the bridge knows about one track, except its meter levels.
public struct TrackInfo: Hashable, Sendable {
    public var id: TrackID
    /// Position in the ordered list: visible tracks, then returns, then main.
    public var index: Int
    public var name: String
    public var color: RGBColor?
    public var kind: TrackKind
    public var isMuted: Bool
    public var isSoloed: Bool
    /// `nil` when the track cannot be armed (group, return, main).
    public var isArmed: Bool?
    /// Silenced because another track is soloed (Live's `muted_via_solo`).
    public var isMutedViaSolo: Bool
    public var hasAudioOutput: Bool
    /// Mixer volume, normalized 0...1 as the DAW stores it.
    public var volume: Double
    /// Volume as the DAW displays it, e.g. "-6.0 dB".
    public var volumeText: String

    public init(
        id: TrackID,
        index: Int,
        name: String,
        color: RGBColor? = nil,
        kind: TrackKind = .audio,
        isMuted: Bool = false,
        isSoloed: Bool = false,
        isArmed: Bool? = false,
        isMutedViaSolo: Bool = false,
        hasAudioOutput: Bool = true,
        volume: Double = 0.85,
        volumeText: String = "0.0 dB"
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.color = color
        self.kind = kind
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.isArmed = isArmed
        self.isMutedViaSolo = isMutedViaSolo
        self.hasAudioOutput = hasAudioOutput
        self.volume = volume
        self.volumeText = volumeText
    }

    /// Main has no mute/solo in Live; arm exists only on audio/MIDI tracks.
    public var canMute: Bool { kind != .main }
    public var canSolo: Bool { kind != .main }
    public var canArm: Bool { isArmed != nil && (kind == .audio || kind == .midi) }
}
