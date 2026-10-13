import MeterCore

/// The musical part a simulated track plays; decides how its meter moves.
/// The raw value seeds the voice's random pattern, so keep existing values stable.
enum SimulatedVoice: UInt64, Hashable, Sendable {
    case kick = 1, snare, clap, hats, openHat, toms, overheads, room, perc, shaker
    case bass, subBass
    case keys, rhodes, piano, pad, strings, leadSynth, arp
    case electricGuitar, acousticGuitar
    case leadVocal, doubleVocal, backingVocal, adlib
    case riser, impact, noiseBed
    /// Sum of its child tracks.
    case group
    case reverbReturn, delayReturn
    /// Sum of everything.
    case main
}

/// One track of the simulated session.
struct SimulatedTrackSpec: Hashable, Sendable {
    var name: String
    var kind: TrackKind
    /// Live palette colour, `0xRRGGBB`.
    var color: Int
    var voice: SimulatedVoice
    /// Initial normalized fader value (0.85 = 0 dB).
    var volume: Double
    /// -1 (left) ... +1 (right).
    var pan: Double = 0
    /// Index of the parent group track in the spec list.
    var group: Int?
    /// Slight left/right difference for stereo sources.
    var width: Double = 0
}

extension SimulatedTrackSpec {
    /// A 32-track pop/rock session with two groups, two returns and Main, in Live's order
    /// (visible tracks, then returns, then main). Colours come from Live's palette.
    static let defaultSession: [SimulatedTrackSpec] = [
        // 0: drums group and its children
        .init(name: "Drums", kind: .group, color: 0xFF3636, voice: .group, volume: 0.85),
        .init(name: "Kick", kind: .audio, color: 0xFF3636, voice: .kick, volume: 0.85, group: 0),
        .init(name: "Snare", kind: .audio, color: 0xE2675A, voice: .snare, volume: 0.83, group: 0),
        .init(name: "Clap", kind: .audio, color: 0xFF94A6, voice: .clap, volume: 0.78, group: 0),
        .init(name: "Hats", kind: .audio, color: 0xFFA529, voice: .hats, volume: 0.79, pan: 0.25, group: 0),
        .init(name: "Open Hat", kind: .audio, color: 0xFFA374, voice: .openHat, volume: 0.76, pan: 0.3, group: 0),
        .init(name: "Toms", kind: .audio, color: 0xF66C03, voice: .toms, volume: 0.80, group: 0, width: 0.2),
        .init(name: "Overheads", kind: .audio, color: 0xCC9927, voice: .overheads, volume: 0.78, group: 0, width: 0.12),
        .init(name: "Room", kind: .audio, color: 0x99724B, voice: .room, volume: 0.74, group: 0, width: 0.1),
        // 9: percussion
        .init(name: "Perc", kind: .midi, color: 0xFFF034, voice: .perc, volume: 0.77, pan: -0.35),
        .init(name: "Shaker", kind: .audio, color: 0xF7F47C, voice: .shaker, volume: 0.75, pan: 0.4),
        // 11: bass
        .init(name: "Bass", kind: .audio, color: 0x886CE4, voice: .bass, volume: 0.84),
        .init(name: "Sub Bass", kind: .midi, color: 0x5480E4, voice: .subBass, volume: 0.80),
        // 13: keys and synths
        .init(name: "Keys", kind: .midi, color: 0x10A4EE, voice: .keys, volume: 0.79, width: 0.08),
        .init(name: "Rhodes", kind: .midi, color: 0x19E9FF, voice: .rhodes, volume: 0.78, pan: -0.2, width: 0.06),
        .init(name: "Piano", kind: .audio, color: 0x8BC5FF, voice: .piano, volume: 0.80, width: 0.1),
        .init(name: "Pad", kind: .midi, color: 0x00BFAF, voice: .pad, volume: 0.76, width: 0.12),
        .init(name: "Strings", kind: .midi, color: 0x25FFA8, voice: .strings, volume: 0.77, width: 0.1),
        .init(name: "Lead Synth", kind: .midi, color: 0xD86CE4, voice: .leadSynth, volume: 0.80, pan: 0.1),
        .init(name: "Arp", kind: .midi, color: 0xE553A0, voice: .arp, volume: 0.75, width: 0.15),
        // 20: guitars
        .init(name: "Gtr L", kind: .audio, color: 0x87FF67, voice: .electricGuitar, volume: 0.79, pan: -0.7),
        .init(name: "Gtr R", kind: .audio, color: 0x3DC300, voice: .electricGuitar, volume: 0.79, pan: 0.7),
        .init(name: "Ac Gtr", kind: .audio, color: 0xBFFB00, voice: .acousticGuitar, volume: 0.77, pan: -0.15),
        // 23: vocal group and its children
        .init(name: "Vox", kind: .group, color: 0x5CFFE8, voice: .group, volume: 0.85),
        .init(name: "Lead Vox", kind: .audio, color: 0x5CFFE8, voice: .leadVocal, volume: 0.85, group: 23),
        .init(name: "Lead Dbl", kind: .audio, color: 0xCDF1F8, voice: .doubleVocal, volume: 0.76, group: 23),
        .init(name: "BGV L", kind: .audio, color: 0x92A7FF, voice: .backingVocal, volume: 0.77, pan: -0.55, group: 23),
        .init(name: "BGV R", kind: .audio, color: 0xB9C1E3, voice: .backingVocal, volume: 0.77, pan: 0.55, group: 23),
        .init(name: "Adlib", kind: .audio, color: 0xB677C6, voice: .adlib, volume: 0.78, pan: 0.2, group: 23),
        // 29: effects
        .init(name: "FX Riser", kind: .audio, color: 0xFF39D4, voice: .riser, volume: 0.77, width: 0.2),
        .init(name: "Impacts", kind: .audio, color: 0xE5DCE1, voice: .impact, volume: 0.79, width: 0.1),
        .init(name: "Vinyl", kind: .audio, color: 0xA9A9A9, voice: .noiseBed, volume: 0.72, width: 0.2),
        // 32: returns and main
        .init(name: "A Reverb", kind: .returnTrack, color: 0xCDBBE4, voice: .reverbReturn, volume: 0.79, width: 0.15),
        .init(name: "B Delay", kind: .returnTrack, color: 0xAE98E5, voice: .delayReturn, volume: 0.77, width: 0.2),
        .init(name: "Main", kind: .main, color: 0xD0D0D0, voice: .main, volume: 0.85),
    ]

    /// Stable simulator id for the track at `index`: pointer-like values above 2^32 so the
    /// app exercises 64-bit ids the way it does with Live.
    static func trackID(at index: Int) -> TrackID {
        TrackID(0x6000_0000_0000 + Int64(index) * 0x2A0)
    }
}
