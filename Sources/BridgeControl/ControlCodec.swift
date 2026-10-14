import Foundation

/// A message from a client (the Stream Deck plugin) to the app.
public enum ControlRequest: Hashable, Sendable {
    /// `ctl.sub`: send `ctl.state` to `port` (nil = the port the datagram came from) now and on every
    /// change for the next 6 s. `client` is free text for logs.
    case subscribe(port: UInt16?, client: String?)
    /// `ctl`: switch the bridge or the Main meter.
    case command(ControlCommand)
}

/// Why a datagram is dropped.
public enum ControlCodecError: Error, Hashable, Sendable {
    /// The datagram is `ControlProtocol.maxDatagramSize` bytes or larger.
    case oversized(Int)
    /// `v` is missing or not 1.
    case unsupportedVersion(Int?)
    /// A `t` this version doesn't know.
    case unknownType(String)
    /// Not a valid message; the string says why.
    case malformed(String)
}

/// Turns control datagrams into requests and the app's state into `ctl.state` datagrams.
///
/// One compact JSON object per datagram. Unknown fields are ignored; a wrong `v`, an unknown `t`, an
/// unknown `op` or an `on` that is neither a boolean nor null makes the datagram invalid (it is dropped).
public enum ControlCodec {
    public static let subscribeType = "ctl.sub"
    public static let commandType = "ctl"
    public static let stateType = "ctl.state"

    // MARK: Decoding

    /// Decodes a datagram sent to the app.
    public static func decodeRequest(_ data: Data) throws(ControlCodecError) -> ControlRequest {
        guard data.count < ControlProtocol.maxDatagramSize else { throw .oversized(data.count) }
        let envelope: RequestEnvelope
        do {
            envelope = try JSONDecoder().decode(RequestEnvelope.self, from: data)
        } catch let error as ControlCodecError {
            throw error
        } catch {
            throw .malformed(describe(error))
        }
        return envelope.request
    }

    /// Decodes a `ctl.state` datagram (clients and tests).
    public static func decodeState(_ data: Data) throws(ControlCodecError) -> ControlState {
        guard data.count < ControlProtocol.maxDatagramSize else { throw .oversized(data.count) }
        do {
            return try JSONDecoder().decode(StateEnvelope.self, from: data).state
        } catch let error as ControlCodecError {
            throw error
        } catch {
            throw .malformed(describe(error))
        }
    }

    // MARK: Encoding

    /// `{"v":1,"t":"ctl.state","bridge":…,"main":…,"edit":…,"source":…,"connected":…,"app":…}`
    public static func encode(_ state: ControlState) -> Data {
        encodeObject(StateEnvelope(state: state))
    }

    /// A client's `ctl.sub` or `ctl` (clients and tests). A toggle encodes `"on":null`.
    public static func encode(_ request: ControlRequest) -> Data {
        encodeObject(RequestEnvelope(request: request))
    }

    // MARK: Private

    private static func encodeObject<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Only booleans, short strings and numbers: encoding cannot fail.
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return String(describing: error) }
        switch decodingError {
        case let .keyNotFound(key, _):
            return "missing \(key.stringValue)"
        case let .dataCorrupted(context), let .typeMismatch(_, context), let .valueNotFound(_, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default:
            return String(describing: decodingError)
        }
    }
}

private enum Key: String, CodingKey {
    case v, t, port, client, op, on
    case bridge, main, edit, source, connected, app
}

/// Reads and checks `v` and `t`.
private func readEnvelope(_ c: KeyedDecodingContainer<Key>, expecting types: Set<String>) throws -> String {
    let version: Int? = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? nil
    guard version == ControlProtocol.version else { throw ControlCodecError.unsupportedVersion(version) }
    let type = try c.decode(String.self, forKey: .t)
    guard types.contains(type) else { throw ControlCodecError.unknownType(type) }
    return type
}

private struct RequestEnvelope: Codable {
    var request: ControlRequest

    init(request: ControlRequest) {
        self.request = request
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try readEnvelope(c, expecting: [ControlCodec.subscribeType, ControlCodec.commandType]) {
        case ControlCodec.subscribeType:
            var port: UInt16?
            if let raw = try c.decodeIfPresent(Int.self, forKey: .port) {
                guard (1...Int(UInt16.max)).contains(raw) else {
                    throw ControlCodecError.malformed("port \(raw) is outside 1...65535")
                }
                port = UInt16(raw)
            }
            // Free text for logs; a wrong type is ignored rather than dropping the keep-alive.
            let client = (try? c.decodeIfPresent(String.self, forKey: .client)) ?? nil
            request = .subscribe(port: port, client: client.map { String($0.prefix(64)) })
        default:
            let op = try c.decode(String.self, forKey: .op)
            // `edit` is switched through the URL scheme only.
            guard let target = ControlTarget(rawValue: op), target != .edit else {
                throw ControlCodecError.malformed("unknown op \(op)")
            }
            let on = try c.decodeIfPresent(Bool.self, forKey: .on)
            request = .command(ControlCommand(target, ControlAction(on: on)))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(ControlProtocol.version, forKey: .v)
        switch request {
        case let .subscribe(port, client):
            try c.encode(ControlCodec.subscribeType, forKey: .t)
            try c.encodeIfPresent(port, forKey: .port)
            try c.encodeIfPresent(client, forKey: .client)
        case let .command(command):
            try c.encode(ControlCodec.commandType, forKey: .t)
            try c.encode(command.target.rawValue, forKey: .op)
            if let on = command.action.on {
                try c.encode(on, forKey: .on)
            } else {
                try c.encodeNil(forKey: .on)
            }
        }
    }
}

private struct StateEnvelope: Codable {
    var state: ControlState

    init(state: ControlState) {
        self.state = state
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        _ = try readEnvelope(c, expecting: [ControlCodec.stateType])
        state = ControlState(
            bridge: try c.decode(Bool.self, forKey: .bridge),
            main: try c.decode(Bool.self, forKey: .main),
            edit: try c.decode(Bool.self, forKey: .edit),
            source: try c.decode(String.self, forKey: .source),
            connected: try c.decode(Bool.self, forKey: .connected),
            app: try c.decode(String.self, forKey: .app)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(ControlProtocol.version, forKey: .v)
        try c.encode(ControlCodec.stateType, forKey: .t)
        try c.encode(state.bridge, forKey: .bridge)
        try c.encode(state.main, forKey: .main)
        try c.encode(state.edit, forKey: .edit)
        try c.encode(state.source, forKey: .source)
        try c.encode(state.connected, forKey: .connected)
        try c.encode(state.app, forKey: .app)
    }
}
