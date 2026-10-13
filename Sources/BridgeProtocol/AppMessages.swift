import Foundation
import MeterCore

/// `sub`: subscribe and keep alive; the app sends it every second.
public struct SubscribeMessage: WireMessage {
    public static let messageType = "sub"

    /// Port the script should send to (the app's listening port).
    public var port: UInt16
    /// Requested meter rate in messages per second.
    public var hz: Int
    /// Random value chosen each time the app starts its Live source, the same in every `sub` until
    /// it stops. A new value makes the script resend its full state even within its 5 s timeout.
    /// Not written when nil.
    public var app: Int?

    public init(port: UInt16 = WireProtocol.appPort, hz: Int = WireProtocol.defaultMeterRate, app: Int? = nil) {
        self.port = port
        self.hz = hz
        self.app = app
    }
}

/// `watch`: extra tracks to meter. Replaces the previous list.
public struct WatchMessage: WireMessage {
    public static let messageType = "watch"

    /// Track ids to meter in addition to strips, selection and Main.
    public var ids: [TrackID]

    public init(ids: [TrackID]) {
        self.ids = ids
    }
}

/// `cmd`: a change the app asks Live to make.
///
/// Wire forms (keys never omitted for the op, `excl` written as `null` when unset):
/// `{"op":"select","id":…}`, `{"op":"mute","id":…,"on":…}`,
/// `{"op":"solo","id":…,"on":…,"excl":true|false|null}`, `{"op":"arm","id":…,"on":…}`,
/// `{"op":"vol","id":…,"val":…}`, and for the final value of a drag `{"op":"vol","id":…,"val":…,"end":true}`.
public struct CommandMessage: WireMessage {
    public static let messageType = "cmd"

    /// The `op` values.
    public enum Operation: String, Codable, Sendable, CaseIterable {
        case select
        case mute
        case solo
        case arm
        case volume = "vol"
    }

    /// The change to make.
    public var command: BridgeCommand

    /// A `cmd` for the given command.
    public init(_ command: BridgeCommand) {
        self.command = command
    }

    /// The `op` this command is sent as.
    public var operation: Operation {
        switch command {
        case .select: .select
        case .setMute: .mute
        case .setSolo: .solo
        case .setArm: .arm
        case .setVolume, .endVolumeDrag: .volume
        }
    }

    /// Volume as written to the wire: clamped to 0...1, non-finite values mapped to the nearest end,
    /// rounded to 6 decimals so the JSON stays short.
    public static func wireVolume(_ value: Double) -> Double {
        let clamped: Double
        if value.isNaN {
            clamped = 0
        } else {
            clamped = min(max(value, 0), 1)
        }
        return (clamped * 1_000_000).rounded() / 1_000_000
    }

    private enum CodingKeys: String, CodingKey {
        case op
        case id
        case on
        case excl
        case val
        case end
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opName = try container.decode(String.self, forKey: .op)
        guard let operation = Operation(rawValue: opName) else {
            throw DecodingError.dataCorruptedError(forKey: .op, in: container, debugDescription: "Unknown cmd op \"\(opName)\"")
        }
        let id = try container.decode(TrackID.self, forKey: .id)
        switch operation {
        case .select:
            command = .select(id)
        case .mute:
            command = .setMute(id, try container.decode(Bool.self, forKey: .on))
        case .solo:
            let exclusive = try container.decodeIfPresent(Bool.self, forKey: .excl)
            command = .setSolo(id, try container.decode(Bool.self, forKey: .on), exclusive: exclusive)
        case .arm:
            command = .setArm(id, try container.decode(Bool.self, forKey: .on))
        case .volume:
            let value = try container.decode(Double.self, forKey: .val)
            let end = try container.decodeIfPresent(Bool.self, forKey: .end) ?? false
            command = end ? .endVolumeDrag(id, value) : .setVolume(id, value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation.rawValue, forKey: .op)
        try container.encode(command.trackID, forKey: .id)
        switch command {
        case .select:
            break
        case let .setMute(_, on), let .setArm(_, on):
            try container.encode(on, forKey: .on)
        case let .setSolo(_, on, exclusive):
            try container.encode(on, forKey: .on)
            try container.encodeNullable(exclusive, forKey: .excl)
        case let .setVolume(_, value):
            try container.encode(Self.wireVolume(value), forKey: .val)
        case let .endVolumeDrag(_, value):
            try container.encode(Self.wireVolume(value), forKey: .val)
            try container.encode(true, forKey: .end)
        }
    }
}
