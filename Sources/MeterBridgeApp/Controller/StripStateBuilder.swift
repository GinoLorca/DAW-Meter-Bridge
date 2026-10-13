import MeterCore
import MeterRendering

/// Builds the per-frame strip states of a bank from the snapshot and the meter store.
@MainActor
enum StripStateBuilder {
    /// One state per strip: the track's name, colour, buttons and volume from the snapshot, its
    /// ballistics from the store and its dimming from `MixFocus`. Strips with no (known) track are empty.
    /// The volume text is the DAW's own, or the snapshot's volume curve (Live's approximation when the
    /// DAW sent none) when the DAW gave no text.
    static func states(
        for trackIDs: [TrackID?],
        snapshot: BridgeSnapshot,
        store: MeterStore,
        mixFocus: MixFocusSettings
    ) -> [StripRenderState] {
        trackIDs.map { id in
            guard let id, let track = snapshot.track(id) else { return .empty }
            var state = StripRenderState(
                track: track,
                meter: store.state(for: id),
                focus: MixFocus.focus(for: track, selected: snapshot.selected, settings: mixFocus)
            )
            if state.volumeText.isEmpty {
                state.volumeText = (snapshot.volumeCurve ?? .liveApproximation).text(atNormalized: track.volume)
            }
            return state
        }
    }
}
