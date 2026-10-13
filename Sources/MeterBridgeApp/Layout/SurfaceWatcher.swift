import CoreMIDI
import Foundation

/// Calls `onChange` (debounced) when CoreMIDI's device setup changes, e.g. SSL 360° starts and publishes
/// its "SSL V-MIDI" ports, or a WING is plugged in over USB. The app then re-reads the endpoint names
/// (`SurfaceDetector`) and re-picks the layout profile.
///
/// Read-only: it creates a MIDI client for setup notifications and never opens a port or sends MIDI.
/// If the client can't be created, it falls back to checking every few seconds.
@MainActor
final class SurfaceWatcher {
    private let onChange: @MainActor () -> Void
    private let debounce: Duration
    private let pollInterval: TimeInterval
    private var client = MIDIClientRef()
    private var pending: Task<Void, Never>?
    private var pollTimer: Timer?

    init(debounce: Duration = .seconds(1), pollInterval: TimeInterval = 5, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        self.debounce = debounce
        self.pollInterval = pollInterval
    }

    func start() {
        guard client == 0, pollTimer == nil else { return }
        if let created = Self.makeClient(onSetupChanged: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleCheck() } }
        }) {
            client = created
        } else {
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        pollTimer?.invalidate()
        pollTimer = nil
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    private func scheduleCheck() {
        pending?.cancel()
        let delay = debounce
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.onChange()
        }
    }

    /// A notification-only MIDI client. Nonisolated so CoreMIDI may call the block on its own thread.
    nonisolated private static func makeClient(onSetupChanged: @escaping @Sendable () -> Void) -> MIDIClientRef? {
        var client = MIDIClientRef()
        let status = MIDIClientCreateWithBlock("DAW Meter Bridge surface detection" as CFString, &client) { notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                onSetupChanged()
            default:
                break
            }
        }
        return status == noErr && client != 0 ? client : nil
    }
}
