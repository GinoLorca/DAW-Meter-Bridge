/// Constants of the Live ⇄ app wire protocol (docs/PROTOCOL.md).
public enum WireProtocol {
    /// The `v` field every message carries. Messages with another version are dropped.
    public static let version = 1
    /// Port the app listens on for messages from the Remote Script.
    public static let appPort: UInt16 = 47800
    /// Port the Remote Script listens on for messages from the app.
    public static let scriptPort: UInt16 = 47801
    /// Largest datagram either side may send, in bytes (macOS caps UDP at 9216).
    public static let maxDatagramSize = 8192
    /// Largest number of track records in one `tracks` part.
    public static let maxItemsPerPart = 32
    /// Largest number of entries in one `m` message.
    public static let maxMeterEntries = 64
    /// Meter rate the app asks for in `sub`, in messages per second.
    public static let defaultMeterRate = 30
}

/// Why a datagram could not be decoded or a message could not be encoded.
public enum BridgeProtocolError: Error, Hashable, Sendable {
    /// The message's `v` differs from ``WireProtocol/version`` (`nil` when `v` is missing).
    case unsupportedVersion(Int?)
    /// The datagram is not a valid message; the string describes the problem.
    case malformed(String)
    /// The encoded message would exceed ``WireProtocol/maxDatagramSize``; carries its size in bytes.
    case oversized(Int)
}

/// One message type of the protocol. Conforming types encode only their own fields;
/// ``WireCodec`` adds the common `v` and `t` fields.
public protocol WireMessage: Codable, Hashable, Sendable {
    /// The `t` value that identifies this message type on the wire.
    static var messageType: String { get }
}

/// Keys every message carries.
enum EnvelopeKey: String, CodingKey {
    case v
    case t
}

/// Encodes `v` and `t` next to the message's own fields, in the same JSON object.
struct Enveloped<Message: WireMessage>: Encodable {
    let message: Message

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeKey.self)
        try container.encode(WireProtocol.version, forKey: .v)
        try container.encode(Message.messageType, forKey: .t)
        try message.encode(to: encoder)
    }
}
