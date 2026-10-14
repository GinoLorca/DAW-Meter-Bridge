import AppKit
import BridgeControl
import Carbon.HIToolbox

/// Receives `dawmeterbridge://` URLs (docs/CONTROL.md) as `kAEGetURL` Apple Events and applies them,
/// without taking keyboard focus from the DAW.
///
/// Install it in `applicationWillFinishLaunching`, so a URL that launches the app is received too; such
/// commands wait until `perform` is set (after the controller started) and then apply as to an app that
/// showed nothing yet, so a toggle that launched the app shows (`ControlURL.launchResolved`). Unknown URLs
/// are logged and ignored.
@MainActor
final class URLCommandHandler: NSObject {
    /// Applies a command. Commands that arrive before it is set are queued.
    var perform: (@MainActor (ControlCommand) -> Void)? {
        didSet { flush() }
    }

    private var pending: [ControlCommand] = []
    private let activationGuard = ActivationGuard()

    /// Registers for `kAEGetURL` and starts watching which app is in front.
    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        activationGuard.start()
    }

    func uninstall() {
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        activationGuard.stop()
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        // Opening a URL makes LaunchServices activate the app; hand activation back to the DAW.
        activationGuard.urlArrived()
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text),
              let command = ControlURL.command(from: url) else {
            let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? "(none)"
            appLog.warning("Ignoring URL \(text, privacy: .public): not a dawmeterbridge://bridge|main|edit/toggle|show|hide command")
            return
        }
        appLog.info("URL command \(command.description, privacy: .public)")
        if let perform {
            perform(command)
        } else {
            pending.append(command)
        }
    }

    /// Applies the commands of the URLs that launched the app.
    private func flush() {
        guard let perform, !pending.isEmpty else { return }
        let commands = ControlURL.launchResolved(pending)
        pending = []
        commands.forEach(perform)
    }
}

/// Hands activation back to the app that was in front when opening a URL activated this app.
///
/// LaunchServices activates the app that opens a URL (unless the opener asked otherwise, as `open -g`
/// does), even an accessory app without windows, which would take the keyboard from Live. For a moment
/// after each URL, any activation of this app is undone. The one exception: the user was already working
/// in this app (it had been in front for a while when the URL arrived) and a titled window of ours
/// (Settings, an alert) is open; then it keeps the keyboard. A Settings window merely left open behind
/// the DAW doesn't count, so it never steals focus from the DAW.
@MainActor
final class ActivationGuard {
    /// How long after a URL an activation counts as caused by it.
    static let window: TimeInterval = 1.5
    /// An activation more recent than this when a URL arrives may have been caused by the URL itself.
    static let settleTime: TimeInterval = 0.5

    private var lastOtherApp: NSRunningApplication?
    private var guardUntil: TimeInterval = 0
    private var observer: (any NSObjectProtocol)?
    private var activeObserver: (any NSObjectProtocol)?
    /// When this app last became active (`NSApp.isActive` turned true).
    private var becameActiveAt: TimeInterval = 0
    /// This app was in front, and had been for `settleTime`, when the last URL arrived.
    private var wasInFrontBeforeURL = false

    func start() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            lastOtherApp = front
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
        // Posted together with `NSApp.isActive` turning true (the workspace notification may come later).
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActiveAt = ActivationGuard.now }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        observer = nil
        activeObserver = nil
    }

    /// A URL arrived: undo this app's activation now and during the next `window` seconds.
    func urlArrived() {
        wasInFrontBeforeURL = NSApp.isActive && Self.now - becameActiveAt > Self.settleTime
        guardUntil = Self.now + Self.window
        handBack()
        // The activation may come just after the event; check again shortly.
        for delay in [0.05, 0.25, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.handBack() }
            }
        }
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app else { return }
        if app == NSRunningApplication.current {
            handBack()
        } else {
            lastOtherApp = app
        }
    }

    private func handBack() {
        guard NSApp.isActive, Self.now < guardUntil else { return }
        // The user was working in Settings or an alert of ours when the URL came: leave it in front.
        let ownWindowNeedsKeys = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        guard !(wasInFrontBeforeURL && ownWindowNeedsKeys) else { return }
        guard let previous = lastOtherApp, !previous.isTerminated else {
            NSApp.deactivate()
            return
        }
        NSApp.yieldActivation(to: previous)
        previous.activate()
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
