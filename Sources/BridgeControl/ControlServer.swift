import Dispatch
import Foundation
import MeterSources
import os

let controlLog = Logger(subsystem: "DAWMeterBridge", category: "Control")

/// The app side of the control protocol (docs/CONTROL.md): listens on 127.0.0.1:47802 for `ctl.sub` and
/// `ctl`, keeps the subscribed clients, and sends them `ctl.state`.
///
/// - Every `ctl.sub` is answered with `ctl.state` to the client's port.
/// - Every `ctl` is applied through ``onCommand``, then answered with `ctl.state` to the sender's port
///   and pushed to every subscriber.
/// - ``stateMayHaveChanged()`` pushes `ctl.state` to every subscriber when the state differs from the
///   last one pushed. Call it whenever the bridge, the Main meter, edit mode or the source may have changed.
/// - If the port is in use, the server logs it, reports ``bindError`` and retries every
///   ``Configuration/bindRetryInterval``; the app keeps running without it meanwhile.
///
/// Socket I/O runs on a private serial queue (`UDPEndpoint`); everything else runs on the main actor.
@MainActor
public final class ControlServer {
    public struct Configuration: Hashable, Sendable {
        /// Port to listen on, on 127.0.0.1. 0 picks any free port (tests); see ``ControlServer/boundPort``.
        public var port: UInt16
        /// Seconds a client stays subscribed after its last `ctl.sub`.
        public var subscriptionLifetime: TimeInterval
        /// Most clients kept at once.
        public var maxSubscribers: Int
        /// Seconds between attempts to bind the port while it is in use.
        public var bindRetryInterval: TimeInterval

        public init(
            port: UInt16 = ControlProtocol.defaultPort,
            subscriptionLifetime: TimeInterval = ControlProtocol.subscriptionLifetime,
            maxSubscribers: Int = ControlProtocol.maxSubscribers,
            bindRetryInterval: TimeInterval = 5
        ) {
            self.port = port
            self.subscriptionLifetime = subscriptionLifetime
            self.maxSubscribers = maxSubscribers
            self.bindRetryInterval = bindRetryInterval
        }
    }

    public let configuration: Configuration
    /// Applies a command. `ctl.state` is sent after it returns, so it should finish the change synchronously.
    public var onCommand: (@MainActor (ControlCommand) -> Void)?
    /// Called when the server starts listening or finds its port in use.
    public var onListeningChange: (@MainActor () -> Void)?
    /// The port listened on, while listening.
    public private(set) var boundPort: UInt16?
    /// Why the port could not be bound, while it can't.
    public private(set) var bindError: UDPSocketError?

    private let currentState: @MainActor () -> ControlState
    private var endpoint: UDPEndpoint?
    private var subscribers: ControlSubscribers
    private var lastPushed: ControlState?
    private var isHandlingCommand = false
    private var retryTimer: (any DispatchSourceTimer)?
    private var running = false
    private var droppedCount = 0

    /// A server that reads the app's state with `state`; nothing happens until ``start()``.
    public init(configuration: Configuration = Configuration(), state: @escaping @MainActor () -> ControlState) {
        self.configuration = configuration
        currentState = state
        subscribers = ControlSubscribers(lifetime: configuration.subscriptionLifetime, capacity: configuration.maxSubscribers)
    }

    /// Whether the port is bound.
    public var isListening: Bool { endpoint != nil }

    /// Clients subscribed now.
    public var liveSubscribers: [ControlSubscribers.Client] {
        subscribers.live(at: Self.now())
    }

    // MARK: Lifecycle

    /// Binds the port (or keeps retrying while it is in use).
    public func start() {
        guard !running else { return }
        running = true
        openSocket()
    }

    /// Closes the socket and forgets the clients (they treat the app as offline after 5 s).
    public func stop() {
        guard running else { return }
        running = false
        retryTimer?.cancel()
        retryTimer = nil
        endpoint?.close()
        endpoint = nil
        boundPort = nil
        subscribers.removeAll()
        lastPushed = nil
    }

    /// Pushes `ctl.state` to every subscriber if it changed since the last push.
    public func stateMayHaveChanged() {
        guard running, !isHandlingCommand, endpoint != nil else { return }
        let state = currentState()
        guard state != lastPushed else { return }
        lastPushed = state
        subscribers.prune(at: Self.now())
        send(state, to: subscribers.clients.map(\.port))
    }

    // MARK: Receiving

    private func receive(_ datagrams: [ReceivedDatagram]) {
        for datagram in datagrams {
            guard running else { return }
            handle(datagram)
        }
    }

    private func handle(_ datagram: ReceivedDatagram) {
        let request: ControlRequest
        do {
            request = try ControlCodec.decodeRequest(datagram.data)
        } catch {
            droppedCount += 1
            if droppedCount <= 5 || droppedCount % 100 == 0 {
                controlLog.warning("Dropping control datagram #\(self.droppedCount): \(String(describing: error), privacy: .public)")
            }
            return
        }
        switch request {
        case let .subscribe(port, client):
            guard let port = port ?? datagram.senderPort else { return }
            if subscribers.subscribe(port: port, name: client, at: datagram.time) {
                controlLog.info("Control client \(client ?? "unnamed", privacy: .public) subscribed on port \(port)")
            }
            send(currentState(), to: [port])
        case let .command(command):
            controlLog.info("Control command \(command.description, privacy: .public)")
            isHandlingCommand = true
            onCommand?(command)
            isHandlingCommand = false
            // One ctl.state for the sender and every subscriber, whether or not anything changed.
            let state = currentState()
            lastPushed = state
            var ports = datagram.senderPort.map { [$0] } ?? []
            for client in subscribers.live(at: datagram.time) where !ports.contains(client.port) {
                ports.append(client.port)
            }
            send(state, to: ports)
        }
    }

    private func send(_ state: ControlState, to ports: [UInt16]) {
        guard let endpoint, !ports.isEmpty else { return }
        let data = ControlCodec.encode(state)
        for port in ports {
            endpoint.send(data, toPort: port) { error in
                controlLog.debug("Sending ctl.state to port \(port) failed: \(error.message, privacy: .public)")
            }
        }
    }

    // MARK: Socket

    private func openSocket() {
        do {
            let endpoint = try UDPEndpoint(port: configuration.port, label: "DAWMeterBridge.Control.socket") { [weak self] datagrams in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.receive(datagrams) }
                }
            }
            self.endpoint = endpoint
            boundPort = endpoint.port
            let wasFailing = bindError != nil
            bindError = nil
            retryTimer?.cancel()
            retryTimer = nil
            controlLog.info("Control server listening on 127.0.0.1:\(endpoint.port)\(wasFailing ? " (port free again)" : "", privacy: .public)")
            onListeningChange?()
        } catch {
            if bindError == nil {
                controlLog.error("Control server not listening: \(error.message, privacy: .public). Retrying every \(Int(self.configuration.bindRetryInterval)) s.")
                bindError = error
                onListeningChange?()
            }
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        let interval = max(0.05, configuration.bindRetryInterval)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.endpoint == nil else { return }
                self.openSocket()
            }
        }
        timer.resume()
        retryTimer = timer
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
