import BridgeProtocol
import Dispatch
import Foundation
import MeterCore

extension LiveSource {
    /// Sends a command to Live and, while connected, shows its effect right away.
    /// Mute/solo on Main and arm on tracks that can't be armed are dropped, as Live would ignore them.
    public func send(_ command: BridgeCommand) {
        guard running else {
            liveLog.debug("Dropping a command while stopped")
            return
        }
        let known = snapshot.track(command.trackID)
        let optimistic = snapshot.connection == .connected && known != nil
        switch command {
        case let .select(id):
            if optimistic { snapshot.selected = id }
            transmit(.command(CommandMessage(command)))

        case let .setMute(_, on):
            if let known, !known.canMute { return }
            if optimistic, var track = known {
                track.isMuted = on
                snapshot.updateTrack(track)
            }
            transmit(.command(CommandMessage(command)))

        case let .setSolo(id, on, exclusive):
            if let known, !known.canSolo { return }
            if optimistic { applySolo(id, on: on, exclusive: exclusive) }
            transmit(.command(CommandMessage(command)))

        case let .setArm(_, on):
            if let known, !known.canArm { return }
            if optimistic, var track = known {
                track.isArmed = on
                snapshot.updateTrack(track)
            }
            transmit(.command(CommandMessage(command)))

        case let .setVolume(id, value), let .endVolumeDrag(id, value):
            let volume = value.isNaN ? 0 : min(max(value, 0), 1)
            let now = Self.now()
            if optimistic, var track = known {
                track.volume = volume
                track.volumeText = (snapshot.volumeCurve ?? .liveApproximation).text(atNormalized: volume)
                snapshot.updateTrack(track)
                volumeHolds[id] = now + configuration.volumeEchoHold
            }
            if case .endVolumeDrag = command {
                // The final value replaces any held one and goes out now, marked as the drag's end.
                _ = throttle.flush(id, at: now)
                transmit(.command(CommandMessage(.endVolumeDrag(id, volume))))
                break
            }
            switch throttle.submit(volume, for: id, at: now) {
            case .sendNow:
                transmit(.command(CommandMessage(.setVolume(id, volume))))
            case let .flushAt(time):
                scheduleVolumeFlush(for: id, after: max(0, time - now))
            case .coalesced:
                break
            }
        }
        publishIfChanged()
    }

    private func scheduleVolumeFlush(for id: TrackID, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.flushVolume(for: id) }
        }
    }

    private func flushVolume(for id: TrackID) {
        let now = Self.now()
        guard let value = throttle.flush(id, at: now), running else { return }
        if volumeHolds[id] != nil { volumeHolds[id] = now + configuration.volumeEchoHold }
        transmit(.command(CommandMessage(.setVolume(id, value))))
    }

    /// Optimistic solo: exclusive (Live's default preference) unless `exclusive` is false, and an
    /// approximate muted-via-solo. Group tracks keep their state until Live's echo, because the
    /// protocol doesn't say which tracks a group contains.
    private func applySolo(_ id: TrackID, on: Bool, exclusive: Bool?) {
        var tracks = snapshot.tracks
        guard let position = tracks.firstIndex(where: { $0.id == id }) else { return }
        if on && exclusive != false {
            for index in tracks.indices where index != position && tracks[index].canSolo {
                tracks[index].isSoloed = false
            }
        }
        tracks[position].isSoloed = on
        let anySoloed = tracks.contains { $0.isSoloed }
        for index in tracks.indices {
            switch tracks[index].kind {
            case .main, .returnTrack:
                tracks[index].isMutedViaSolo = false
            case .group:
                if !anySoloed || tracks[index].isSoloed { tracks[index].isMutedViaSolo = false }
            case .audio, .midi:
                tracks[index].isMutedViaSolo = anySoloed && !tracks[index].isSoloed
            }
        }
        snapshot.setTracks(tracks)
    }
}
