import BridgeControl
import Foundation

/// Connects the control protocol (docs/CONTROL.md, UDP 127.0.0.1:47802) to the controller: commands go to
/// `AppController.perform(_:)`, and `ctl.state` follows `AppController.controlState`.
///
/// Started only by the menu-bar app, never in `--snapshot` or `--demo-edit` runs. When the port is in use
/// (another copy of the app, a test run) the app runs without it, says so in the menu and keeps retrying.
@MainActor
final class ControlService {
    private let server: ControlServer
    private weak var controller: AppController?
    /// The menu warning shown while the port is in use.
    private var warning: String?

    init(controller: AppController, port: UInt16) {
        self.controller = controller
        server = ControlServer(configuration: ControlServer.Configuration(port: port)) { [weak controller] in
            controller?.controlState
                ?? ControlState(bridge: false, main: false, edit: false, source: SourceKind.simulator.rawValue, connected: false, app: AppInfo.version)
        }
        server.onCommand = { [weak controller] command in controller?.perform(command) }
        server.onListeningChange = { [weak self] in self?.listeningChanged() }
    }

    func start() {
        server.start()
    }

    func stop() {
        server.stop()
    }

    /// Pushes `ctl.state` to the subscribed clients if it changed (call on every status change).
    func stateMayHaveChanged() {
        server.stateMayHaveChanged()
    }

    private func listeningChanged() {
        guard let controller else { return }
        if let warning { controller.appMessages.removeAll { $0 == warning } }
        warning = nil
        if let error = server.bindError {
            let port = server.configuration.port
            // Usually another copy of the app holds the port (one started without --control-port).
            let reason = if case .addressInUse = error {
                "UDP port \(port) is in use (another copy of DAW Meter Bridge, or another app)"
            } else {
                "\(error.message) (port \(port))"
            }
            let text = "Stream Deck control is off: \(reason). Retrying."
            controller.appMessages.append(text)
            warning = text
        }
        controller.onStatusChange?()
    }
}
