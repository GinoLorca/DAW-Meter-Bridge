import Foundation
import MeterCore

/// Demo and calibration source that needs no DAW.
///
/// It simulates a 32-track Live session (two groups, two returns and Main) playing a looping song
/// at ``tempo``, metered at about 30 Hz, and a virtual Mackie surface of ``unitCount`` units
/// (1 = UF8, 3 = WING as MCU + 2 XT) that banks like Live's MackieControl. Commands change the
/// simulated mix the way Live would. Meter motion is deterministic for a given ``seed``.
/// The song starts at the entry of its first chorus (``chorusEntryBeat``), so every drum meter on
/// the first bank moves within the first second instead of after the quiet intro.
///
/// Like the Live script, it meters only the tracks on surface strips, the selected track, Main and
/// the watched tracks (unless ``metersAllTracks`` is set), and sends zeros once for a track that
/// leaves that set.
@MainActor
public final class SimulatedSource: MeterSource {
    /// Seed used when none is given.
    public nonisolated static let defaultSeed: UInt64 = 0x5EED_DA7A
    /// Tempo range accepted by ``setTempo(_:)``.
    public nonisolated static let tempoRange: ClosedRange<Double> = 40...240
    /// Default start: the last beat of bar 11, where the toms fill into the first chorus (bar 12).
    /// The loop's arrangement is unchanged; it just starts here instead of in the intro.
    public nonisolated static let chorusEntryBeat: Double = 47

    public let displayName = "Simulator"
    public weak var delegate: (any MeterSourceDelegate)?
    public private(set) var snapshot: BridgeSnapshot

    /// Seed of the meter motion.
    public let seed: UInt64
    /// Song tempo in beats per minute.
    public private(set) var tempo: Double
    /// Meter frames per second while running.
    public let meterRate: Double
    /// Song position in beats from the top of the loop (``chorusEntryBeat`` unless another start was given).
    public private(set) var beatPosition: Double
    /// Meter every track instead of only strips, selection, Main and watched tracks.
    public var metersAllTracks = false

    /// Number of virtual Mackie units of 8 strips.
    public var unitCount: Int { surface.unitCount }
    /// Visible-track index on the first strip.
    public var bankOffset: Int { surface.bankOffset }
    /// Whether the meter timer is running.
    public var isRunning: Bool { timer != nil }

    private var mix: SimulatedMix
    private var surface: VirtualMackieSurface
    private let engine: SimulatedMeterEngine
    private var watched: Set<TrackID> = []
    private var lastMetered: Set<TrackID> = []
    private var timer: Timer?
    private var lastTick: TimeInterval?

    /// - Parameters:
    ///   - seed: Seed of the meter motion; the same seed gives the same motion.
    ///   - unitCount: Virtual Mackie units of 8 strips (1 = UF8, 3 = WING), clamped to 1...7.
    ///   - tempo: Song tempo in BPM, clamped to ``tempoRange``.
    ///   - meterRate: Meter frames per second while running.
    ///   - startBeat: Song position to start at, in beats (0 = the top of the intro).
    public init(
        seed: UInt64 = SimulatedSource.defaultSeed,
        unitCount: Int = 1,
        tempo: Double = 120,
        meterRate: Double = 30,
        startBeat: Double = SimulatedSource.chorusEntryBeat
    ) {
        let specs = SimulatedTrackSpec.defaultSession
        self.seed = seed
        beatPosition = startBeat.isFinite ? max(startBeat, 0) : 0
        self.tempo = min(max(tempo, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
        self.meterRate = min(max(meterRate, 1), 120)
        mix = SimulatedMix(specs: specs, selectedIndex: specs.firstIndex { $0.voice == .leadVocal })
        surface = VirtualMackieSurface(unitCount: unitCount)
        engine = SimulatedMeterEngine(specs: specs, seed: seed)
        snapshot = BridgeSnapshot(connection: .idle, volumeCurve: mix.curve)
        rebuildSnapshot()
    }

    // MARK: MeterSource

    /// Starts meter frames on a timer on the main run loop (common modes) and reports `.connected`.
    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / meterRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        lastTick = ProcessInfo.processInfo.systemUptime
        snapshot.connection = .connected
        publishSnapshot()
    }

    /// Stops the timer and reports `.idle`. The mix state is kept.
    public func stop() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
        lastMetered = []
        snapshot.connection = .idle
        publishSnapshot()
    }

    /// Applies the command to the simulated mix like Live would and publishes the new snapshot.
    public func send(_ command: BridgeCommand) {
        guard mix.apply(command) else { return }
        rebuildSnapshot()
        publishSnapshot()
    }

    /// Extra tracks to meter besides strips, selection and Main.
    public func setWatchedTracks(_ ids: Set<TrackID>) {
        watched = ids
    }

    // MARK: Virtual surface and transport

    /// Banks the virtual surface left by all of its strips.
    public func bankLeft() {
        surface.bankLeft()
        surfaceChanged()
    }

    /// Banks the virtual surface right by all of its strips, unless that passes the last track.
    public func bankRight() {
        surface.bankRight(trackCount: visibleTrackIDs.count)
        surfaceChanged()
    }

    /// Sets how many 8-strip Mackie units the virtual surface has (clamped to 1...7).
    public func setUnitCount(_ count: Int) {
        surface.setUnitCount(count, trackCount: visibleTrackIDs.count)
        surfaceChanged()
    }

    /// Sets the song tempo in BPM (clamped to ``tempoRange``).
    public func setTempo(_ bpm: Double) {
        guard bpm.isFinite else { return }
        tempo = min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
    }

    // MARK: Meters

    /// Advances the song by `dt` seconds and delivers one meter frame to the delegate.
    /// Returns the levels delivered. The running timer calls this; tests can call it directly.
    @discardableResult
    public func advance(by dt: TimeInterval) -> [MeterLevel] {
        beatPosition += max(dt, 0) * tempo / 60
        let levels = currentLevels()
        delegate?.meterSource(self, didReceive: levels, at: ProcessInfo.processInfo.systemUptime)
        return levels
    }

    /// Levels at the current position for the metered tracks, plus zeros for tracks that just left the set.
    private func currentLevels() -> [MeterLevel] {
        let metered = meteredTrackIndices()
        let all = engine.levels(at: beatPosition, mix: mix)
        var levels = metered.map { index in
            MeterLevel(id: mix.tracks[index].id, left: Float(all[index].left), right: Float(all[index].right))
        }
        let ids = Set(levels.map(\.id))
        for id in lastMetered.subtracting(ids).sorted() {
            levels.append(MeterLevel(id: id, left: 0, right: 0))
        }
        lastMetered = ids
        return levels
    }

    private func meteredTrackIndices() -> [Int] {
        if metersAllTracks { return Array(mix.tracks.indices.prefix(64)) }
        var wanted = watched
        for unit in snapshot.units {
            for case let id? in unit.strips { wanted.insert(id) }
        }
        if let selected = mix.selected { wanted.insert(selected) }
        if let main = mix.tracks.last(where: { $0.kind == .main }) { wanted.insert(main.id) }
        return Array(wanted.compactMap { mix.index(of: $0) }.sorted().prefix(64))
    }

    private func timerFired() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTick.map { min(max(now - $0, 0), 0.25) } ?? 1 / meterRate
        lastTick = now
        advance(by: dt)
    }

    // MARK: Snapshot

    private var visibleTrackIDs: [TrackID] {
        mix.tracks.filter { $0.kind != .returnTrack && $0.kind != .main }.map(\.id)
    }

    private func surfaceChanged() {
        let units = surface.units(over: visibleTrackIDs)
        guard units != snapshot.units else { return }
        snapshot.units = units
        publishSnapshot()
    }

    private func rebuildSnapshot() {
        snapshot.setTracks(mix.tracks)
        snapshot.selected = mix.selected
        snapshot.units = surface.units(over: visibleTrackIDs)
    }

    private func publishSnapshot() {
        delegate?.meterSource(self, didUpdate: snapshot)
    }
}
