import Foundation
import Testing
@testable import BridgeProtocol
import MeterCore

@Suite("Track list assembly")
struct TrackListAssemblerTests {
    static func tracks(_ count: Int, base: Int64 = 1000) -> [WireTrack] {
        (0..<count).map { sampleTrack(TrackID(base + Int64($0)), index: $0, name: "T\($0)") }
    }

    static func parts(_ list: [WireTrack], gen: Int, size: Int) -> [TracksMessage] {
        let chunks = stride(from: 0, to: list.count, by: size).map { Array(list[$0..<min($0 + size, list.count)]) }
        return chunks.enumerated().map {
            TracksMessage(gen: gen, part: $0, parts: chunks.count, total: list.count, items: $1)
        }
    }

    @Test func singlePartCompletesImmediately() {
        var assembler = TrackListAssembler()
        let list = Self.tracks(3)
        #expect(assembler.add(Self.parts(list, gen: 1, size: 32)[0], at: 0) == list)
        #expect(assembler.completedGeneration == 1)
        #expect(assembler.pendingGeneration == nil)
    }

    @Test func emptyListIsOnePart() throws {
        var assembler = TrackListAssembler()
        let parts = try TracksMessage.split([], gen: 4)
        #expect(parts.count == 1)
        #expect(assembler.add(parts[0], at: 0) == [])
    }

    @Test func partsInOrder() {
        var assembler = TrackListAssembler()
        let list = Self.tracks(70)
        let parts = Self.parts(list, gen: 2, size: 32)
        #expect(parts.count == 3)
        #expect(assembler.add(parts[0], at: 0) == nil)
        #expect(assembler.add(parts[1], at: 0.01) == nil)
        #expect(assembler.pendingGeneration == 2)
        #expect(assembler.add(parts[2], at: 0.02) == list)
    }

    @Test func partsOutOfOrderAssembleInPartOrder() {
        var assembler = TrackListAssembler()
        let list = Self.tracks(70)
        let parts = Self.parts(list, gen: 2, size: 32)
        #expect(assembler.add(parts[2], at: 0) == nil)
        #expect(assembler.add(parts[0], at: 0) == nil)
        #expect(assembler.add(parts[0], at: 0) == nil) // duplicate
        #expect(assembler.add(parts[1], at: 0) == list)
    }

    @Test func incompleteGenerationTimesOut() {
        var assembler = TrackListAssembler(timeout: 1)
        let parts = Self.parts(Self.tracks(40), gen: 5, size: 32)
        #expect(assembler.add(parts[0], at: 10) == nil)
        let expiredEarly = assembler.expire(at: 10.9)
        #expect(!expiredEarly)
        let expiredLate = assembler.expire(at: 11.01)
        #expect(expiredLate)
        #expect(assembler.pendingGeneration == nil)
        // The late part of the discarded generation is ignored, not completed.
        #expect(assembler.add(parts[1], at: 11.2) == nil)
        #expect(assembler.pendingGeneration == nil)
        // A later generation still works.
        let fresh = Self.tracks(2)
        #expect(assembler.add(Self.parts(fresh, gen: 6, size: 32)[0], at: 11.3) == fresh)
    }

    @Test func timeoutAlsoAppliesWhenTheNextPartArrivesLate() {
        var assembler = TrackListAssembler(timeout: 1)
        let parts = Self.parts(Self.tracks(40), gen: 5, size: 32)
        #expect(assembler.add(parts[0], at: 0) == nil)
        #expect(assembler.add(parts[1], at: 1.5) == nil)
        #expect(assembler.completedGeneration == nil)
    }

    @Test func newerGenerationDiscardsIncompleteOlder() {
        var assembler = TrackListAssembler()
        let old = Self.parts(Self.tracks(40), gen: 7, size: 32)
        let newList = Self.tracks(40, base: 5000)
        let new = Self.parts(newList, gen: 8, size: 32)
        #expect(assembler.add(old[0], at: 0) == nil)
        #expect(assembler.add(new[1], at: 0.1) == nil)
        #expect(assembler.pendingGeneration == 8)
        #expect(assembler.add(old[1], at: 0.2) == nil) // older generation: ignored
        #expect(assembler.add(new[0], at: 0.3) == newList)
    }

    @Test func staleGenerationsAfterCompletionAreIgnored() {
        var assembler = TrackListAssembler()
        let list = Self.tracks(2)
        #expect(assembler.add(Self.parts(list, gen: 9, size: 32)[0], at: 0) == list)
        #expect(assembler.add(Self.parts(Self.tracks(1), gen: 9, size: 32)[0], at: 0.1) == nil)
        #expect(assembler.add(Self.parts(Self.tracks(1), gen: 3, size: 32)[0], at: 0.1) == nil)
        #expect(assembler.completedGeneration == 9)
    }

    @Test func resetAcceptsLowerGenerationsAgain() {
        var assembler = TrackListAssembler()
        #expect(assembler.add(Self.parts(Self.tracks(2), gen: 9, size: 32)[0], at: 0) != nil)
        assembler.reset()
        let list = Self.tracks(3)
        #expect(assembler.add(Self.parts(list, gen: 1, size: 32)[0], at: 0.1) == list)
    }

    @Test func invalidPartsAreIgnored() {
        var assembler = TrackListAssembler()
        let items = Self.tracks(1)
        #expect(assembler.add(TracksMessage(gen: 1, part: 2, parts: 2, total: 1, items: items), at: 0) == nil)
        #expect(assembler.add(TracksMessage(gen: 1, part: -1, parts: 2, total: 1, items: items), at: 0) == nil)
        #expect(assembler.add(TracksMessage(gen: 1, part: 0, parts: 0, total: 1, items: items), at: 0) == nil)
        #expect(assembler.pendingGeneration == nil)
        // A part count that disagrees with the pending generation is ignored.
        #expect(assembler.add(TracksMessage(gen: 2, part: 0, parts: 2, total: 2, items: items), at: 0) == nil)
        #expect(assembler.add(TracksMessage(gen: 2, part: 1, parts: 3, total: 2, items: items), at: 0) == nil)
        #expect(assembler.add(TracksMessage(gen: 2, part: 1, parts: 2, total: 2, items: items), at: 0) == items + items)
    }

    @Test func splitRespectsItemAndByteLimits() throws {
        let longName = String(repeating: "Überlange Spur / ", count: 12)
        let list = (0..<150).map { sampleTrack(TrackID(Int64.max - Int64($0)), index: $0, name: "\($0) \(longName)") }
        let parts = try TracksMessage.split(list, gen: 3)
        #expect(parts.count > 5) // long names force fewer than 32 per part
        for part in parts {
            #expect(part.items.count <= WireProtocol.maxItemsPerPart)
            #expect(try WireCodec.encode(part).count <= WireProtocol.maxDatagramSize)
            #expect(part.parts == parts.count)
            #expect(part.total == list.count)
            #expect(part.gen == 3)
        }
        var assembler = TrackListAssembler()
        var result: [WireTrack]?
        for part in parts.reversed() {
            result = assembler.add(part, at: 0) ?? result
        }
        #expect(result == list)
    }

    @Test func splitUsesUpTo32ItemsForShortNames() throws {
        let parts = try TracksMessage.split(Self.tracks(65), gen: 1)
        #expect(parts.map(\.items.count) == [32, 32, 1])
    }

    @Test func splitRejectsARecordThatCannotFit() {
        let huge = sampleTrack(TrackID(1), name: String(repeating: "x", count: 9000))
        #expect(throws: BridgeProtocolError.self) { try TracksMessage.split([huge], gen: 1) }
    }
}
