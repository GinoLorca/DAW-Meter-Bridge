import Foundation
import MeterCore
@testable import MeterSources
import Testing

/// Long-running checks of the simulated music, on the engine directly so they run off the main actor.
@Suite("Simulated music")
struct SimulatedMusicTests {
    let specs = SimulatedTrackSpec.defaultSession

    /// Live 12 meter value for a linear amplitude: the simulator reports Live's scale (linear in dB).
    func meter(amplitude: Double) -> Double {
        MeterCalibration.liveMeterValue(decibels: 20 * log10(amplitude))
    }

    /// Values at or above this light the clip LED (just above 0 dBFS).
    let clipValue = Double(MeterCalibration.ableton12.clipValue)

    /// Peak of left/right per track for each 30 Hz frame over `seconds` at 120 BPM.
    func frames(seed: UInt64, seconds: Double, mix: SimulatedMix? = nil) -> [[Double]] {
        let engine = SimulatedMeterEngine(specs: specs, seed: seed)
        let mix = mix ?? SimulatedMix(specs: specs)
        return (0..<Int(seconds * 30)).map { frame in
            engine.levels(at: Double(frame) / 30 * 2, mix: mix).map { max($0.left, $0.right) }
        }
    }

    @Test func sameSeedSameMotionOtherSeedOtherMotion() {
        let a = frames(seed: 7, seconds: 20)
        #expect(a == frames(seed: 7, seconds: 20))
        #expect(a != frames(seed: 8, seconds: 20))
    }

    @Test func songReachesTheRedAndRarelyClips() {
        let all = frames(seed: SimulatedSource.defaultSeed, seconds: 180) // about three times the 32-bar loop
        let values = all.flatMap { $0 }
        let red = values.filter { $0 >= meter(amplitude: 0.9) }.count
        let clips = values.filter { $0 >= clipValue }.count
        #expect(red > 0)
        #expect(clips > 0)
        #expect(Double(red) / Double(values.count) < 0.05)
        #expect(Double(clips) / Double(values.count) < 0.002)
        // Every track makes sound at some point, and Main is never silent for long.
        for track in specs.indices {
            #expect(all.contains { $0[track] > meter(amplitude: 0.05) }, "\(specs[track].name) never sounds")
        }
        let main = specs.count - 1
        #expect(all.filter { $0[main] < meter(amplitude: 0.05) }.count < all.count / 50)
    }

    @Test func clipsComeFromDrumsAndMainStaysBelowFullScale() {
        let all = frames(seed: SimulatedSource.defaultSeed, seconds: 120)
        let main = specs.count - 1
        #expect(all.allSatisfy { $0[main] < clipValue })
        #expect(all.contains { $0[main] > meter(amplitude: 0.75) })
    }

    @Test func valuesStayInRangeWithFourDecimalsEvenAtFullVolume() {
        var mix = SimulatedMix(specs: specs)
        for track in mix.tracks { mix.apply(.setVolume(track.id, 1)) }
        let engine = SimulatedMeterEngine(specs: specs, seed: 5)
        var outOfRange = 0
        var tooPrecise = 0
        for frame in 0..<900 {
            for level in engine.levels(at: Double(frame) / 15, mix: mix) {
                for value in [level.left, level.right] {
                    if !(0...1).contains(value) { outOfRange += 1 }
                    if abs(value * 10_000 - (value * 10_000).rounded()) > 1e-6 { tooPrecise += 1 }
                }
            }
        }
        #expect(outOfRange == 0)
        #expect(tooPrecise == 0)
    }

    @Test func sectionsFollowTheLoop() {
        let sections = (0..<34).map(SimulatedMusic.section(ofBar:))
        #expect(sections[0] == .intro)
        #expect(sections[4] == .verse)
        #expect(sections[12] == .chorus)
        #expect(sections[20] == .breakdown)
        #expect(sections[24] == .chorus)
        #expect(sections[32] == .intro)
        #expect(sections[33] == .intro)
    }

    @Test func pannedTracksFavourTheirSide() {
        let engine = SimulatedMeterEngine(specs: specs, seed: 1)
        let mix = SimulatedMix(specs: specs)
        let left = specs.firstIndex { $0.name == "Gtr L" }!
        let right = specs.firstIndex { $0.name == "Gtr R" }!
        var leftWins = 0
        var rightWins = 0
        for frame in 0..<300 {
            let levels = engine.levels(at: 16 + Double(frame) / 15, mix: mix) // verse
            if levels[left].left > levels[left].right { leftWins += 1 }
            if levels[right].right > levels[right].left { rightWins += 1 }
        }
        #expect(leftWins > 250)
        #expect(rightWins > 250)
    }

    @Test func noiseIsUniformAndStable() {
        let noise = SeededNoise(seed: 42)
        let values = (0..<10_000).map { noise.unit(1, $0) }
        #expect(values.allSatisfy { (0..<1).contains($0) })
        let mean = values.reduce(0, +) / Double(values.count)
        #expect(abs(mean - 0.5) < 0.02)
        #expect(noise.unit(1, 5) == SeededNoise(seed: 42).unit(1, 5))
        #expect(noise.unit(1, 5) != SeededNoise(seed: 43).unit(1, 5))
    }
}
