import MeterCore

/// Where a strip group gets its tracks from.
public enum StripBinding: Hashable, Sendable {
    /// Strips of one hardware unit, starting at `firstStrip` (0-based), e.g. the UF8 is `surfaceUnit(index: 0, firstStrip: 0)`
    /// and the WING's C1–4 section is `surfaceUnit(index: 1, firstStrip: 4)`. `index` follows `BridgeSnapshot.units`.
    case surfaceUnit(index: Int, firstStrip: Int)
    /// One meter showing the DAW's selected track, e.g. above the UF1.
    case selectedTrack
    /// One meter showing the main (master) track.
    case mainTrack
    /// Consecutive tracks of the ordered track list, starting at `offset` (0-based).
    case trackList(offset: Int)

    /// Strips per Mackie unit; also the stride of the no-surface fallback.
    public static let stripsPerUnit = 8
    /// Surface unit indices a layout may use (a Mackie setup has at most 8 units; generous margin).
    public static let unitRange = 0...63
    /// Track-list offsets a layout may use.
    public static let offsetRange = 0...9_999

    /// True for bindings that show a single track (`selectedTrack`, `mainTrack`).
    public var isSingleTrack: Bool {
        switch self {
        case .selectedTrack, .mainTrack: return true
        case .surfaceUnit, .trackList: return false
        }
    }

    /// Most strips that can resolve to a track, or nil when unbounded (`trackList`).
    /// Strips past this always resolve to nil.
    public var maximumStripCount: Int? {
        switch self {
        case let .surfaceUnit(_, firstStrip): return max(0, Self.stripsPerUnit - firstStrip)
        case .selectedTrack, .mainTrack: return 1
        case .trackList: return nil
        }
    }

    /// Track on each of `stripCount` strips, left to right; nil for an empty strip.
    ///
    /// - `surfaceUnit(i, f)`: strip k shows `snapshot.units[i].strips[f + k]`. When `snapshot.units` is
    ///   empty (no surface configured), it falls back to `snapshot.tracks[i * 8 + f + k]`, so a layout
    ///   made for a surface still works with the simulator or a bare Live set. Strips past the unit's
    ///   last strip (or past 8 in the fallback) are nil.
    /// - `selectedTrack` / `mainTrack`: strip 0 shows the track, further strips are nil.
    /// - `trackList(offset)`: strip k shows `snapshot.tracks[offset + k]`.
    ///
    /// IDs are returned as the snapshot reports them; look them up with `BridgeSnapshot.track(_:)`.
    public func resolve(stripCount: Int, in snapshot: BridgeSnapshot) -> [TrackID?] {
        guard stripCount > 0 else { return [] }
        switch self {
        case let .surfaceUnit(index, firstStrip):
            if snapshot.units.isEmpty {
                return (0..<stripCount).map { k in
                    let (strip, overflow) = firstStrip.addingReportingOverflow(k)
                    // Bounded before multiplying, so a damaged layout can't overflow (and trap).
                    guard !overflow, Self.unitRange.contains(index), strip >= 0, strip < Self.stripsPerUnit else { return nil }
                    return Self.track(at: index * Self.stripsPerUnit + strip, in: snapshot)
                }
            }
            guard snapshot.units.indices.contains(index) else {
                return Array(repeating: nil, count: stripCount)
            }
            let strips = snapshot.units[index].strips
            return (0..<stripCount).map { k in
                let (strip, overflow) = firstStrip.addingReportingOverflow(k)
                return !overflow && strips.indices.contains(strip) ? strips[strip] : nil
            }
        case .selectedTrack:
            return [snapshot.selected] + Array(repeating: nil, count: stripCount - 1)
        case .mainTrack:
            return [snapshot.mainTrack?.id] + Array(repeating: nil, count: stripCount - 1)
        case let .trackList(offset):
            return (0..<stripCount).map { k in
                let (position, overflow) = offset.addingReportingOverflow(k)
                return overflow ? nil : Self.track(at: position, in: snapshot)
            }
        }
    }

    private static func track(at position: Int, in snapshot: BridgeSnapshot) -> TrackID? {
        snapshot.tracks.indices.contains(position) ? snapshot.tracks[position].id : nil
    }
}

extension StripBinding: Codable {
    // {"type":"surfaceUnit","unit":0,"firstStrip":4} | {"type":"selectedTrack"} | {"type":"mainTrack"} | {"type":"trackList","offset":16}
    private enum CodingKeys: String, CodingKey {
        case type, unit, firstStrip, offset
    }

    private enum Kind: String, Codable {
        case surfaceUnit, selectedTrack, mainTrack, trackList
    }

    /// An unknown `type` (added by a newer version) throws `LayoutDocumentError.unknownValue`, so the
    /// file is kept as it is; out-of-range numbers (a damaged or mistyped file) are a decoding error.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: type) else {
            throw LayoutDocumentError.unknownValue("binding type “\(type)”")
        }
        func checked(_ key: CodingKeys, _ value: Int, in range: ClosedRange<Int>) throws -> Int {
            guard range.contains(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: c, debugDescription: "\(value) is outside \(range.lowerBound)...\(range.upperBound)"
                )
            }
            return value
        }
        switch kind {
        case .surfaceUnit:
            self = .surfaceUnit(
                index: try checked(.unit, try c.decode(Int.self, forKey: .unit), in: Self.unitRange),
                firstStrip: try checked(.firstStrip, try c.decodeIfPresent(Int.self, forKey: .firstStrip) ?? 0, in: 0...(Self.stripsPerUnit - 1))
            )
        case .selectedTrack:
            self = .selectedTrack
        case .mainTrack:
            self = .mainTrack
        case .trackList:
            self = .trackList(offset: try checked(.offset, try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0, in: Self.offsetRange))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .surfaceUnit(index, firstStrip):
            try c.encode(Kind.surfaceUnit, forKey: .type)
            try c.encode(index, forKey: .unit)
            try c.encode(firstStrip, forKey: .firstStrip)
        case .selectedTrack:
            try c.encode(Kind.selectedTrack, forKey: .type)
        case .mainTrack:
            try c.encode(Kind.mainTrack, forKey: .type)
        case let .trackList(offset):
            try c.encode(Kind.trackList, forKey: .type)
            try c.encode(offset, forKey: .offset)
        }
    }
}
