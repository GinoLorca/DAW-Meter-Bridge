import BridgeProtocol
import Darwin
import Foundation
import MeterCore

/// A stand-in for the Live Remote Script: a real UDP socket on 127.0.0.1 (any free port)
/// that receives the app's messages and sends script messages back.
@MainActor
final class FakeScript {
    let port: UInt16
    private let fd: Int32
    /// Datagrams received but not consumed yet, oldest first.
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
            close(fd)
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

    deinit { close(fd) }

    // MARK: Sending

    func send(_ message: IncomingMessage, to port: UInt16) throws {
        sendRaw(try WireCodec.encode(message), to: port)
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

    // MARK: Receiving

    /// Moves every pending datagram into the inbox.
    private func pump() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            guard count >= 0 else { return }
            inbox.append(Data(buffer[0..<count]))
        }
    }

    /// Waits for the next message for which `predicate` holds, consuming everything before it.
    /// Returns the message and its raw bytes, or nil on timeout.
    func next(
        timeout: TimeInterval = 5,
        where predicate: (OutgoingMessage) -> Bool = { _ in true }
    ) async -> (message: OutgoingMessage, raw: Data)? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            pump()
            while !inbox.isEmpty {
                let raw = inbox.removeFirst()
                guard let message = try? WireCodec.decodeOutgoing(raw) else { continue }
                if predicate(message) { return (message, raw) }
            }
            try? await Task.sleep(for: .milliseconds(5))
        } while Date() < deadline
        return nil
    }

    /// Waits for the next `cmd`, skipping `sub` and `watch`.
    func nextCommand(timeout: TimeInterval = 5) async -> (command: BridgeCommand, raw: Data)? {
        guard let (message, raw) = await next(timeout: timeout, where: { if case .command = $0 { true } else { false } }),
              case let .command(body) = message else { return nil }
        return (body.command, raw)
    }

    /// Collects messages until `done` holds for what has arrived, or `timeout` passes.
    func collect(timeout: TimeInterval = 5, until done: ([OutgoingMessage]) -> Bool) async -> [OutgoingMessage] {
        let deadline = Date().addingTimeInterval(timeout)
        var collected: [OutgoingMessage] = []
        repeat {
            pump()
            collected += inbox.compactMap { try? WireCodec.decodeOutgoing($0) }
            inbox.removeAll()
            if done(collected) { return collected }
            try? await Task.sleep(for: .milliseconds(5))
        } while Date() < deadline
        return collected
    }

    /// Collects every message that arrives within `duration`.
    func collect(for duration: TimeInterval) async -> [OutgoingMessage] {
        try? await Task.sleep(for: .seconds(duration))
        pump()
        defer { inbox.removeAll() }
        return inbox.compactMap { try? WireCodec.decodeOutgoing($0) }
    }

    /// Drops everything received so far.
    func discardInbox() {
        pump()
        inbox.removeAll()
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
