import Foundation
import Testing
@testable import BridgeProtocol
import MeterCore

@Suite("Datagram size")
struct DatagramSizeTests {
    /// Widest possible id in decimal.
    static let widest = TrackID(Int64.min)

    @Test func outgoingMessagesFitWithWorstCaseValues() throws {
        let messages: [OutgoingMessage] = [
            .subscribe(SubscribeMessage(port: 65535, hz: Int.max, app: Int.max)),
            .watch(WatchMessage(ids: Array(repeating: Self.widest, count: WireProtocol.maxMeterEntries))),
            .command(CommandMessage(.select(Self.widest))),
            .command(CommandMessage(.setMute(Self.widest, false))),
            .command(CommandMessage(.setSolo(Self.widest, false, exclusive: false))),
            .command(CommandMessage(.setArm(Self.widest, false))),
            .command(CommandMessage(.setVolume(Self.widest, 0.123456789123))),
            .command(CommandMessage(.endVolumeDrag(Self.widest, 0.123456789123))),
        ]
        for message in messages {
            let size = try WireCodec.encode(message).count
            #expect(size <= WireProtocol.maxDatagramSize)
            if case .command = message { #expect(size < 128, "cmd should be tiny: \(size) bytes") }
        }
    }

    @Test func fullMeterMessageFits() throws {
        let entries = (0..<WireProtocol.maxMeterEntries).map { _ in WireMeter(id: Self.widest, left: 0.1234, right: 0.9876) }
        #expect(try WireCodec.encode(MetersMessage(seq: Int.max, entries: entries)).count <= WireProtocol.maxDatagramSize)
    }

    @Test func helloWithFullCurveFits() throws {
        let hello = HelloMessage(script: "0.1.0", live: "12.4.6", session: Int64.max, hz: 30, vc: VolumeCurveTable(sampling: .liveApproximation))
        #expect(try WireCodec.encode(hello).count <= WireProtocol.maxDatagramSize)
    }

    @Test func oversizedMessagesAreRefused() {
        let ids = Array(repeating: Self.widest, count: 1000)
        #expect(throws: BridgeProtocolError.self) { try WireCodec.encode(WatchMessage(ids: ids)) }
        do {
            _ = try WireCodec.encode(WatchMessage(ids: ids))
        } catch {
            guard case let .oversized(size) = error else {
                Issue.record("expected oversized, got \(error)")
                return
            }
            #expect(size > WireProtocol.maxDatagramSize)
        }
    }
}
