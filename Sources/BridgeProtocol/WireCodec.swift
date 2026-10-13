import Foundation

/// Turns datagrams into messages and messages into datagrams.
///
/// Encoding produces compact UTF-8 JSON (no whitespace, sorted keys so output is deterministic)
/// and refuses anything larger than ``WireProtocol/maxDatagramSize``. Decoding ignores unknown
/// fields, maps unknown `t` values to `.unknown(type:)` and rejects any `v` other than 1.
public enum WireCodec {
    // MARK: Decoding

    /// Decodes a datagram from the script.
    public static func decodeIncoming(_ data: Data) throws(BridgeProtocolError) -> IncomingMessage {
        try decode(IncomingEnvelope.self, from: data).message
    }

    /// Decodes a datagram from the app (used by fake scripts in tests and by diagnostics).
    public static func decodeOutgoing(_ data: Data) throws(BridgeProtocolError) -> OutgoingMessage {
        try decode(OutgoingEnvelope.self, from: data).message
    }

    // MARK: Encoding

    /// Encodes one message with its `v` and `t` fields.
    public static func encode<Message: WireMessage>(_ message: Message) throws(BridgeProtocolError) -> Data {
        let data = try encodeUnchecked(message)
        guard data.count <= WireProtocol.maxDatagramSize else { throw .oversized(data.count) }
        return data
    }

    /// Encodes an app → script message.
    public static func encode(_ message: OutgoingMessage) throws(BridgeProtocolError) -> Data {
        switch message {
        case let .subscribe(body): try encode(body)
        case let .watch(body): try encode(body)
        case let .command(body): try encode(body)
        case let .unknown(type): throw .malformed("Cannot encode unknown message type \"\(type)\"")
        }
    }

    /// Encodes a script → app message (used by fake scripts in tests and by the simulator tooling).
    public static func encode(_ message: IncomingMessage) throws(BridgeProtocolError) -> Data {
        switch message {
        case let .hello(body): try encode(body)
        case let .tracks(body): try encode(body)
        case let .track(body): try encode(body)
        case let .selection(body): try encode(body)
        case let .surfaces(body): try encode(body)
        case let .meters(body): try encode(body)
        case let .heartbeat(body): try encode(body)
        case let .error(body): try encode(body)
        case let .unknown(type): throw .malformed("Cannot encode unknown message type \"\(type)\"")
        }
    }

    /// Size in bytes of the encoded message, without the datagram size check.
    public static func encodedSize<Message: WireMessage>(_ message: Message) throws(BridgeProtocolError) -> Int {
        try encodeUnchecked(message).count
    }

    // MARK: Private

    private static func encodeUnchecked<Message: WireMessage>(_ message: Message) throws(BridgeProtocolError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(Enveloped(message: message))
        } catch {
            throw .malformed("Encoding \(Message.messageType) failed: \(error)")
        }
    }

    private static func decode<Envelope: Decodable>(_ type: Envelope.Type, from data: Data) throws(BridgeProtocolError) -> Envelope {
        do {
            return try JSONDecoder().decode(Envelope.self, from: data)
        } catch let error as BridgeProtocolError {
            throw error
        } catch {
            throw .malformed(describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return String(describing: error) }
        switch decodingError {
        case let .keyNotFound(key, context):
            return describe(context, path: context.codingPath + [key])
        case let .dataCorrupted(context),
             let .typeMismatch(_, context),
             let .valueNotFound(_, context):
            return describe(context, path: context.codingPath)
        @unknown default:
            return String(describing: decodingError)
        }
    }

    private static func describe(_ context: DecodingError.Context, path: [any CodingKey]) -> String {
        let joined = path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        return joined.isEmpty ? context.debugDescription : "\(joined): \(context.debugDescription)"
    }
}
