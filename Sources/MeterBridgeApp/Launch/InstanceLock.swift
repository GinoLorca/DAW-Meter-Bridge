import Darwin
import Foundation

/// One running app per data folder.
///
/// An exclusive `flock` on `.meterbridge.lock` in the folder that holds layouts.json, kept for the life of
/// the process (the system drops it when the process exits, even after a crash). Two instances that share
/// that folder would overwrite each other's layouts.json and stack duplicate panels; instances started
/// with a different `--data-dir` (tests, demos) lock a different file and run side by side. `--snapshot`
/// runs never save, so they don't take the lock.
final class InstanceLock {
    /// The lock file.
    let url: URL
    private let descriptor: Int32

    private init(url: URL, descriptor: Int32) {
        self.url = url
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    enum Outcome {
        /// This process holds the lock; keep the object alive until quitting.
        case acquired(InstanceLock)
        /// Another process holds it: another copy of the app uses this folder.
        case heldElsewhere(URL)
        /// The lock file could not be created or locked (`errno`); carry on without a lock.
        case unavailable(URL, Int32)
    }

    static let fileName = ".meterbridge.lock"

    /// Posted (distributed) by a second launch, with the lock file's path as the object, so the running
    /// copy can show itself.
    static let secondLaunchNotification = Notification.Name("com.ginolorca.DAWMeterBridge.secondLaunch")

    /// Tries to take the lock for `folder` (created if missing) without waiting.
    static func acquire(in folder: URL) -> Outcome {
        let url = folder.appendingPathComponent(fileName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .unavailable(url, EACCES)
        }
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return .unavailable(url, errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            return code == EWOULDBLOCK ? .heldElsewhere(url) : .unavailable(url, code)
        }
        return .acquired(InstanceLock(url: url, descriptor: descriptor))
    }

    /// Asks the copy holding `lockURL` to show itself.
    static func notifyRunningInstance(lockURL: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            secondLaunchNotification,
            object: lockURL.path,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Calls `handler` on the main actor when a second launch for this lock file asks us to show ourselves.
    func observeSecondLaunches(_ handler: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.secondLaunchNotification,
            object: url.path,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
