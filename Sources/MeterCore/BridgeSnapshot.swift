/// One emulated Mackie device as the DAW sees it (a UF8, an XT, or a WING section),
/// with the track currently shown on each of its strips.
public struct SurfaceUnit: Hashable, Sendable {
    public enum Role: String, Sendable, Codable {
        case main
        case extender = "xt"
    }

    /// 1-based Control Surface slot in the DAW's preferences.
    public var slot: Int
    /// Remote script class, e.g. "MackieControl".
    public var scriptName: String
    public var role: Role
    /// Track on each hardware strip, left to right; `nil` for an empty strip.
    public var strips: [TrackID?]

    public init(slot: Int, scriptName: String, role: Role, strips: [TrackID?]) {
        self.slot = slot
        self.scriptName = scriptName
        self.role = role
        self.strips = strips
    }
}

public enum ConnectionState: Hashable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected(reason: String)

    public var isConnected: Bool { self == .connected }
}

/// Everything the UI needs except meter levels. Replaced as a value on every state change.
public struct BridgeSnapshot: Equatable, Sendable {
    /// Ordered as the DAW orders them: visible tracks, then returns, then main.
    public private(set) var tracks: [TrackInfo]
    public var selected: TrackID?
    /// Mackie units in physical left-to-right order. Empty when no surface is configured.
    public var units: [SurfaceUnit]
    public var connection: ConnectionState
    /// Human-readable problems to surface in the menu (e.g. surface introspection failed).
    public var warnings: [String]
    /// Normalized volume <-> dB mapping reported by the DAW, if known.
    public var volumeCurve: VolumeCurve?

    private var positions: [TrackID: Int]

    public init(
        tracks: [TrackInfo] = [],
        selected: TrackID? = nil,
        units: [SurfaceUnit] = [],
        connection: ConnectionState = .idle,
        warnings: [String] = [],
        volumeCurve: VolumeCurve? = nil
    ) {
        self.tracks = tracks
        self.selected = selected
        self.units = units
        self.connection = connection
        self.warnings = warnings
        self.volumeCurve = volumeCurve
        self.positions = BridgeSnapshot.positions(of: tracks)
    }

    public static let empty = BridgeSnapshot()

    public func track(_ id: TrackID?) -> TrackInfo? {
        guard let id, let position = positions[id] else { return nil }
        return tracks[position]
    }

    public func contains(_ id: TrackID) -> Bool { positions[id] != nil }

    /// Replaces the whole track list.
    public mutating func setTracks(_ newTracks: [TrackInfo]) {
        tracks = newTracks
        positions = BridgeSnapshot.positions(of: newTracks)
    }

    /// Replaces one track's record. Returns false if the id is unknown.
    @discardableResult
    public mutating func updateTrack(_ track: TrackInfo) -> Bool {
        guard let position = positions[track.id] else { return false }
        tracks[position] = track
        return true
    }

    public var anySoloed: Bool { tracks.contains { $0.isSoloed } }

    public var mainTrack: TrackInfo? { tracks.last { $0.kind == .main } }

    private static func positions(of tracks: [TrackInfo]) -> [TrackID: Int] {
        var result: [TrackID: Int] = [:]
        result.reserveCapacity(tracks.count)
        for (position, track) in tracks.enumerated() {
            result[track.id] = position
        }
        return result
    }
}
