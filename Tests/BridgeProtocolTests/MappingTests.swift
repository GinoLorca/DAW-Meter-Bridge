import Foundation
import Testing
@testable import BridgeProtocol
import MeterCore

@Suite("Model mapping")
struct MappingTests {
    @Test func wireTrackMapsToTrackInfoAndBack() {
        let wire = WireTrack(
            id: TrackID(Int64.max), index: 7, name: "BGV L", color: 0x92A7FF, kind: .returnTrack,
            isMuted: true, isSoloed: false, isArmed: nil, isMutedViaSolo: true,
            hasAudioOutput: false, volume: 0.42, volumeText: "-19.4 dB"
        )
        let info = wire.trackInfo
        #expect(info.id == TrackID(Int64.max))
        #expect(info.index == 7)
        #expect(info.name == "BGV L")
        #expect(info.color == RGBColor(red: 0x92, green: 0xA7, blue: 0xFF))
        #expect(info.kind == .returnTrack)
        #expect(info.isMuted)
        #expect(!info.isSoloed)
        #expect(info.isArmed == nil)
        #expect(!info.canArm)
        #expect(info.isMutedViaSolo)
        #expect(!info.hasAudioOutput)
        #expect(info.volume == 0.42)
        #expect(info.volumeText == "-19.4 dB")
        #expect(WireTrack(info) == wire)
    }

    @Test func missingColorMapsToNil() {
        var wire = sampleTrack(TrackID(1))
        wire.color = nil
        #expect(wire.trackInfo.color == nil)
        #expect(WireTrack(wire.trackInfo).color == nil)
    }

    @Test func allKindsRoundTrip() throws {
        for kind in TrackKind.allCases {
            var wire = sampleTrack(TrackID(3))
            wire.kind = kind
            let data = try WireCodec.encode(TrackMessage(gen: 1, item: wire))
            guard case let .track(decoded) = try WireCodec.decodeIncoming(data) else {
                Issue.record("not a track")
                continue
            }
            #expect(decoded.item.kind == kind)
        }
        #expect(try jsonObject(try WireCodec.encode(TrackMessage(gen: 1, item: {
            var t = sampleTrack(TrackID(3))
            t.kind = .returnTrack
            return t
        }())))["item"].flatMap { ($0 as? [String: Any])?["k"] as? String } == "return")
    }

    @Test func surfacesMapToSurfaceUnits() {
        let message = SurfacesMessage(units: [
            WireSurfaceUnit(slot: 3, script: "MackieControlXT", role: "xt", strips: [TrackID(1), nil]),
            WireSurfaceUnit(slot: 4, script: "MackieControl", role: "main", strips: [TrackID(2)]),
            WireSurfaceUnit(slot: 5, script: "MackieControlXT", role: "mystery", strips: []),
            WireSurfaceUnit(slot: 6, script: "MackieControl", role: "mystery", strips: []),
        ])
        let units = message.surfaceUnits
        #expect(units.map(\.slot) == [3, 4, 5, 6])
        #expect(units.map(\.role) == [.extender, .main, .extender, .main])
        #expect(units[0].scriptName == "MackieControlXT")
        #expect(units[0].strips == [TrackID(1), nil])
        #expect(WireSurfaceUnit(units[1]) == message.units[1])
    }

    @Test func volumeCurveFromHello() throws {
        let table = VolumeCurveTable(sampling: .liveApproximation)
        #expect(table.x.count == 101)
        #expect(table.x[85] == 0.85)
        let curve = try #require(HelloMessage(script: "", live: "", session: 1, hz: 30, vc: table).volumeCurve)
        #expect(abs((curve.decibels(atNormalized: 0.85) ?? -99) - 0) < 1e-9)
        #expect(abs(curve.normalized(atDecibels: 6) - 1) < 1e-9)
        #expect(curve.decibels(atNormalized: 0) == nil)
        #expect(HelloMessage(script: "", live: "", session: 1, hz: 30, vc: nil).volumeCurve == nil)
        // Mismatched or all-null arrays don't make a curve.
        #expect(VolumeCurveTable(x: [0, 1], db: [nil]).volumeCurve == nil)
        #expect(VolumeCurveTable(x: [0, 1], db: [nil, nil]).volumeCurve == nil)
    }

    @Test func metersMapToLevels() {
        let levels = [MeterLevel(id: TrackID(9), left: 0.25, right: 1)]
        let message = MetersMessage(seq: 4, levels: levels)
        #expect(message.entries == [WireMeter(id: TrackID(9), left: 0.25, right: 1)])
        #expect(message.levels == levels)
    }
}
