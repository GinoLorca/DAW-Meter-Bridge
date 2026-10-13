import Foundation

/// The song the simulator "plays": a 32-bar loop (intro, verse, chorus, breakdown, chorus)
/// and a pre-fader mono envelope per voice. Everything is a pure function of the seed and the
/// musical position in beats, so the same seed and position always give the same level.
struct SimulatedMusic: Sendable {
    enum Section: Hashable, Sendable {
        case intro, verse, chorus, breakdown
    }

    static let loopBars = 32
    static let beatsPerBar = 4.0

    let noise: SeededNoise

    init(seed: UInt64) {
        noise = SeededNoise(seed: seed)
    }

    /// Section of a bar: 0–3 intro, 4–11 verse, 12–19 chorus, 20–23 breakdown, 24–31 chorus.
    static func section(ofBar bar: Int) -> Section {
        switch loopBar(bar) {
        case 0..<4: .intro
        case 4..<12: .verse
        case 12..<20: .chorus
        case 20..<24: .breakdown
        default: .chorus
        }
    }

    static func loopBar(_ bar: Int) -> Int {
        ((bar % loopBars) + loopBars) % loopBars
    }

    /// Pre-fader mono level (about 0...1.15) of `voice` at `beat`.
    /// `variant` separates two tracks playing the same part (e.g. Gtr L / Gtr R).
    func amplitude(_ voice: SimulatedVoice, at beat: Double, variant: Int = 0) -> Double {
        guard beat >= 0 else { return 0 }
        let salt = voice.rawValue &* 0x100 &+ UInt64(variant)
        let bar = Int(floor(beat / Self.beatsPerBar))
        let loopBar = Self.loopBar(bar)
        let section = Self.section(ofBar: bar)
        let pos = beat - Double(bar) * Self.beatsPerBar

        switch voice {
        case .kick:
            guard section != .breakdown, !(section == .intro && loopBar < 2) else { return 0 }
            let n = Int(floor(beat))
            let since = beat - Double(n)
            let velocity = peak(noise.value(in: 0.80...0.88, salt, n), salt, n)
            return velocity * (0.94 * decay(since, 0.11) + 0.06 * decay(since, 0.5))

        case .snare:
            guard section == .verse || section == .chorus else { return 0 }
            let n = Int(floor(beat))
            var level = 0.0
            if n % 2 == 1 {
                let velocity = peak(noise.value(in: 0.80...0.88, salt, n), salt, n)
                level = velocity * decay(beat - Double(n), 0.18)
            }
            let sixteenth = Int(floor(beat * 4))
            if sixteenth % 4 != 0, noise.chance(0.1, salt, sixteenth, 1) {
                level = max(level, 0.24 * decay(beat - Double(sixteenth) / 4, 0.06))
            }
            return level

        case .clap:
            guard section == .chorus else { return 0 }
            let n = Int(floor(beat - 0.02))
            guard n % 2 == 1 else { return 0 }
            return peak(noise.value(in: 0.76...0.84, salt, n), salt, n) * decay(beat - 0.02 - Double(n), 0.14)

        case .hats:
            guard section != .breakdown else { return 0 }
            let sixteenth = Int(floor(beat * 4))
            let isEighth = sixteenth % 2 == 0
            guard section == .chorus || isEighth else { return 0 }
            let base = isEighth ? 0.68 : 0.48
            return base * noise.value(in: 0.88...1.08, salt, sixteenth) * decay(beat - Double(sixteenth) / 4, 0.07)

        case .openHat:
            guard section == .chorus, beat >= 0.5 else { return 0 }
            let n = Int(floor(beat - 0.5))
            return noise.value(in: 0.64...0.76, salt, n) * decay(beat - 0.5 - Double(n), 0.32)

        case .toms:
            guard section == .verse || section == .chorus, loopBar % 4 == 3, pos >= 3 else { return 0 }
            let sixteenth = Int(floor(beat * 4))
            let velocity = peak(0.92 - 0.04 * Double(sixteenth % 4) + noise.value(in: -0.03...0.03, salt, sixteenth), salt, sixteenth)
            return velocity * decay(beat - Double(sixteenth) / 4, 0.12)

        case .overheads:
            let kick = 0.32 * amplitude(.kick, at: beat)
            let snare = 0.62 * amplitude(.snare, at: beat)
            let hats = 0.55 * amplitude(.hats, at: beat)
            let open = 0.5 * amplitude(.openHat, at: beat)
            let crash = 0.9 * crashLevel(at: beat)
            return (kick * kick + snare * snare + hats * hats + open * open + crash * crash).squareRoot()

        case .room:
            let taps = (0..<4).map { amplitude(.overheads, at: beat - Double($0) * 0.06) }
            return 0.95 * taps.reduce(0, +) / Double(taps.count)

        case .perc:
            guard section == .verse || section == .chorus else { return 0 }
            let sixteenth = Int(floor(beat * 4))
            guard [3, 6, 9, 11, 14].contains(sixteenth % 16), noise.chance(0.65, salt, sixteenth) else { return 0 }
            return noise.value(in: 0.58...0.70, salt, sixteenth, 1) * decay(beat - Double(sixteenth) / 4, 0.1)

        case .shaker:
            guard section == .verse || section == .chorus else { return 0 }
            let eighth = Int(floor(beat * 2))
            let base = eighth % 2 == 0 ? 0.54 : 0.44
            return base * noise.value(in: 0.9...1.1, salt, eighth) * decay(beat - Double(eighth) / 2, 0.14)

        case .bass:
            guard section == .verse || section == .chorus || (section == .intro && loopBar >= 2) else { return 0 }
            let patterns: [[Bool]] = [
                [true, false, true, true, false, true, true, false],
                [true, false, true, false, true, true, false, true],
                [true, true, false, true, false, true, true, false],
                [true, false, true, true, false, true, false, true],
            ]
            let step = min(Int(floor(pos * 2)), 7)
            guard patterns[loopBar % 4][step] else { return 0 }
            let since = pos - Double(step) * 0.5
            let velocity = noise.value(in: 0.76...0.84, salt, bar * 8 + step)
            let body = velocity * (0.82 + 0.18 * decay(since, 0.08))
            return since < 0.42 ? body : body * decay(since - 0.42, 0.04)

        case .subBass:
            guard section == .verse || section == .chorus || (section == .intro && loopBar >= 2) else { return 0 }
            let n = Int(floor(beat))
            return noise.value(in: 0.70...0.78, salt, n) * (0.35 + 0.65 * decay(beat - Double(n), 0.6))

        case .keys:
            guard section == .verse || section == .chorus else { return 0 }
            let chord = Int(floor(beat / 2))
            let since = beat - Double(chord) * 2
            let release = since > 1.8 ? decay(since - 1.8, 0.05) : 1
            return noise.value(in: 0.62...0.74, salt, chord) * (0.5 + 0.5 * decay(since, 0.3)) * release

        case .rhodes:
            guard section == .verse || section == .breakdown, beat >= 0.5 else { return 0 }
            let n = Int(floor(beat - 0.5))
            return noise.value(in: 0.54...0.66, salt, n) * (0.25 + 0.75 * decay(beat - 0.5 - Double(n), 0.28))

        case .piano:
            guard section == .chorus || section == .breakdown else { return 0 }
            let chord = 0.78 * decay(pos, 2.0)
            let eighth = Int(floor(beat * 2))
            let note = noise.chance(0.55, salt, eighth)
                ? noise.value(in: 0.48...0.62, salt, eighth, 1) * decay(beat - Double(eighth) / 2, 0.4)
                : 0
            return max(chord, note)

        case .pad:
            let base: Double = switch section {
            case .intro: 0.5
            case .verse: 0.52
            case .chorus: 0.6
            case .breakdown: 0.66
            }
            let fadeIn = min(1, beat / 8)
            let swell = 0.06 * sin(2 * .pi * beat / 16)
            let grain = 0.03 * (noise.unit(salt, Int(floor(beat * 4))) - 0.5)
            return fadeIn * (base + swell + grain)

        case .strings:
            guard section == .chorus || section == .breakdown else { return 0 }
            let start = Double(sectionStartBar(bar)) * Self.beatsPerBar
            let attack = min(1, (beat - start) / 6)
            return attack * (0.6 + 0.05 * sin(2 * .pi * beat / 8))

        case .leadSynth:
            guard section == .chorus else { return 0 }
            let eighth = Int(floor(beat * 2))
            guard noise.chance(0.7, salt, eighth) else { return 0.1 }
            let velocity = peak(noise.value(in: 0.64...0.80, salt, eighth, 1), salt, eighth)
            return velocity * (0.45 + 0.55 * decay(beat - Double(eighth) / 2, 0.2))

        case .arp:
            guard section != .breakdown else { return 0 }
            let sixteenth = Int(floor(beat * 4))
            let sweep = 0.5 + 0.18 * sin(2 * .pi * beat / 16)
            return sweep * noise.value(in: 0.92...1.08, salt, sixteenth) * (0.15 + 0.85 * decay(beat - Double(sixteenth) / 4, 0.06))

        case .electricGuitar:
            guard section == .verse || section == .chorus else { return 0 }
            let eighth = Int(floor(beat * 2))
            if section == .verse && noise.chance(0.2, salt, eighth, 2) { return 0.08 }
            let base = (eighth % 2 == 0 ? 0.74 : 0.56) * (section == .chorus ? 1.08 : 1)
            return base * noise.value(in: 0.9...1.1, salt, eighth) * (0.4 + 0.6 * decay(beat - Double(eighth) / 2, 0.18))

        case .acousticGuitar:
            guard section != .intro else { return 0 }
            let eighth = Int(floor(beat * 2))
            let base = section == .chorus ? 0.5 : 0.62
            return base * noise.value(in: 0.9...1.1, salt, eighth) * (0.35 + 0.65 * decay(beat - Double(eighth) / 2, 0.25))

        case .leadVocal:
            guard section != .intro else { return 0 }
            return vocalPhrase(at: beat, salt: salt, section: section, start: section == .chorus ? 0.25 : 0.5, end: section == .chorus ? 6.75 : 6.25)
                * (section == .breakdown ? 0.85 : 1)

        case .doubleVocal:
            guard section == .chorus else { return 0 }
            let lead = amplitude(.leadVocal, at: beat - 0.01)
            return lead * 0.8 * noise.value(in: 0.92...1.04, salt, Int(floor(beat * 2)))

        case .backingVocal:
            guard section == .chorus else { return 0 }
            let note = Int(floor(beat / 2))
            guard !noise.chance(0.15, salt, note, 1) else { return 0 }
            let since = beat - Double(note) * 2
            let attack = min(1, since / 0.3)
            let release = since > 1.8 ? decay(since - 1.8, 0.08) : 1
            return noise.value(in: 0.52...0.66, salt, note) * attack * release

        case .adlib:
            guard section == .chorus else { return 0 }
            let cycle = Int(floor(beat / 8))
            guard noise.chance(0.45, salt, cycle, 3) else { return 0 }
            return vocalPhrase(at: beat, salt: salt, section: section, start: 6.25, end: 7.9) * 0.9

        case .riser:
            guard [11, 19, 23, 31].contains(loopBar) else { return 0 }
            let ramp = pos / Self.beatsPerBar
            return 0.06 + 0.86 * ramp * ramp + 0.02 * noise.unit(salt, Int(floor(beat * 4)))

        case .impact:
            guard let start = [4, 12, 24].last(where: { $0 <= loopBar && loopBar - $0 < 2 }) else { return 0 }
            let since = beat - Double(bar - loopBar + start) * Self.beatsPerBar
            return 0.92 * decay(since, 1.4)

        case .noiseBed:
            return 0.16 + 0.04 * noise.unit(salt, Int(floor(beat * 4))) + 0.02 * sin(2 * .pi * beat / 32)

        case .group, .reverbReturn, .delayReturn, .main:
            // Mixed from other tracks by SimulatedMeterEngine.
            return 0
        }
    }

    // MARK: Helpers

    /// Beats an event stays at full level before it decays. Live's meters are smoothed peak
    /// meters, so even short hits show their peak; the hold keeps a hit visible for at least
    /// one 30 Hz frame at usual tempos.
    static let peakHold = 0.07

    /// Exponential decay `since` beats after an event (after a short hold); 0 before it.
    private func decay(_ since: Double, _ time: Double) -> Double {
        if since < 0 { return 0 }
        if since < Self.peakHold { return 1 }
        return exp(-(since - Self.peakHold) / time)
    }

    /// Occasionally pushes a hit into the red, and very rarely past full scale (a clip).
    private func peak(_ velocity: Double, _ salt: UInt64, _ index: Int) -> Double {
        let roll = noise.unit(salt, index, 0xC11F)
        if roll < 0.0025 { return 1.12 }
        if roll < 0.05 { return noise.value(in: 0.93...0.99, salt, index, 0xBED) }
        return velocity
    }

    /// First bar of the section that `bar` is in.
    private func sectionStartBar(_ bar: Int) -> Int {
        var start = bar
        while start > 0, Self.section(ofBar: start - 1) == Self.section(ofBar: bar) { start -= 1 }
        return start
    }

    /// A crash cymbal at the start of the verse and both choruses.
    private func crashLevel(at beat: Double) -> Double {
        let bar = Int(floor(beat / Self.beatsPerBar))
        let loopBar = Self.loopBar(bar)
        guard let start = [4, 12, 24].last(where: { $0 <= loopBar && loopBar - $0 < 2 }) else { return 0 }
        return decay(beat - Double(bar - loopBar + start) * Self.beatsPerBar, 2.5)
    }

    /// A sung line: syllables every half beat between `start` and `end` of each two-bar cycle,
    /// with per-syllable level, a little vibrato, and occasional belted notes in the chorus.
    private func vocalPhrase(at beat: Double, salt: UInt64, section: Section, start: Double, end: Double) -> Double {
        let cycle = Int(floor(beat / 8))
        let position = beat - Double(cycle) * 8
        guard position >= start else { return 0 }
        let syllableLength = 0.5
        let clamped = min(position, end)
        let syllable = Int(floor((clamped - start) / syllableLength))
        let index = cycle * 64 + syllable
        var level = noise.value(in: 0.58...0.80, salt, index) + (section == .chorus ? 0.06 : 0)
        if section == .chorus, noise.chance(0.06, salt, index, 5) {
            level = noise.value(in: 0.94...0.99, salt, index, 6)
        }
        if position >= end {
            return level * 0.6 * decay(position - end, 0.12)
        }
        let phase = (position - start) / syllableLength - Double(syllable)
        let envelope = 0.35 + 0.65 * pow(sin(.pi * phase), 0.4)
        let vibrato = 0.02 * sin(2 * .pi * 2.7 * beat)
        return max(0, level * envelope + vibrato)
    }
}
