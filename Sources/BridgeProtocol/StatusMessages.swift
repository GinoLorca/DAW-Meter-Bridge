import MeterCore

/// `sel`: the selected track.
public struct SelectionMessage: WireMessage {
    public static let messageType = "sel"

    /// Selected track, or `nil` when it isn't in the list (e.g. inside a folded group). Always written.
    public var id: TrackID?

    public init(id: TrackID?) {
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(id, forKey: .id)
    }
}

/// `hb`: heartbeat, sent every second while subscribed.
public struct HeartbeatMessage: WireMessage {
    public static let messageType = "hb"

    /// Increases by one per heartbeat.
    public var seq: Int

    public init(seq: Int) {
        self.seq = seq
    }
}

/// `err`: a diagnostic from the script, e.g. a command it could not apply.
public struct ErrorMessage: WireMessage {
    public static let messageType = "err"

    /// Human-readable description.
    public var msg: String

    public init(msg: String) {
        self.msg = msg
    }
}
