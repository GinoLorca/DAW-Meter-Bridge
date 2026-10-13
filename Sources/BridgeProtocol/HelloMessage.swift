import MeterCore

/// `vc` in `hello`: Live's volume curve as parallel arrays of normalized values and dB (`null` = -inf).
public struct VolumeCurveTable: Codable, Hashable, Sendable {
    /// Normalized fader values, `k/100` for `k = 0...100`.
    public var x: [Double]
    /// dB at each `x`; `nil` is -inf.
    public var db: [Double?]

    public init(x: [Double], db: [Double?]) {
        self.x = x
        self.db = db
    }

    /// Samples `curve` at `count` evenly spaced normalized values from 0 to 1 (101 in the protocol).
    public init(sampling curve: VolumeCurve, count: Int = 101) {
        let steps = max(count - 1, 1)
        let xs = (0...steps).map { Double($0) / Double(steps) }
        self.init(x: xs, db: xs.map { curve.decibels(atNormalized: $0) })
    }

    /// The curve as MeterCore uses it, or `nil` when the arrays don't make a valid curve.
    public var volumeCurve: VolumeCurve? {
        VolumeCurve(normalized: x, decibels: db)
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case db
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        // Arrays of optionals encode `nil` elements as JSON null.
        try container.encode(db, forKey: .db)
    }
}

/// `hello`: sent by the script after a new subscription, before the full state.
public struct HelloMessage: WireMessage {
    public static let messageType = "hello"

    /// Remote Script version, e.g. "0.1.0".
    public var script: String
    /// Live version, e.g. "12.4.6".
    public var live: String
    /// Random id of the script instance. A new value means the app must drop its cached state.
    public var session: Int64
    /// Meter rate the script will actually use, in messages per second.
    public var hz: Int
    /// Volume curve sampled from the main track's volume parameter.
    public var vc: VolumeCurveTable?

    public init(script: String, live: String, session: Int64, hz: Int, vc: VolumeCurveTable?) {
        self.script = script
        self.live = live
        self.session = session
        self.hz = hz
        self.vc = vc
    }

    /// The volume curve from `vc`, if present and valid.
    public var volumeCurve: VolumeCurve? { vc?.volumeCurve }

    private enum CodingKeys: String, CodingKey {
        case script
        case live
        case session
        case hz
        case vc
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(script, forKey: .script)
        try container.encode(live, forKey: .live)
        try container.encode(session, forKey: .session)
        try container.encode(hz, forKey: .hz)
        try container.encodeNullable(vc, forKey: .vc)
    }
}
