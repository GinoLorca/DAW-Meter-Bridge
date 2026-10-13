import BridgeProtocol
import Foundation
import MeterCore

extension LiveSource {
    /// A long run of `m` messages with old sequence numbers means the script restarted without
    /// us seeing its `hello`; after this many in a row, accept them again.
    static let staleMeterRunLimit = 30

    /// Handles a batch of datagrams read from the socket (on the main actor).
    func receive(_ datagrams: [ReceivedDatagram]) {
        for datagram in datagrams {
            guard running else { return }
            handle(datagram)
        }
        publishIfChanged()
    }

    private func handle(_ datagram: ReceivedDatagram) {
        let message: IncomingMessage
        do {
            message = try WireCodec.decodeIncoming(datagram.data)
        } catch {
            switch error {
            case let .unsupportedVersion(version):
                versionMismatch(version)
            case let .malformed(reason):
                malformedCount += 1
                if malformedCount <= 5 || malformedCount % 1000 == 0 {
                    liveLog.warning("Ignoring malformed datagram #\(self.malformedCount): \(reason, privacy: .public)")
                }
            case .oversized:
                break
            }
            return
        }

        heard(at: datagram.time)
        switch message {
        case let .hello(hello):
            apply(hello)
        case let .tracks(part):
            apply(part, at: datagram.time)
        case let .track(update):
            apply(update, at: datagram.time)
        case let .selection(selection):
            snapshot.selected = selection.id
        case let .surfaces(surfaces):
            snapshot.units = surfaces.surfaceUnits
            surfaceWarning = surfaces.warn
            updateWarnings()
        case let .meters(meters):
            apply(meters, at: datagram.time)
        case .heartbeat:
            break
        case let .error(error):
            lastScriptError = error.msg
            liveLog.warning("Live script reported: \(error.msg, privacy: .public)")
        case let .unknown(type):
            if reportedUnknownTypes.insert(type).inserted {
                liveLog.debug("Ignoring unknown message type \(type, privacy: .public)")
            }
        }
    }

    private func heard(at time: TimeInterval) {
        lastHeard = time
        if versionWarning != nil {
            versionWarning = nil
            updateWarnings()
        }
        if snapshot.connection != .connected {
            snapshot.connection = .connected
        }
    }

    private func versionMismatch(_ version: Int?) {
        if reportedVersions.insert(version).inserted {
            liveLog.warning("Dropping messages with protocol version \(version.map(String.init) ?? "none", privacy: .public); this app speaks v\(WireProtocol.version)")
        }
        let reason = "The MeterBridge script in Live speaks protocol v\(version.map(String.init) ?? "?"), "
            + "this app speaks v\(WireProtocol.version). Install matching versions."
        versionWarning = reason
        snapshot.connection = .disconnected(reason: reason)
        updateWarnings()
    }

    private func apply(_ hello: HelloMessage) {
        helloSinceStart = true
        if hello.session != session {
            if session != nil {
                liveLog.info("New Live script session \(hello.session); dropping cached state")
            }
            resetSessionState()
            session = hello.session
        }
        scriptVersion = hello.script
        liveVersion = hello.live
        scriptMeterRate = hello.hz
        if let curve = hello.volumeCurve { snapshot.volumeCurve = curve }
        // The script may have lost the watch list along with the old subscription.
        sendWatch()
    }

    private func resetSessionState() {
        snapshot.setTracks([])
        snapshot.selected = nil
        snapshot.units = []
        snapshot.volumeCurve = nil
        surfaceWarning = nil
        updateWarnings()
        assembler.reset()
        listGeneration = nil
        lastMeterSeq = nil
        staleMeterRun = 0
        volumeHolds.removeAll()
        lastScriptError = nil
    }

    private func apply(_ part: TracksMessage, at time: TimeInterval) {
        guard let list = assembler.add(part, at: time) else { return }
        let tracks = list.map { keepingLocalVolume($0.trackInfo, at: time) }
        snapshot.setTracks(tracks)
        listGeneration = part.gen
    }

    private func apply(_ update: TrackMessage, at time: TimeInterval) {
        if let listGeneration, update.gen < listGeneration { return }
        guard snapshot.contains(update.item.id) else { return }
        snapshot.updateTrack(keepingLocalVolume(update.item.trackInfo, at: time))
    }

    private func apply(_ meters: MetersMessage, at time: TimeInterval) {
        if let last = lastMeterSeq, meters.seq <= last {
            staleMeterRun += 1
            guard staleMeterRun >= Self.staleMeterRunLimit else { return }
            liveLog.info("Meter sequence restarted at \(meters.seq); accepting it")
        }
        staleMeterRun = 0
        lastMeterSeq = meters.seq
        delegate?.meterSource(self, didReceive: meters.levels, at: time)
    }

    /// While the user is dragging a fader, Live's echoes lag behind; keep the local volume.
    private func keepingLocalVolume(_ track: TrackInfo, at time: TimeInterval) -> TrackInfo {
        guard let holdUntil = volumeHolds[track.id] else { return track }
        guard time < holdUntil, let local = snapshot.track(track.id) else {
            volumeHolds[track.id] = nil
            return track
        }
        var result = track
        result.volume = local.volume
        result.volumeText = local.volumeText
        return result
    }
}
