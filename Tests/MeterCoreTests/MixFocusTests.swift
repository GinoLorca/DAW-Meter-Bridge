import MeterCore
import Testing

/// Mix focus: dimming for mute and solo-implied mute, plus selection and arm flags.
@Suite struct MixFocusTests {
    private let standard = MixFocusSettings.standard

    @Test func plainTrackHasNoFocus() {
        let focus = MixFocus.focus(for: makeTrack(1), selected: nil)
        #expect(focus == .none)
        #expect(focus.dim == 0)
    }

    @Test func mutedTrackDimsByMuteDim() {
        let focus = MixFocus.focus(for: makeTrack(1, isMuted: true), selected: nil)
        #expect(focus.dim == standard.muteDim)
        #expect(focus.isMuted)
        #expect(!focus.isMutedViaSolo)
    }

    @Test func trackSilencedBySomeoneElsesSoloDimsBySoloDim() {
        let focus = MixFocus.focus(for: makeTrack(1, isMutedViaSolo: true), selected: nil)
        #expect(focus.dim == standard.soloDim)
        #expect(focus.isMutedViaSolo)
        #expect(!focus.isMuted)
        #expect(!focus.isSoloed)
    }

    @Test func soloedTrackIsNotDimmed() {
        let focus = MixFocus.focus(for: makeTrack(1, isSoloed: true), selected: nil)
        #expect(focus.dim == 0)
        #expect(focus.isSoloed)
        #expect(!focus.isMutedViaSolo)
    }

    @Test func soloedTrackIgnoresMutedViaSolo() {
        let focus = MixFocus.focus(for: makeTrack(1, isSoloed: true, isMutedViaSolo: true), selected: nil)
        #expect(focus.dim == 0)
        #expect(focus.isSoloed)
        #expect(!focus.isMutedViaSolo)
    }

    @Test func mutedAndSoloImpliedTakesTheStrongerDim() {
        let focus = MixFocus.focus(for: makeTrack(1, isMuted: true, isMutedViaSolo: true), selected: nil)
        #expect(focus.dim == max(standard.muteDim, standard.soloDim))
        #expect(focus.isMuted)
        #expect(focus.isMutedViaSolo)
    }

    @Test func soloedButMutedStillDimsForMute() {
        let focus = MixFocus.focus(for: makeTrack(1, isMuted: true, isSoloed: true), selected: nil)
        #expect(focus.dim == standard.muteDim)
        #expect(focus.isSoloed)
        #expect(focus.isMuted)
    }

    @Test func customSettingsDriveTheDim() {
        let settings = MixFocusSettings(soloDim: 0.3, muteDim: 0.8)
        #expect(MixFocus.focus(for: makeTrack(1, isMuted: true), selected: nil, settings: settings).dim == 0.8)
        #expect(MixFocus.focus(for: makeTrack(1, isMutedViaSolo: true), selected: nil, settings: settings).dim == 0.3)
        let both = makeTrack(1, isMuted: true, isMutedViaSolo: true)
        #expect(MixFocus.focus(for: both, selected: nil, settings: settings).dim == 0.8)
    }

    @Test func zeroDimSettingsTurnDimmingOff() {
        let off = MixFocusSettings(soloDim: 0, muteDim: 0)
        let track = makeTrack(1, isMuted: true, isMutedViaSolo: true)
        let focus = MixFocus.focus(for: track, selected: nil, settings: off)
        #expect(focus.dim == 0)
        #expect(focus.isMuted)
    }

    @Test func selectionMatchesTheSelectedID() {
        let track = makeTrack(7)
        #expect(MixFocus.focus(for: track, selected: TrackID(7)).isSelected)
        #expect(!MixFocus.focus(for: track, selected: TrackID(8)).isSelected)
        #expect(!MixFocus.focus(for: track, selected: nil).isSelected)
    }

    @Test func selectionDoesNotDim() {
        #expect(MixFocus.focus(for: makeTrack(7), selected: TrackID(7)).dim == 0)
    }

    @Test(arguments: [(Bool?.some(true), true), (.some(false), false), (nil, false)])
    func armFollowsTheTrack(armed: Bool?, expected: Bool) {
        let focus = MixFocus.focus(for: makeTrack(1, isArmed: armed), selected: nil)
        #expect(focus.isArmed == expected)
        #expect(focus.dim == 0)
    }

    /// One soloed track: Live reports `muted_via_solo` on the others, but not on a return that
    /// is solo-in-place safe or on the main track, so those stay undimmed.
    @Test func soloScenarioUsesTheDAWsOwnMutedViaSolo() {
        let snapshot = BridgeSnapshot(tracks: [
            makeTrack(1, index: 0, isSoloed: true),
            makeTrack(2, index: 1, isMutedViaSolo: true),
            makeTrack(3, index: 2, isMuted: true, isMutedViaSolo: true),
            makeTrack(4, index: 3, kind: .returnTrack, isArmed: nil),
            makeTrack(5, index: 4, kind: .main, isArmed: nil),
        ], selected: TrackID(2))
        #expect(snapshot.anySoloed)

        let dims = snapshot.tracks.map { MixFocus.focus(for: $0, selected: snapshot.selected).dim }
        #expect(dims == [0, standard.soloDim, max(standard.muteDim, standard.soloDim), 0, 0])
        let selected = snapshot.tracks.filter { MixFocus.focus(for: $0, selected: snapshot.selected).isSelected }
        #expect(selected.map(\.id) == [TrackID(2)])
    }
}
