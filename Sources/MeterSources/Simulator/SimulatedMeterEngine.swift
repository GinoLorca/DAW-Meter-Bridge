import Foundation
import MeterCore

/// Turns the song into post-fader stereo meter values for every simulated track:
/// each track's voice, panned and scaled by its fader; groups sum their children; returns are
/// fed by sends (reverb smear, delay echoes); Main sums the top level through a soft limiter.
/// Muted tracks and tracks muted via solo are silent.
struct SimulatedMeterEngine: Sendable {
    struct Stereo: Hashable, Sendable {
        var left: Double
        var right: Double

        static let silent = Stereo(left: 0, right: 0)

        var squared: Stereo { Stereo(left: left * left, right: right * right) }
        func scaled(_ factor: Double) -> Stereo { Stereo(left: left * factor, right: right * factor) }
    }

    private struct Send: Sendable {
        var track: Int
        var amount: Double
    }

    let music: SimulatedMusic
    let specs: [SimulatedTrackSpec]
    /// Per track: how many earlier tracks play the same voice.
    private let variants: [Int]
    private let children: [Int: [Int]]
    /// Tracks that feed Main directly: ungrouped tracks, groups and returns.
    private let topLevel: [Int]
    private let reverbSends: [Send]
    private let delaySends: [Send]

    /// Mix state needed for one frame, computed once.
    private struct Frame {
        var gains: [Double]
        var audible: [Bool]
        /// Whether each track currently feeds its sends.
        var feedsSends: [Bool]
    }

    init(specs: [SimulatedTrackSpec], seed: UInt64) {
        music = SimulatedMusic(seed: seed)
        self.specs = specs
        var seen: [SimulatedVoice: Int] = [:]
        variants = specs.map { spec in
            defer { seen[spec.voice, default: 0] += 1 }
            return seen[spec.voice, default: 0]
        }
        var children: [Int: [Int]] = [:]
        for (index, spec) in specs.enumerated() {
            if let group = spec.group { children[group, default: []].append(index) }
        }
        self.children = children
        topLevel = specs.indices.filter { specs[$0].group == nil && specs[$0].voice != .main }
        let reverbAmounts: [SimulatedVoice: Double] = [
            .snare: 0.5, .clap: 0.45, .leadVocal: 0.55, .doubleVocal: 0.4, .backingVocal: 0.6,
            .keys: 0.35, .piano: 0.45, .pad: 0.3, .strings: 0.4, .acousticGuitar: 0.3,
        ]
        let delayAmounts: [SimulatedVoice: Double] = [
            .leadVocal: 0.6, .adlib: 0.7, .leadSynth: 0.5, .electricGuitar: 0.2,
        ]
        reverbSends = specs.indices.compactMap { index in
            reverbAmounts[specs[index].voice].map { Send(track: index, amount: $0) }
        }
        delaySends = specs.indices.compactMap { index in
            delayAmounts[specs[index].voice].map { Send(track: index, amount: $0) }
        }
    }

    /// Post-fader stereo levels of every track at `beat`, clamped to 0...1 and rounded to 4 decimals
    /// like the Live script sends them. Indexed like `specs`.
    func levels(at beat: Double, mix: SimulatedMix) -> [Stereo] {
        let frame = makeFrame(mix)
        var output = [Stereo](repeating: .silent, count: specs.count)
        // Plain tracks first, then groups, returns and Main, which mix them.
        for index in specs.indices where !isMixed(specs[index].voice) && frame.audible[index] {
            let mono = music.amplitude(specs[index].voice, at: beat, variant: variants[index])
            output[index] = place(mono, index: index, beat: beat).scaled(frame.gains[index])
        }
        for (group, members) in children where frame.audible[group] {
            let sum = members.map { output[$0].squared }.reduce(Stereo.silent, +)
            output[group] = Stereo(left: sum.left.squareRoot(), right: sum.right.squareRoot())
                .scaled(0.62 * frame.gains[group])
        }
        for index in specs.indices where frame.audible[index] {
            let level: Double
            switch specs[index].voice {
            case .reverbReturn: level = reverb(at: beat, frame: frame)
            case .delayReturn: level = delay(at: beat, frame: frame)
            default: continue
            }
            output[index] = place(level, index: index, beat: beat).scaled(frame.gains[index])
        }
        for index in specs.indices where specs[index].voice == .main {
            let sum = topLevel.map { output[$0].squared }.reduce(Stereo.silent, +)
            // Bus compression: loud passages sit high but rarely reach full scale.
            output[index] = Stereo(left: tanh(sum.left.squareRoot() * 0.65), right: tanh(sum.right.squareRoot() * 0.65))
                .scaled(frame.gains[index])
        }
        return output.map { Stereo(left: Self.wireValue($0.left), right: Self.wireValue($0.right)) }
    }

    // MARK: Private

    private func isMixed(_ voice: SimulatedVoice) -> Bool {
        switch voice {
        case .group, .reverbReturn, .delayReturn, .main: true
        default: false
        }
    }

    /// Pans a mono level and adds a little movement between the sides for stereo sources.
    private func place(_ mono: Double, index: Int, beat: Double) -> Stereo {
        let spec = specs[index]
        var left = mono * min(1, 1 - spec.pan)
        var right = mono * min(1, 1 + spec.pan)
        if spec.width > 0 {
            let phase = Double(index) * 0.137
            left *= 1 + spec.width * sin(2 * .pi * (beat * 0.31 + phase))
            right *= 1 + spec.width * sin(2 * .pi * (beat * 0.27 + phase + 0.25))
        }
        return Stereo(left: left, right: right)
    }

    private func makeFrame(_ mix: SimulatedMix) -> Frame {
        // When only returns are soloed, tracks keep feeding the returns (Live's solo-in-place).
        let onlyReturnsSoloed = mix.anySoloed
            && !mix.tracks.contains { $0.isSoloed && $0.kind != .returnTrack }
        return Frame(
            gains: specs.indices.map { mix.gain($0) },
            audible: specs.indices.map { mix.isAudible($0) },
            feedsSends: mix.tracks.map { !$0.isMuted && (!$0.isMutedViaSolo || onlyReturnsSoloed) }
        )
    }

    /// Combined send level into a return at `beat`, from tracks that feed their sends right now.
    private func sendInput(_ sends: [Send], at beat: Double, frame: Frame) -> Double {
        var power = 0.0
        for send in sends where frame.feedsSends[send.track] {
            let level = music.amplitude(specs[send.track].voice, at: beat, variant: variants[send.track])
                * frame.gains[send.track] * send.amount
            power += level * level
        }
        return power.squareRoot()
    }

    /// A smeared tail of the recent send input.
    private func reverb(at beat: Double, frame: Frame) -> Double {
        var sum = 0.0
        var weight = 1.0
        var total = 0.0
        for tap in 1...6 {
            sum += weight * sendInput(reverbSends, at: beat - Double(tap) * 0.11, frame: frame)
            total += weight
            weight *= 0.8
        }
        return 1.25 * sum / total
    }

    /// Three dotted-eighth echoes of the send input.
    private func delay(at beat: Double, frame: Frame) -> Double {
        0.6 * sendInput(delaySends, at: beat - 0.75, frame: frame)
            + 0.38 * sendInput(delaySends, at: beat - 1.5, frame: frame)
            + 0.22 * sendInput(delaySends, at: beat - 2.25, frame: frame)
    }

    /// Converts a linear amplitude (1 = 0 dBFS) to Live's meter scale, as Live 12 reports it
    /// (`MeterCalibration.ableton12`: linear in dB from -70 to +6 dBFS), rounded to 4 decimals like the
    /// script sends it. Overs above 0 dBFS read above 0.92105, so the clip LED behaves as with Live.
    static func wireValue(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        let meter = MeterCalibration.liveMeterValue(decibels: 20 * log10(value))
        return (meter * 10_000).rounded() / 10_000
    }
}

extension SimulatedMeterEngine.Stereo {
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(left: lhs.left + rhs.left, right: lhs.right + rhs.right)
    }
}
