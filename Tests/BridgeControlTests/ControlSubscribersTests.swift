import BridgeControl
import Testing

@Suite struct ControlSubscribersTests {
    @Test func defaultsFollowTheProtocol() {
        let subscribers = ControlSubscribers()
        #expect(subscribers.lifetime == 6)
        #expect(subscribers.capacity == 8)
    }

    @Test func aClientExpiresSixSecondsAfterItsLastSubscribe() {
        var subscribers = ControlSubscribers()
        let isNew = subscribers.subscribe(port: 5000, name: "streamdeck", at: 100)
        #expect(isNew)
        #expect(subscribers.live(at: 105.9).map(\.port) == [5000])
        #expect(subscribers.live(at: 106).map(\.port) == [5000])
        #expect(subscribers.live(at: 106.1).isEmpty)

        // A keep-alive every 2 s keeps it subscribed indefinitely.
        var now = 100.0
        for _ in 0..<10 {
            now += 2
            let renewedIsNew = subscribers.subscribe(port: 5000, name: "streamdeck", at: now)
            #expect(!renewedIsNew)
        }
        #expect(subscribers.live(at: now + 5).map(\.port) == [5000])
        let expired = subscribers.prune(at: now + 7)
        #expect(expired.map(\.port) == [5000])
        #expect(subscribers.clients.isEmpty)
    }

    @Test func resubscribingKeepsOneEntryAndUpdatesTheName() {
        var subscribers = ControlSubscribers()
        subscribers.subscribe(port: 5000, name: "old", at: 0)
        subscribers.subscribe(port: 5001, name: nil, at: 0.5)
        let renamedIsNew = subscribers.subscribe(port: 5000, name: "streamdeck", at: 1)
        #expect(!renamedIsNew)
        let unnamedIsNew = subscribers.subscribe(port: 5000, name: nil, at: 1.5)
        #expect(!unnamedIsNew)
        #expect(subscribers.clients.map(\.port) == [5000, 5001])
        #expect(subscribers.clients.first?.name == "streamdeck")
        #expect(subscribers.clients.first?.lastSeen == 1.5)
    }

    @Test func aNinthClientReplacesTheStalest() {
        var subscribers = ControlSubscribers()
        for k in 0..<8 {
            subscribers.subscribe(port: UInt16(6000 + k), name: nil, at: Double(k) * 0.1)
        }
        // Port 6000 renews; 6001 is now the one heard from least recently. Nobody has expired yet.
        subscribers.subscribe(port: 6000, name: nil, at: 0.8)
        let ninthIsNew = subscribers.subscribe(port: 7000, name: "new", at: 0.9)
        #expect(ninthIsNew)
        #expect(subscribers.clients.count == 8)
        #expect(!subscribers.clients.map(\.port).contains(6001))
        #expect(subscribers.clients.map(\.port).contains(6000))
        #expect(subscribers.clients.last?.port == 7000)
    }

    @Test func expiredClientsMakeRoomBeforeAnyoneIsEvicted() {
        var subscribers = ControlSubscribers()
        for k in 0..<8 {
            subscribers.subscribe(port: UInt16(6000 + k), name: nil, at: k < 4 ? 0 : 10)
        }
        subscribers.subscribe(port: 7000, name: nil, at: 10.5)
        #expect(subscribers.clients.map(\.port) == [6004, 6005, 6006, 6007, 7000])
    }

    @Test func removeAllForgetsEveryone() {
        var subscribers = ControlSubscribers(lifetime: 1, capacity: 2)
        subscribers.subscribe(port: 1, name: nil, at: 0)
        subscribers.subscribe(port: 2, name: nil, at: 0)
        subscribers.subscribe(port: 3, name: nil, at: 0.1)
        #expect(subscribers.clients.map(\.port) == [2, 3])
        subscribers.removeAll()
        #expect(subscribers.live(at: 0.2).isEmpty)
    }
}
