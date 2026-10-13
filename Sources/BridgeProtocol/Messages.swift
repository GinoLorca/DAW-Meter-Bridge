/// A message from the Remote Script to the app.
public enum IncomingMessage: Hashable, Sendable {
    case hello(HelloMessage)
    case tracks(TracksMessage)
    case track(TrackMessage)
    case selection(SelectionMessage)
    case surfaces(SurfacesMessage)
    case meters(MetersMessage)
    case heartbeat(HeartbeatMessage)
    case error(ErrorMessage)
    /// A type this app doesn't know; receivers ignore it.
    case unknown(type: String)

    /// The `t` value of the message.
    public var messageType: String {
        switch self {
        case .hello: HelloMessage.messageType
        case .tracks: TracksMessage.messageType
        case .track: TrackMessage.messageType
        case .selection: SelectionMessage.messageType
        case .surfaces: SurfacesMessage.messageType
        case .meters: MetersMessage.messageType
        case .heartbeat: HeartbeatMessage.messageType
        case .error: ErrorMessage.messageType
        case let .unknown(type): type
        }
    }
}

/// A message from the app to the Remote Script.
public enum OutgoingMessage: Hashable, Sendable {
    case subscribe(SubscribeMessage)
    case watch(WatchMessage)
    case command(CommandMessage)
    /// A type the script side doesn't know; receivers ignore it.
    case unknown(type: String)

    /// The `t` value of the message.
    public var messageType: String {
        switch self {
        case .subscribe: SubscribeMessage.messageType
        case .watch: WatchMessage.messageType
        case .command: CommandMessage.messageType
        case let .unknown(type): type
        }
    }
}

/// Reads `v` and `t`, then decodes the body of a script → app message from the same JSON object.
struct IncomingEnvelope: Decodable {
    let message: IncomingMessage

    init(from decoder: any Decoder) throws {
        let type = try readEnvelope(decoder)
        switch type {
        case HelloMessage.messageType: message = .hello(try HelloMessage(from: decoder))
        case TracksMessage.messageType: message = .tracks(try TracksMessage(from: decoder))
        case TrackMessage.messageType: message = .track(try TrackMessage(from: decoder))
        case SelectionMessage.messageType: message = .selection(try SelectionMessage(from: decoder))
        case SurfacesMessage.messageType: message = .surfaces(try SurfacesMessage(from: decoder))
        case MetersMessage.messageType: message = .meters(try MetersMessage(from: decoder))
        case HeartbeatMessage.messageType: message = .heartbeat(try HeartbeatMessage(from: decoder))
        case ErrorMessage.messageType: message = .error(try ErrorMessage(from: decoder))
        default: message = .unknown(type: type)
        }
    }
}

/// Reads `v` and `t`, then decodes the body of an app → script message from the same JSON object.
struct OutgoingEnvelope: Decodable {
    let message: OutgoingMessage

    init(from decoder: any Decoder) throws {
        let type = try readEnvelope(decoder)
        switch type {
        case SubscribeMessage.messageType: message = .subscribe(try SubscribeMessage(from: decoder))
        case WatchMessage.messageType: message = .watch(try WatchMessage(from: decoder))
        case CommandMessage.messageType: message = .command(try CommandMessage(from: decoder))
        default: message = .unknown(type: type)
        }
    }
}

/// Checks `v` and returns `t`. Throws ``BridgeProtocolError/unsupportedVersion(_:)`` when `v` isn't 1.
private func readEnvelope(_ decoder: any Decoder) throws -> String {
    let container = try decoder.container(keyedBy: EnvelopeKey.self)
    let version = try container.decodeIfPresent(Int.self, forKey: .v)
    guard version == WireProtocol.version else {
        throw BridgeProtocolError.unsupportedVersion(version)
    }
    return try container.decode(String.self, forKey: .t)
}
