import MeterCore

/// `tracks`: one part of the full ordered track list.
///
/// The app replaces its list once all `parts` of a `gen` have arrived; see ``TrackListAssembler``.
public struct TracksMessage: WireMessage {
    public static let messageType = "tracks"

    /// Generation; increases on every full-list send.
    public var gen: Int
    /// 0-based index of this part.
    public var part: Int
    /// Number of parts in this generation.
    public var parts: Int
    /// Number of tracks in the whole list.
    public var total: Int
    /// The records in this part, in list order.
    public var items: [WireTrack]

    public init(gen: Int, part: Int, parts: Int, total: Int, items: [WireTrack]) {
        self.gen = gen
        self.part = part
        self.parts = parts
        self.total = total
        self.items = items
    }

    /// Splits a full list into parts the way the script must: at most `maxItems` records per part
    /// and every encoded part at most `maxBytes` bytes. An empty list gives one empty part.
    /// Throws ``BridgeProtocolError/oversized(_:)`` if a single record cannot fit on its own.
    public static func split(
        _ tracks: [WireTrack],
        gen: Int,
        maxItems: Int = WireProtocol.maxItemsPerPart,
        maxBytes: Int = WireProtocol.maxDatagramSize
    ) throws(BridgeProtocolError) -> [TracksMessage] {
        // Size each part with worst-case header numbers so renumbering can't push it over.
        let headerProbe = TracksMessage(gen: gen, part: Int.max, parts: Int.max, total: Int.max, items: [])
        var groups: [[WireTrack]] = []
        var current: [WireTrack] = []
        for track in tracks {
            let candidate = current + [track]
            var probe = headerProbe
            probe.items = candidate
            let fits = candidate.count <= maxItems && (try? WireCodec.encodedSize(probe)).map { $0 <= maxBytes } == true
            if fits {
                current = candidate
                continue
            }
            guard !current.isEmpty else {
                probe.items = [track]
                throw .oversized((try? WireCodec.encodedSize(probe)) ?? Int.max)
            }
            groups.append(current)
            current = [track]
            probe.items = current
            if let size = try? WireCodec.encodedSize(probe), size > maxBytes {
                throw .oversized(size)
            }
        }
        if !current.isEmpty || groups.isEmpty { groups.append(current) }
        return groups.enumerated().map { index, items in
            TracksMessage(gen: gen, part: index, parts: groups.count, total: tracks.count, items: items)
        }
    }
}

/// `track`: one track's complete record changed.
public struct TrackMessage: WireMessage {
    public static let messageType = "track"

    /// Generation of the list this record belongs to.
    public var gen: Int
    /// The complete record (not a diff).
    public var item: WireTrack

    public init(gen: Int, item: WireTrack) {
        self.gen = gen
        self.item = item
    }
}
