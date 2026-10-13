import Foundation
import MeterCore
import MeterSources

extension AppController {
    /// Stops the current source and starts `kind`. Each kind keeps one instance, so switching back to
    /// Live within a few seconds reuses its cached tracks. The choice is remembered across launches.
    func activateSource(_ kind: SourceKind) {
        if let current = source {
            current.delegate = nil
            current.stop()
        }
        let next: any MeterSource
        switch kind {
        case .simulator:
            let simulator = self.simulator ?? SimulatedSource(unitCount: settings.simulatorUnitCount)
            self.simulator = simulator
            next = simulator
        case .live:
            let live = self.live ?? LiveSource()
            self.live = live
            next = live
        }
        sourceKind = kind
        source = next
        applyMeterCalibration()
        matchSimulatorToProfile()
        store.removeAll()
        frameClock.reset()
        lastWatched = nil
        snapshot = next.snapshot
        revision &+= 1
        next.delegate = self
        updateWatchedTracks()
        next.start()
        settings.source = kind
        saveSettings()
        keepAwake(for: 0.1)
        onStatusChange?()
    }

    /// Tells the source which tracks the bridge shows that it would not meter on its own.
    func updateWatchedTracks() {
        let ids = presentation.placements.map(\.group).watchedTracks(in: snapshot)
        guard ids != lastWatched else { return }
        lastWatched = ids
        source?.setWatchedTracks(ids)
    }

    /// Sends a command to the DAW through the current source.
    func send(_ command: BridgeCommand) {
        source?.send(command)
    }

    /// The simulator, when it is the current source.
    var activeSimulator: SimulatedSource? {
        sourceKind == .simulator ? simulator : nil
    }

    /// The meter calibration for the current source. Drives the dB readouts and the clip LEDs.
    /// Live: a table from the settings if there is one, else the built-in measurement for the connected
    /// Live version (known once the script's hello arrives), else uncalibrated. The simulator emits Live
    /// 12's scale, so it uses the Live 12 measurement.
    func applyMeterCalibration() {
        let calibration: MeterCalibration
        switch sourceKind {
        case .live:
            calibration = settings.liveMeterCalibration
                ?? MeterCalibration.ableton(version: live?.liveVersion)
                ?? .uncalibrated
        case .simulator:
            calibration = .ableton12
        }
        guard calibration != store.calibration else { return }
        store.calibration = calibration
        if !isHeadless { panelManager.setCalibration(calibration) }
    }

    /// Gives the simulator at least as many Mackie units as the active profile's groups use (the WING
    /// profile needs 3), so demoing a profile never shows empty sections. Never removes units.
    func matchSimulatorToProfile() {
        guard let simulator = activeSimulator, let profile = document.activeProfile else { return }
        let needed = min(max(1, profile.surfaceUnitCount), 7)
        if needed > simulator.unitCount { setSimulatorUnitCount(needed) }
    }

    /// Sets how many Mackie units the simulator emulates (1 = UF8, 3 = WING) and remembers it.
    func setSimulatorUnitCount(_ count: Int) {
        settings.simulatorUnitCount = count
        saveSettings()
        simulator?.setUnitCount(count)
    }

    /// One line describing the source's state, for the menu.
    var sourceStatusLine: String {
        switch sourceKind {
        case .simulator:
            guard let simulator else { return "Simulator" }
            let visible = snapshot.tracks.filter { $0.kind != .returnTrack && $0.kind != .main }.count
            let first = simulator.bankOffset + 1
            let last = min(simulator.bankOffset + 8 * simulator.unitCount, visible)
            return "Simulator: \(snapshot.tracks.count) tracks, surface on tracks \(first)–\(last)"
        case .live:
            switch snapshot.connection {
            case .idle:
                return "Ableton Live: stopped"
            case .connecting:
                let port = live?.boundPort ?? live?.configuration.listenPort ?? 47800
                return "Ableton Live: waiting for the MeterBridge script (port \(port))…"
            case .connected:
                var parts = ["\(snapshot.tracks.count) tracks"]
                if let version = live?.liveVersion, !version.isEmpty { parts.insert("Live \(version)", at: 0) }
                if let script = live?.scriptVersion { parts.append("script \(script)") }
                return "Ableton Live: connected (\(parts.joined(separator: ", ")))"
            case let .disconnected(reason):
                return "Ableton Live: not connected. \(reason)"
            }
        }
    }

    /// Warnings for the menu: the source's, the layout's and any load/save problems.
    var statusWarnings: [String] {
        var lines = snapshot.warnings
        if sourceKind == .live, let error = live?.lastScriptError { lines.append("Live script: \(error)") }
        lines += presentation.notes
        lines += layoutMessages
        lines += appMessages
        return lines
    }
}

extension AppController: MeterSourceDelegate {
    func meterSource(_ source: any MeterSource, didUpdate newSnapshot: BridgeSnapshot) {
        guard source === self.source else { return }
        let old = snapshot
        snapshot = newSnapshot
        revision &+= 1
        if old.tracks.count != newSnapshot.tracks.count || !old.tracks.map(\.id).elementsEqual(newSnapshot.tracks.map(\.id)) {
            store.retain(only: Set(newSnapshot.tracks.map(\.id)))
        }
        updateWatchedTracks()
        // The Live version arrives with the script's hello; switch to its measured calibration then.
        applyMeterCalibration()
        keepAwake(for: 0.05)
        if old.connection != newSnapshot.connection || old.warnings != newSnapshot.warnings
            || old.units != newSnapshot.units || old.tracks.count != newSnapshot.tracks.count {
            onStatusChange?()
        }
    }

    func meterSource(_ source: any MeterSource, didReceive levels: [MeterLevel], at time: TimeInterval) {
        guard source === self.source else { return }
        store.ingest(levels, at: time)
        let floor = store.settings.silenceFloor
        if levels.contains(where: { $0.left > floor || $0.right > floor }) {
            panelManager.wakeAll()
        }
    }
}
