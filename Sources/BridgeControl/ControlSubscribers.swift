import Foundation

/// The clients that want `ctl.state`: each one that sent `ctl.sub` within the last
/// `lifetime` seconds, at most `capacity` of them.
public struct ControlSubscribers: Hashable, Sendable {
    public struct Client: Hashable, Sendable {
        /// Where `ctl.state` goes, on 127.0.0.1.
        public var port: UInt16
        /// The `client` text of its last `ctl.sub`, for logs.
        public var name: String?
        /// `ProcessInfo.systemUptime` of its last `ctl.sub`.
        public var lastSeen: TimeInterval
    }

    public let lifetime: TimeInterval
    public let capacity: Int
    /// In the order they first subscribed.
    public private(set) var clients: [Client] = []

    public init(lifetime: TimeInterval = ControlProtocol.subscriptionLifetime, capacity: Int = ControlProtocol.maxSubscribers) {
        self.lifetime = lifetime
        self.capacity = max(1, capacity)
    }

    /// Records a `ctl.sub` from `port` at `now`. Expired clients are dropped first; when the list is
    /// still full, the client heard from least recently makes room. Returns true for a new client.
    @discardableResult
    public mutating func subscribe(port: UInt16, name: String?, at now: TimeInterval) -> Bool {
        prune(at: now)
        if let index = clients.firstIndex(where: { $0.port == port }) {
            clients[index].lastSeen = now
            if let name { clients[index].name = name }
            return false
        }
        while clients.count >= capacity, let stalest = clients.indices.min(by: { clients[$0].lastSeen < clients[$1].lastSeen }) {
            clients.remove(at: stalest)
        }
        clients.append(Client(port: port, name: name, lastSeen: now))
        return true
    }

    /// Drops clients not heard from for longer than `lifetime`. Returns the dropped ones.
    @discardableResult
    public mutating func prune(at now: TimeInterval) -> [Client] {
        let expired = clients.filter { !isLive($0, at: now) }
        if !expired.isEmpty { clients = clients.filter { isLive($0, at: now) } }
        return expired
    }

    /// Clients still subscribed at `now`.
    public func live(at now: TimeInterval) -> [Client] {
        clients.filter { isLive($0, at: now) }
    }

    /// Forgets every client.
    public mutating func removeAll() {
        clients = []
    }

    private func isLive(_ client: Client, at now: TimeInterval) -> Bool {
        now - client.lastSeen <= lifetime
    }
}
