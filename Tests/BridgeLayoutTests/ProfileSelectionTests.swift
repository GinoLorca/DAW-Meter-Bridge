import BridgeLayout
import CoreGraphics
import Foundation
import Testing

@Suite struct ProfileSelectionTests {
    let bronx = LayoutProfile(name: "Bronx — UF8", displays: [DisplayLayout(fingerprint: Fixtures.lg)], surfaceHint: .ssl)
    let brooklyn = LayoutProfile(name: "Brooklyn — WING", displays: [DisplayLayout(fingerprint: Fixtures.brooklyn)], surfaceHint: .wing)
    let lgWing = LayoutProfile(name: "LG — WING test", displays: [DisplayLayout(fingerprint: Fixtures.lg)], surfaceHint: .wing)

    @Test func displaysDecideWhenNoSurfaceIsKnown() {
        let profiles = [bronx, brooklyn]
        #expect(ProfileSelector.bestProfile(in: profiles, connectedDisplays: [Fixtures.brooklyn], surfaces: [])?.id == brooklyn.id)
        #expect(ProfileSelector.bestProfile(in: profiles, connectedDisplays: [Fixtures.lg, Fixtures.bar], surfaces: [])?.id == bronx.id)
    }

    @Test func surfaceFamilyComesFirst() {
        let profiles = [bronx, lgWing]
        #expect(ProfileSelector.bestProfile(in: profiles, connectedDisplays: [Fixtures.lg], surfaces: [.wing])?.id == lgWing.id)
        #expect(ProfileSelector.bestProfile(in: profiles, connectedDisplays: [Fixtures.lg], surfaces: [.ssl])?.id == bronx.id)
        // A matching surface beats a matching display.
        #expect(ProfileSelector.bestProfile(in: [bronx, brooklyn], connectedDisplays: [Fixtures.lg], surfaces: [.wing])?.id == brooklyn.id)
    }

    @Test func moreMatchedDisplaysWinThenFewerMissingThenStrongerMatches() {
        let twoDisplays = LayoutProfile(name: "LG + bar", displays: [DisplayLayout(fingerprint: Fixtures.lg), DisplayLayout(fingerprint: Fixtures.bar)])
        let lgOnly = LayoutProfile(name: "LG", displays: [DisplayLayout(fingerprint: Fixtures.lg)])
        #expect(ProfileSelector.bestProfile(in: [lgOnly, twoDisplays], connectedDisplays: [Fixtures.lg, Fixtures.bar], surfaces: [])?.id == twoDisplays.id)
        // With the bar unplugged, the profile that is not missing a display wins.
        #expect(ProfileSelector.bestProfile(in: [twoDisplays, lgOnly], connectedDisplays: [Fixtures.lg], surfaces: [])?.id == lgOnly.id)

        var nameOnly = Fixtures.lg
        nameOnly.uuid = nil
        nameOnly.vendorID = 1
        let weak = LayoutProfile(name: "weak", displays: [DisplayLayout(fingerprint: nameOnly)])
        #expect(ProfileSelector.bestProfile(in: [weak, lgOnly], connectedDisplays: [Fixtures.lg], surfaces: [])?.id == lgOnly.id)
    }

    @Test func tiesPreferTheCurrentProfileThenListOrder() {
        let a = LayoutProfile(name: "A", displays: [DisplayLayout(fingerprint: Fixtures.lg)])
        let b = LayoutProfile(name: "B", displays: [DisplayLayout(fingerprint: Fixtures.lg)])
        #expect(ProfileSelector.bestProfile(in: [a, b], connectedDisplays: [Fixtures.lg], surfaces: [])?.id == a.id)
        #expect(ProfileSelector.bestProfile(in: [a, b], connectedDisplays: [Fixtures.lg], surfaces: [], currentProfileID: b.id)?.id == b.id)
    }

    @Test func somethingIsAlwaysPickedWhenProfilesExist() {
        #expect(ProfileSelector.bestProfile(in: [bronx, brooklyn], connectedDisplays: [Fixtures.bar], surfaces: [])?.id == bronx.id)
        #expect(ProfileSelector.bestProfile(in: [], connectedDisplays: [Fixtures.lg], surfaces: [.ssl]) == nil)
    }

    @Test func matchDetails() {
        let match = ProfileSelector.match(bronx, connectedDisplays: [Fixtures.lg], surfaces: [.wing], currentProfileID: bronx.id)
        #expect(match == ProfileMatch(profileID: bronx.id, surfaceScore: -1, matchedDisplays: 1, unmatchedDisplays: 0, matchStrength: DisplayMatch.uuid.rawValue, isCurrent: true))
        let ranked = ProfileSelector.ranked([bronx, brooklyn], connectedDisplays: [Fixtures.lg], surfaces: [.ssl])
        #expect(ranked.map(\.profileID) == [bronx.id, brooklyn.id])
    }

    @Test func documentRecordsTheAutomaticPick() {
        var document = LayoutDocument(profiles: [bronx, brooklyn])
        let picked = document.selectProfile(connectedDisplays: [Fixtures.brooklyn], surfaces: [.wing])
        #expect(picked?.id == brooklyn.id)
        #expect(document.activeProfileID == brooklyn.id)
        #expect(document.activeProfile?.name == "Brooklyn — WING")
        #expect(document.selectionMode == .automatic)

        document.selectProfile(connectedDisplays: [Fixtures.lg], surfaces: [.ssl])
        #expect(document.activeProfileID == bronx.id)
    }

    @Test func manualChoiceSticksUntilAutomatic() {
        var document = LayoutDocument(profiles: [bronx, brooklyn])
        let chose = document.chooseManually(brooklyn.id)
        #expect(chose)
        #expect(document.selectionMode == .manual)
        #expect(document.selectProfile(connectedDisplays: [Fixtures.lg], surfaces: [.ssl])?.id == brooklyn.id)

        document.chooseAutomatically()
        #expect(document.selectProfile(connectedDisplays: [Fixtures.lg], surfaces: [.ssl])?.id == bronx.id)
        let choseUnknown = document.chooseManually(UUID())
        #expect(!choseUnknown)
        #expect(document.activeProfileID == bronx.id)
    }

    @Test func removingTheManualProfileFallsBackToAutomatic() {
        var document = LayoutDocument(profiles: [bronx, brooklyn])
        document.chooseManually(brooklyn.id)
        document.removeProfile(withID: brooklyn.id)
        #expect(document.activeProfileID == nil)
        #expect(document.selectionMode == .automatic)
        #expect(document.selectProfile(connectedDisplays: [], surfaces: [])?.id == bronx.id)
    }

    @Test func upsertReplacesByID() {
        var document = LayoutDocument(profiles: [bronx])
        var renamed = bronx
        renamed.name = "Bronx — bar"
        document.upsert(renamed)
        document.upsert(brooklyn)
        #expect(document.profiles.map(\.name) == ["Bronx — bar", "Brooklyn — WING"])
    }

    @Test func profileGroupLookupAndUpdate() throws {
        let placement = TemplatePlacement.centered(.bronxRow, displaySize: Fixtures.lg.pointSize, pointsPerMillimeter: Fixtures.lgPointsPerMillimeter, meterHeight: 150)
        var profile = TemplateBuilder.profile(named: "Bronx", template: .bronxRow, on: Fixtures.lg, placement: placement)
        var uf1 = try #require(profile.allGroups.last)
        let location = try #require(profile.location(ofGroup: uf1.id))
        #expect(location.display == 0 && location.group == 1)
        uf1.binding = .mainTrack
        let updated = profile.updateGroup(uf1)
        #expect(updated)
        #expect(profile.group(withID: uf1.id)?.binding == .mainTrack)
        let updatedStranger = profile.updateGroup(StripGroup(name: "stranger", binding: .mainTrack, stripCount: 1, frame: .zero))
        #expect(!updatedStranger)
        #expect(profile.displayIndex(matching: Fixtures.lg) == 0)
        #expect(profile.displayIndex(matching: Fixtures.bar) == nil)
    }

    @Test func surfaceHintsDetectedFromMIDINames() {
        #expect(SurfaceHint.detect(inDeviceNames: ["SSL V-MIDI Port 1", "IAC Driver Bus 1"]) == [.ssl])
        #expect(SurfaceHint.detect(inDeviceNames: ["WING 1", "WING 2"]) == [.wing])
        #expect(SurfaceHint.detect(inDeviceNames: ["UF8 MIDI"]) == [.ssl])
        #expect(SurfaceHint.detect(inDeviceNames: ["Swing Machine", "Network Session 1"]).isEmpty)
    }

    @Test func aWingWinsOverSSL360sVirtualPorts() {
        // SSL 360° (a login item) keeps its V-MIDI ports up even in the WING studio.
        let brooklynPorts = ["SSL V-MIDI Port 1 Source", "SSL V-MIDI Port 1 Destination", "WING 1", "WING 2", "WING 3"]
        #expect(SurfaceHint.detect(inDeviceNames: brooklynPorts) == [.ssl, .wing])
        #expect(SurfaceHint.connectedFamilies(inDeviceNames: brooklynPorts) == [.wing])
        #expect(SurfaceHint.connectedFamilies(inDeviceNames: ["SSL V-MIDI Port 1 Source"]) == [.ssl])
        #expect(SurfaceHint.connectedFamilies(inDeviceNames: []).isEmpty)

        // With the Bronx profile current and both on the same display, the WING profile is picked.
        var brooklynOnLG = brooklyn
        brooklynOnLG.displays = [DisplayLayout(fingerprint: Fixtures.lg)]
        let picked = ProfileSelector.bestProfile(
            in: [bronx, brooklynOnLG],
            connectedDisplays: [Fixtures.lg],
            surfaces: SurfaceHint.connectedFamilies(inDeviceNames: brooklynPorts),
            currentProfileID: bronx.id
        )
        #expect(picked?.id == brooklynOnLG.id)
    }

    @Test func surfaceHintsIgnoreCase() {
        #expect(SurfaceHint(rawValue: " wing ") == .wing)
        let hint: SurfaceHint = "ssl"
        #expect(hint == .ssl)
        #expect(hint.description == "SSL")
    }
}
