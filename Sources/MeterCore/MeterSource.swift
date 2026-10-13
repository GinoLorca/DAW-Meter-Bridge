import Foundation

/// A change the bridge asks the DAW to make.
public enum BridgeCommand: Hashable, Sendable {
    case select(TrackID)
    case setMute(TrackID, Bool)
    /// `exclusive`: true = unsolo others, false = additive, nil = follow the DAW's preference.
    case setSolo(TrackID, Bool, exclusive: Bool?)
    case setArm(TrackID, Bool)
    /// Normalized 0...1 mixer volume, one step of a drag.
    case setVolume(TrackID, Double)
    /// The final normalized 0...1 volume of a drag (mouse up). Sets it like ``setVolume(_:_:)`` and
    /// ends the drag, so the DAW records the whole drag as one gesture and one undo step.
    case endVolumeDrag(TrackID, Double)

    public var trackID: TrackID {
        switch self {
        case let .select(id), let .setMute(id, _), let .setSolo(id, _, _), let .setArm(id, _), let .setVolume(id, _),
             let .endVolumeDrag(id, _):
            return id
        }
    }
}

/// One meter reading in the DAW's own normalized meter scale (0...1).
public struct MeterLevel: Hashable, Sendable {
    public var id: TrackID
    public var left: Float
    public var right: Float

    public init(id: TrackID, left: Float, right: Float) {
        self.id = id
        self.left = left
        self.right = right
    }
}

@MainActor
public protocol MeterSourceDelegate: AnyObject {
    /// Track list, selection, surfaces, connection or warnings changed.
    func meterSource(_ source: any MeterSource, didUpdate snapshot: BridgeSnapshot)
    /// New meter readings. `time` is `ProcessInfo.processInfo.systemUptime` at arrival.
    func meterSource(_ source: any MeterSource, didReceive levels: [MeterLevel], at time: TimeInterval)
}

/// Where tracks, state and meters come from: the simulator or Ableton Live.
@MainActor
public protocol MeterSource: AnyObject {
    var displayName: String { get }
    var delegate: (any MeterSourceDelegate)? { get set }
    var snapshot: BridgeSnapshot { get }

    func start()
    func stop()
    func send(_ command: BridgeCommand)
    /// Tracks shown on the bridge that are not on a surface strip; the source meters these too.
    func setWatchedTracks(_ ids: Set<TrackID>)
}
