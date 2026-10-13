import MeterCore

/// One `[id, left, right]` triple in an `m` message.
public struct WireMeter: Codable, Hashable, Sendable {
    /// The metered track.
    public var id: TrackID
    /// Live's normalized meter value 0...1 (`output_meter_left`).
    public var left: Float
    /// Live's normalized meter value 0...1 (`output_meter_right`).
    public var right: Float

    public init(id: TrackID, left: Float, right: Float) {
        self.id = id
        self.left = left
        self.right = right
    }

    /// The wire triple for a model reading.
    public init(_ level: MeterLevel) {
        self.init(id: level.id, left: level.left, right: level.right)
    }

    /// The model reading.
    public var meterLevel: MeterLevel { MeterLevel(id: id, left: left, right: right) }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(TrackID.self)
        left = try container.decode(Float.self)
        right = try container.decode(Float.self)
        // Extra trailing elements are ignored, like unknown keys elsewhere.
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(left)
        try container.encode(right)
    }
}

/// `m`: meter readings, about `hz` times per second.
public struct MetersMessage: WireMessage {
    public static let messageType = "m"

    /// Increases by one per message.
    public var seq: Int
    /// `d`: the readings.
    public var entries: [WireMeter]

    public init(seq: Int, entries: [WireMeter]) {
        self.seq = seq
        self.entries = entries
    }

    /// An `m` message carrying model readings.
    public init(seq: Int, levels: [MeterLevel]) {
        self.init(seq: seq, entries: levels.map(WireMeter.init))
    }

    /// The readings as MeterCore models them.
    public var levels: [MeterLevel] { entries.map(\.meterLevel) }

    private enum CodingKeys: String, CodingKey {
        case seq
        case entries = "d"
    }
}
