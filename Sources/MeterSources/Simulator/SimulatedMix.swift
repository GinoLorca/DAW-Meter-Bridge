import Foundation
import MeterCore

/// Mixer state of the simulated session, changed by ``BridgeCommand``s the way Live applies them.
struct SimulatedMix: Sendable {
    private(set) var tracks: [TrackInfo]
    private(set) var selected: TrackID?
    /// Parent group index per track index.
    let parents: [Int?]
    let curve: VolumeCurve
    private let positions: [TrackID: Int]

    init(specs: [SimulatedTrackSpec], curve: VolumeCurve = .liveApproximation, selectedIndex: Int? = nil) {
        self.curve = curve
        parents = specs.map(\.group)
        tracks = specs.enumerated().map { index, spec in
            let volume = min(max(spec.volume, 0), 1)
            return TrackInfo(
                id: SimulatedTrackSpec.trackID(at: index),
                index: index,
                name: spec.name,
                color: RGBColor(hex: spec.color),
                kind: spec.kind,
                isArmed: (spec.kind == .audio || spec.kind == .midi) ? false : nil,
                hasAudioOutput: true,
                volume: volume,
                volumeText: curve.text(atNormalized: volume)
            )
        }
        var positions: [TrackID: Int] = [:]
        for (index, track) in tracks.enumerated() { positions[track.id] = index }
        self.positions = positions
        selected = selectedIndex.flatMap { tracks.indices.contains($0) ? tracks[$0].id : nil }
    }

    func index(of id: TrackID) -> Int? { positions[id] }

    /// Not muted and not silenced by someone else's solo.
    func isAudible(_ index: Int) -> Bool {
        !tracks[index].isMuted && !tracks[index].isMutedViaSolo
    }

    /// Linear post-fader gain from the track's volume (0 at -inf).
    func gain(_ index: Int) -> Double {
        guard let db = curve.decibels(atNormalized: tracks[index].volume) else { return 0 }
        return pow(10, db / 20)
    }

    var anySoloed: Bool { tracks.contains { $0.isSoloed } }

    /// Applies a command like Live would. Returns true if anything changed.
    @discardableResult
    mutating func apply(_ command: BridgeCommand) -> Bool {
        guard let index = positions[command.trackID] else { return false }
        let before = (tracks, selected)
        switch command {
        case .select:
            selected = tracks[index].id
        case let .setMute(_, on):
            guard tracks[index].canMute else { return false }
            tracks[index].isMuted = on
        case let .setSolo(_, on, exclusive):
            guard tracks[index].canSolo else { return false }
            // Live's "Exclusive Solo" preference defaults to on, so nil behaves like true.
            if on && exclusive != false {
                for other in tracks.indices where other != index {
                    tracks[other].isSoloed = false
                }
            }
            tracks[index].isSoloed = on
            updateMutedViaSolo()
        case let .setArm(_, on):
            guard tracks[index].canArm else { return false }
            tracks[index].isArmed = on
        case let .setVolume(_, value), let .endVolumeDrag(_, value):
            let volume = value.isNaN ? 0 : min(max(value, 0), 1)
            tracks[index].volume = volume
            tracks[index].volumeText = curve.text(atNormalized: volume)
        }
        return before.0 != tracks || before.1 != selected
    }

    /// Live's solo-in-place: with any solo active, a track is muted via solo unless it, one of its
    /// groups or one of its children is soloed. Returns and Main are never muted via solo.
    private mutating func updateMutedViaSolo() {
        let soloed = Set(tracks.indices.filter { tracks[$0].isSoloed })
        for index in tracks.indices {
            let kind = tracks[index].kind
            guard !soloed.isEmpty, kind != .returnTrack, kind != .main else {
                tracks[index].isMutedViaSolo = false
                continue
            }
            let related = soloed.contains(index)
                || ancestors(of: index).contains { soloed.contains($0) }
                || soloed.contains { ancestors(of: $0).contains(index) }
            tracks[index].isMutedViaSolo = !related
        }
    }

    private func ancestors(of index: Int) -> [Int] {
        var result: [Int] = []
        var current = parents[index]
        while let parent = current, !result.contains(parent) {
            result.append(parent)
            current = parents[parent]
        }
        return result
    }
}
