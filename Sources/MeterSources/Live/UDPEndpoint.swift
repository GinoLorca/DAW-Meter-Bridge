import Darwin
import Dispatch
import Foundation

/// Why the UDP socket could not be opened.
public enum UDPSocketError: Error, Hashable, Sendable {
    /// Another process already listens on the port (`EADDRINUSE`).
    case addressInUse(port: UInt16)
    /// A socket call failed; `call` names it, `code` is `errno`.
    case system(call: String, code: Int32)

    /// A sentence for the UI and the log.
    public var message: String {
        switch self {
        case let .addressInUse(port):
            "Port \(port) on 127.0.0.1 is already in use by another app"
        case let .system(call, code):
            "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

/// A datagram and the time it was read (`ProcessInfo.systemUptime`).
struct ReceivedDatagram: Sendable {
    var data: Data
    var time: TimeInterval
}

/// A UDP socket bound to 127.0.0.1. All socket I/O runs on a private serial queue; received
/// datagrams are handed to `onReceive` in batches on that queue.
final class UDPEndpoint: @unchecked Sendable {
    // @unchecked: `fd` and `buffer` are only touched on `queue` after init returns, and
    // `readSource` is only set during init and cancelled through the queue.
    private let queue: DispatchQueue
    private let fd: Int32
    private var buffer = [UInt8](repeating: 0, count: 65_536)
    private var readSource: (any DispatchSourceRead)?
    private let cancelled = DispatchSemaphore(value: 0)
    private var isClosed = false

    /// The port actually bound (differs from the requested one when that was 0).
    let port: UInt16

    /// Opens a non-blocking UDP socket on 127.0.0.1:`port` (0 = any free port) and starts reading.
    init(port requestedPort: UInt16, label: String, onReceive: @escaping @Sendable ([ReceivedDatagram]) -> Void) throws(UDPSocketError) {
        queue = DispatchQueue(label: label, qos: .userInteractive)
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw .system(call: "socket", code: errno) }

        var bufferSize: Int32 = 1 << 20
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        var address = Self.loopback(port: requestedPort)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw code == EADDRINUSE ? .addressInUse(port: requestedPort) : .system(call: "bind", code: code)
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        port = UInt16(bigEndian: actual.sin_port)
        self.fd = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let datagrams = self.drain()
            if !datagrams.isEmpty { onReceive(datagrams) }
        }
        let cancelled = cancelled
        source.setCancelHandler {
            Darwin.close(fd)
            cancelled.signal()
        }
        readSource = source
        source.resume()
    }

    deinit {
        if !isClosed { readSource?.cancel() }
    }

    /// Sends one datagram to 127.0.0.1:`port`. Errors are reported to `onError` on the socket queue.
    func send(_ data: Data, toPort port: UInt16, onError: (@Sendable (UDPSocketError) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            var address = Self.loopback(port: port)
            let sent = data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(self.fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent < 0 { onError?(.system(call: "sendto", code: errno)) }
        }
    }

    /// Stops reading and closes the socket. Returns once the descriptor is closed, so the port can
    /// be bound again right away.
    func close() {
        let source: (any DispatchSourceRead)? = queue.sync {
            guard !isClosed else { return nil }
            isClosed = true
            return readSource
        }
        guard let source else { return }
        source.cancel()
        _ = cancelled.wait(timeout: .now() + 1)
    }

    /// Reads every pending datagram. Runs on `queue`.
    private func drain() -> [ReceivedDatagram] {
        var datagrams: [ReceivedDatagram] = []
        while !isClosed {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if count < 0 {
                if errno == EINTR { continue }
                break // EAGAIN/EWOULDBLOCK: nothing more to read; other errors: try again next event.
            }
            datagrams.append(ReceivedDatagram(
                data: Data(buffer[0..<count]),
                time: ProcessInfo.processInfo.systemUptime
            ))
        }
        return datagrams
    }

    private static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }
}
