import CoreGraphics
import Foundation

/// The strip groups shown on one display, keyed by that display's fingerprint.
public struct DisplayLayout: Hashable, Sendable {
    public var fingerprint: DisplayFingerprint
    public var groups: [StripGroup]
    /// Points per millimetre on this display, when known: from a template placement, a two-point
    /// calibration, or EDID. Used to keep physical sizes when the bridge moves to another display.
    public var pointsPerMillimeter: Double?

    public init(fingerprint: DisplayFingerprint, groups: [StripGroup] = [], pointsPerMillimeter: Double? = nil) {
        self.fingerprint = fingerprint
        self.groups = groups
        self.pointsPerMillimeter = pointsPerMillimeter
    }

    /// The display's bounds in display-local points.
    public var bounds: CGRect { fingerprint.bounds }

    /// Index of the group with `id`, if it is on this display.
    public func groupIndex(withID id: UUID) -> Int? {
        groups.firstIndex { $0.id == id }
    }

    /// The same layout with every group frame snapped to the display's device-pixel grid, so 1-pixel LED
    /// gaps, rails and text stay crisp after the frames were scaled.
    public func snappedToPixelGrid() -> DisplayLayout {
        let grid = PixelGrid(scale: fingerprint.backingScale)
        var result = self
        result.groups = groups.map { group in
            var g = group
            g.frame = grid.snap(group.frame)
            return g
        }
        return result
    }

    /// The same layout for the same physical display after its mode changed (new resolution or
    /// "looks like" scaling): frames scale with the point size per axis (then snap to the new mode's
    /// pixel grid), and `pointsPerMillimeter` scales with the width.
    public func adapted(to newFingerprint: DisplayFingerprint) -> DisplayLayout {
        let old = fingerprint.pointSize
        let new = newFingerprint.pointSize
        let sx = old.width > 0 && new.width > 0 ? new.width / old.width : 1
        let sy = old.height > 0 && new.height > 0 ? new.height / old.height : 1
        var result = self
        result.fingerprint = newFingerprint
        result.groups = groups.map { group in
            var g = group
            g.frame = CGRect(
                x: group.frame.minX * sx,
                y: group.frame.minY * sy,
                width: group.frame.width * sx,
                height: group.frame.height * sy
            )
            return g
        }
        result.pointsPerMillimeter = pointsPerMillimeter.map { $0 * Double(sx) }
        return result.snappedToPixelGrid()
    }
}

extension DisplayLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case fingerprint = "display", groups, pointsPerMillimeter = "pointsPerMM"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fingerprint = try c.decode(DisplayFingerprint.self, forKey: .fingerprint)
        groups = try c.decodeIfPresent([StripGroup].self, forKey: .groups) ?? []
        pointsPerMillimeter = try c.decodeIfPresent(Double.self, forKey: .pointsPerMillimeter)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fingerprint, forKey: .fingerprint)
        try c.encode(groups, forKey: .groups)
        try c.encodeIfPresent(pointsPerMillimeter, forKey: .pointsPerMillimeter)
    }
}

/// A named set of display layouts for one setup, e.g. "Bronx — UF8" or "Brooklyn — WING".
public struct LayoutProfile: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var displays: [DisplayLayout]
    /// The surface family this profile is made for; helps pick it automatically.
    public var surfaceHint: SurfaceHint?

    public init(id: UUID = UUID(), name: String, displays: [DisplayLayout] = [], surfaceHint: SurfaceHint? = nil) {
        self.id = id
        self.name = name
        self.displays = displays
        self.surfaceHint = surfaceHint
    }

    /// Every group on every display, in display order.
    public var allGroups: [StripGroup] { displays.flatMap(\.groups) }

    /// Number of Mackie units the groups' `surfaceUnit` bindings use (UF8 layout: 1, WING: 3, none: 0).
    public var surfaceUnitCount: Int {
        allGroups.reduce(0) { count, group in
            if case let .surfaceUnit(index, _) = group.binding, index >= 0, index < Int.max { return max(count, index + 1) }
            return count
        }
    }

    /// Where the group with `id` lives.
    public func location(ofGroup id: UUID) -> (display: Int, group: Int)? {
        for (displayIndex, layout) in displays.enumerated() {
            if let groupIndex = layout.groupIndex(withID: id) {
                return (displayIndex, groupIndex)
            }
        }
        return nil
    }

    /// The group with `id`, on whichever display it is.
    public func group(withID id: UUID) -> StripGroup? {
        location(ofGroup: id).map { displays[$0.display].groups[$0.group] }
    }

    /// Replaces the group with the same id. Returns false if no such group exists.
    @discardableResult
    public mutating func updateGroup(_ group: StripGroup) -> Bool {
        guard let location = location(ofGroup: group.id) else { return false }
        displays[location.display].groups[location.group] = group
        return true
    }

    /// Index of the layout whose fingerprint matches `fingerprint` best, if any matches.
    public func displayIndex(matching fingerprint: DisplayFingerprint) -> Int? {
        var best: (index: Int, match: DisplayMatch)?
        for (index, layout) in displays.enumerated() {
            let match = layout.fingerprint.match(fingerprint)
            if match.isMatch, match > (best?.match ?? .none) {
                best = (index, match)
            }
        }
        return best?.index
    }
}

extension LayoutProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, displays, surfaceHint = "surface"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        displays = try c.decodeIfPresent([DisplayLayout].self, forKey: .displays) ?? []
        surfaceHint = try c.decodeIfPresent(SurfaceHint.self, forKey: .surfaceHint)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(displays, forKey: .displays)
        try c.encodeIfPresent(surfaceHint, forKey: .surfaceHint)
    }
}
