import CoreGraphics
import Foundation
import MeterCore

/// One borderless panel of `stripCount` equally spaced meters, bound to a source of tracks.
///
/// `frame` is in display-local points with the origin at the display's bottom-left corner (like AppKit),
/// so rearranging displays in System Settings does not move the group relative to its display.
public struct StripGroup: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Shown in edit mode, e.g. "UF8" or "L9-12".
    public var name: String
    /// Where the group's tracks come from.
    public var binding: StripBinding
    /// Number of meters; always at least 1 when read through the geometry helpers.
    public var stripCount: Int
    /// Display-local points, origin bottom-left.
    public var frame: CGRect
    public var isVisible: Bool
    /// Centre-to-centre distance of the faders under this group in millimetres, when it came from a
    /// template (UF8: 38.5). Lets a calibrated group tell how many points a millimetre is on its display.
    public var physicalPitchMillimeters: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        binding: StripBinding,
        stripCount: Int,
        frame: CGRect,
        isVisible: Bool = true,
        physicalPitchMillimeters: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.binding = binding
        self.stripCount = max(1, stripCount)
        self.frame = frame.standardized
        self.isVisible = isVisible
        self.physicalPitchMillimeters = physicalPitchMillimeters
    }

    private var safeStripCount: Int { max(1, stripCount) }

    /// Width of one strip in points (the group's pitch).
    public var stripWidth: CGFloat { frame.width / CGFloat(safeStripCount) }

    /// Strip `index`'s rectangle relative to the group (origin at the group's bottom-left).
    public func localStripFrame(at index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * stripWidth, y: 0, width: stripWidth, height: frame.height)
    }

    /// Strip `index`'s rectangle in display-local points.
    public func stripFrame(at index: Int) -> CGRect {
        localStripFrame(at: index).offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// Display-local x of strip `index`'s centre.
    public func stripCenterX(at index: Int) -> CGFloat {
        frame.minX + (CGFloat(index) + 0.5) * stripWidth
    }

    /// Strip under a display-local x, or nil outside the group.
    public func stripIndex(atX x: CGFloat) -> Int? {
        guard frame.width > 0, x >= frame.minX, x < frame.maxX else { return nil }
        return min(safeStripCount - 1, Int((x - frame.minX) / stripWidth))
    }

    /// Strip under a group-local x (as a view inside the panel sees it), or nil outside the group.
    public func stripIndex(atLocalX x: CGFloat) -> Int? {
        stripIndex(atX: x + frame.minX)
    }

    /// Track on each strip; see `StripBinding.resolve(stripCount:in:)`.
    public func resolveTracks(in snapshot: BridgeSnapshot) -> [TrackID?] {
        binding.resolve(stripCount: safeStripCount, in: snapshot)
    }

    /// Points per millimetre implied by the group's current pitch, when its physical pitch is known.
    /// After a two-point calibration this is a measured display scale.
    public var measuredPointsPerMillimeter: Double? {
        guard let pitch = physicalPitchMillimeters, pitch > 0, stripWidth > 0 else { return nil }
        return Double(stripWidth) / pitch
    }
}

extension StripGroup: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, binding, stripCount = "strips", frame, isVisible = "visible", physicalPitchMillimeters = "pitchMM"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            binding: try c.decode(StripBinding.self, forKey: .binding),
            stripCount: try c.decode(Int.self, forKey: .stripCount),
            frame: try c.decode(CodableRect.self, forKey: .frame).cgRect,
            isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
            physicalPitchMillimeters: try c.decodeIfPresent(Double.self, forKey: .physicalPitchMillimeters)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(binding, forKey: .binding)
        try c.encode(stripCount, forKey: .stripCount)
        try c.encode(CodableRect(frame), forKey: .frame)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encodeIfPresent(physicalPitchMillimeters, forKey: .physicalPitchMillimeters)
    }
}

extension Sequence where Element == StripGroup {
    /// Tracks to list in the protocol's `watch` message: tracks shown by visible groups that the
    /// DAW would not meter on its own. The script already meters every surface strip, the selected
    /// track and the main track (docs/PROTOCOL.md, `m`), so those are left out.
    public func watchedTracks(in snapshot: BridgeSnapshot) -> Set<TrackID> {
        var alreadyMetered = Set<TrackID>()
        for unit in snapshot.units {
            for case let id? in unit.strips { alreadyMetered.insert(id) }
        }
        if let selected = snapshot.selected { alreadyMetered.insert(selected) }
        if let main = snapshot.mainTrack?.id { alreadyMetered.insert(main) }

        var watched = Set<TrackID>()
        for group in self where group.isVisible {
            for case let id? in group.resolveTracks(in: snapshot) where !alreadyMetered.contains(id) {
                watched.insert(id)
            }
        }
        return watched
    }
}
