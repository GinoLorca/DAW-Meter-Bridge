import MeterCore

/// The track record that appears in `tracks` and `track` messages.
///
/// Wire keys: `id`, `i`, `n`, `c`, `k`, `m`, `s`, `a`, `ms`, `ao`, `vol`, `vs`.
/// `c` and `a` are always written, as `null` when absent.
public struct WireTrack: Codable, Hashable, Sendable {
    /// `id`: Live's `track._live_ptr`, decoded exactly as a 64-bit integer.
    public var id: TrackID
    /// `i`: position in the ordered list (visible tracks, returns, main).
    public var index: Int
    /// `n`: track name.
    public var name: String
    /// `c`: colour as `0xRRGGBB`, or `nil`.
    public var color: Int?
    /// `k`: track kind. Unknown kinds decode as `.audio`.
    public var kind: TrackKind
    /// `m`: muted.
    public var isMuted: Bool
    /// `s`: soloed.
    public var isSoloed: Bool
    /// `a`: armed, `nil` when the track can't be armed.
    public var isArmed: Bool?
    /// `ms`: muted via another track's solo.
    public var isMutedViaSolo: Bool
    /// `ao`: has audio output.
    public var hasAudioOutput: Bool
    /// `vol`: normalized mixer volume 0...1.
    public var volume: Double
    /// `vs`: volume as Live displays it, e.g. "-6.0 dB".
    public var volumeText: String

    public init(
        id: TrackID,
        index: Int,
        name: String,
        color: Int? = nil,
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

    /// The wire record for a model track.
    public init(_ track: TrackInfo) {
        self.init(
            id: track.id,
            index: track.index,
            name: track.name,
            color: track.color?.hex,
            kind: track.kind,
            isMuted: track.isMuted,
            isSoloed: track.isSoloed,
            isArmed: track.isArmed,
            isMutedViaSolo: track.isMutedViaSolo,
            hasAudioOutput: track.hasAudioOutput,
            volume: track.volume,
            volumeText: track.volumeText
        )
    }

    /// The model track for this record.
    public var trackInfo: TrackInfo {
        TrackInfo(
            id: id,
            index: index,
            name: name,
            color: color.map(RGBColor.init(hex:)),
            kind: kind,
            isMuted: isMuted,
            isSoloed: isSoloed,
            isArmed: isArmed,
            isMutedViaSolo: isMutedViaSolo,
            hasAudioOutput: hasAudioOutput,
            volume: volume,
            volumeText: volumeText
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case index = "i"
        case name = "n"
        case color = "c"
        case kind = "k"
        case isMuted = "m"
        case isSoloed = "s"
        case isArmed = "a"
        case isMutedViaSolo = "ms"
        case hasAudioOutput = "ao"
        case volume = "vol"
        case volumeText = "vs"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TrackID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(Int.self, forKey: .color)
        let kindName = try container.decode(String.self, forKey: .kind)
        kind = TrackKind(rawValue: kindName) ?? .audio
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isSoloed = try container.decode(Bool.self, forKey: .isSoloed)
        isArmed = try container.decodeIfPresent(Bool.self, forKey: .isArmed)
        isMutedViaSolo = try container.decode(Bool.self, forKey: .isMutedViaSolo)
        hasAudioOutput = try container.decode(Bool.self, forKey: .hasAudioOutput)
        volume = try container.decode(Double.self, forKey: .volume)
        volumeText = try container.decode(String.self, forKey: .volumeText)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(index, forKey: .index)
        try container.encode(name, forKey: .name)
        try container.encodeNullable(color, forKey: .color)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isSoloed, forKey: .isSoloed)
        try container.encodeNullable(isArmed, forKey: .isArmed)
        try container.encode(isMutedViaSolo, forKey: .isMutedViaSolo)
        try container.encode(hasAudioOutput, forKey: .hasAudioOutput)
        try container.encode(volume, forKey: .volume)
        try container.encode(volumeText, forKey: .volumeText)
    }
}

extension KeyedEncodingContainer {
    /// Encodes the value, or an explicit JSON `null` when it is `nil` (the protocol never omits these keys).
    mutating func encodeNullable<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
