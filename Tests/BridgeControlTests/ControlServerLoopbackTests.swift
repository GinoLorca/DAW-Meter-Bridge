import BridgeControl
import Darwin
import Foundation
import MeterSources
import Testing

/// ControlServer against fake clients (the Stream Deck plugin's side) over real UDP sockets on free ports.
@Suite("ControlServer loopback", .serialized)
@MainActor
struct ControlServerLoopbackTests {
    /// A fake app: the two switches, plus a count of applied commands.
    @MainActor
    final class FakeApp {
        var state = ControlState(bridge: true, main: false, edit: false, source: "simulator", connected: true, app: "test")
        var commands: [ControlCommand] = []

        func perform(_ command: ControlCommand) {
            commands.append(command)
            switch command.target {
            case .bridge: state.bridge = command.action.resolve(current: state.bridge)
            case .main: state.main = command.action.resolve(current: state.main)
            case .edit: state.edit = command.action.resolve(current: state.edit)
            }
        }
    }

    private func makeServer(_ app: FakeApp, lifetime: TimeInterval = 6, maxSubscribers: Int = 8) -> ControlServer {
        let server = ControlServer(configuration: .init(port: 0, subscriptionLifetime: lifetime, maxSubscribers: maxSubscribers)) { app.state }
        server.onCommand = { app.perform($0) }
        server.start()
        return server
    }

    @Test func subscribeIsAnsweredWithTheState() async throws {
        let app = FakeApp()
        let server = makeServer(app)
        defer { server.stop() }
        let port = try #require(server.boundPort)
        let client = try FakeClient()

        client.send(.subscribe(port: client.port, client: "streamdeck"), to: port)
        let state = await client.nextState()
        #expect(state == app.state)
        #expect(await waitUntil { server.liveSubscribers.map(\.port) == [client.port] })
        #expect(server.liveSubscribers.first?.name == "streamdeck")

        // A keep-alive without `port` is answered on the port it came from.
        client.send(.subscribe(port: nil, client: nil), to: port)
        #expect(await client.nextState() == app.state)
        #expect(server.liveSubscribers.count == 1)
    }

    @Test func aCommandIsAppliedAnsweredAndPushedToEverySubscriber() async throws {
        let app = FakeApp()
        let server = makeServer(app)
        defer { server.stop() }
        let port = try #require(server.boundPort)
        let deck = try FakeClient()
        let other = try FakeClient()
        let oneShot = try FakeClient()
        deck.send(.subscribe(port: deck.port, client: "streamdeck"), to: port)
        other.send(.subscribe(port: other.port, client: "other"), to: port)
        _ = await deck.nextState()
        _ = await other.nextState()

        // Toggle the bridge from a client that never subscribed: it gets the answer, both subscribers the push.
        oneShot.send(.command(ControlCommand(.bridge, .toggle)), to: port)
        let answer = await oneShot.nextState()
        #expect(answer?.bridge == false)
        #expect(await deck.nextState()?.bridge == false)
        #expect(await other.nextState()?.bridge == false)
        #expect(app.commands == [ControlCommand(.bridge, .toggle)])

        // Show the Main meter from the subscribed deck: exactly one ctl.state reaches it.
        deck.send(.command(ControlCommand(.main, .show)), to: port)
        #expect(await deck.nextState()?.main == true)
        #expect(await other.nextState()?.main == true)
        #expect(await deck.collectStates(for: 0.15).isEmpty)

        // A command that changes nothing is still answered and pushed.
        deck.send(.command(ControlCommand(.main, .show)), to: port)
        #expect(await deck.nextState()?.main == true)
        #expect(await other.nextState()?.main == true)
        #expect(app.state.main && !app.state.bridge)
    }

    @Test func stateChangesArePushedOnlyWhenSomethingChanged() async throws {
        let app = FakeApp()
        let server = makeServer(app)
        defer { server.stop() }
        let port = try #require(server.boundPort)
        let deck = try FakeClient()
        deck.send(.subscribe(port: deck.port, client: "streamdeck"), to: port)
        _ = await deck.nextState()

        server.stateMayHaveChanged() // first push after start
        _ = await deck.collectStates(for: 0.1)
        app.state.edit = true
        server.stateMayHaveChanged()
        #expect(await deck.nextState()?.edit == true)
        server.stateMayHaveChanged()
        server.stateMayHaveChanged()
        #expect(await deck.collectStates(for: 0.15).isEmpty)
        app.state.connected = false
        app.state.source = "live"
        server.stateMayHaveChanged()
        let pushed = await deck.nextState()
        #expect(pushed?.connected == false && pushed?.source == "live")
    }

    @Test func invalidDatagramsGetNoAnswer() async throws {
        let app = FakeApp()
        let server = makeServer(app)
        defer { server.stop() }
        let port = try #require(server.boundPort)
        let client = try FakeClient()
        for json in [
            #"{"v":2,"t":"ctl","op":"bridge"}"#,
            #"{"v":1,"t":"ctl.unknown"}"#,
            #"{"v":1,"t":"ctl","op":"edit"}"#,
            #"{"v":1,"t":"ctl","op":"bridge","on":"maybe"}"#,
            "garbage",
        ] {
            client.sendRaw(Data(json.utf8), to: port)
        }
        #expect(await client.collectStates(for: 0.2).isEmpty)
        #expect(app.commands.isEmpty)
        #expect(app.state.bridge)
        #expect(server.liveSubscribers.isEmpty)
    }

    @Test func subscribersExpireWithoutKeepAlives() async throws {
        let app = FakeApp()
        let server = makeServer(app, lifetime: 0.3)
        defer { server.stop() }
        let port = try #require(server.boundPort)
        let deck = try FakeClient()
        deck.send(.subscribe(port: deck.port, client: "streamdeck"), to: port)
        _ = await deck.nextState()
        try await Task.sleep(for: .milliseconds(450))
        #expect(server.liveSubscribers.isEmpty)
        app.state.bridge = false
        server.stateMayHaveChanged()
        #expect(await deck.collectStates(for: 0.15).isEmpty)
    }

    @Test func aBusyPortIsRetriedUntilItIsFree() async throws {
        // Hold a port, start a server on it, then free it.
        let holder = try FakeClient()
        let busyPort = holder.port
        let app = FakeApp()
        let server = ControlServer(configuration: .init(port: busyPort, bindRetryInterval: 0.1)) { app.state }
        var changes = 0
        server.onListeningChange = { changes += 1 }
        server.start()
        defer { server.stop() }
        #expect(!server.isListening)
        #expect(server.bindError == .addressInUse(port: busyPort))
        #expect(changes == 1)

        holder.close()
        #expect(await waitUntil { server.isListening })
        #expect(server.boundPort == busyPort)
        #expect(server.bindError == nil)
        #expect(changes == 2)

        let client = try FakeClient()
        client.send(.subscribe(port: client.port, client: nil), to: busyPort)
        #expect(await client.nextState() == app.state)
    }

    @Test func stopClosesThePortAndForgetsClients() async throws {
        let app = FakeApp()
        let server = makeServer(app)
        let port = try #require(server.boundPort)
        let deck = try FakeClient()
        deck.send(.subscribe(port: deck.port, client: nil), to: port)
        _ = await deck.nextState()
        server.stop()
        #expect(!server.isListening)
        #expect(server.liveSubscribers.isEmpty)
        // The port can be bound again at once.
        let again = ControlServer(configuration: .init(port: port)) { app.state }
        again.start()
        #expect(again.boundPort == port)
        again.stop()
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A stand-in for the Stream Deck plugin: a UDP socket on 127.0.0.1 (any free port).
@MainActor
final class FakeClient {
    let port: UInt16
    private var fd: Int32
    private var inbox: [Data] = []

    init() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var address = Self.loopback(port: 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        port = UInt16(bigEndian: actual.sin_port)
        self.fd = fd
    }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
    }

    func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }

    func send(_ request: ControlRequest, to port: UInt16) {
        sendRaw(ControlCodec.encode(request), to: port)
    }

    func sendRaw(_ data: Data, to port: UInt16) {
        var address = Self.loopback(port: port)
        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func pump() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while fd >= 0 {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            guard count >= 0 else { return }
            inbox.append(Data(buffer[0..<count]))
        }
    }

    /// The next `ctl.state`, or nil after `timeout`.
    func nextState(timeout: TimeInterval = 3) async -> ControlState? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            pump()
            while !inbox.isEmpty {
                if let state = try? ControlCodec.decodeState(inbox.removeFirst()) { return state }
            }
            try? await Task.sleep(for: .milliseconds(5))
        } while Date() < deadline
        return nil
    }

    /// Every `ctl.state` that arrives within `duration`.
    func collectStates(for duration: TimeInterval) async -> [ControlState] {
        try? await Task.sleep(for: .seconds(duration))
        pump()
        defer { inbox.removeAll() }
        return inbox.compactMap { try? ControlCodec.decodeState($0) }
    }

    static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }
}
