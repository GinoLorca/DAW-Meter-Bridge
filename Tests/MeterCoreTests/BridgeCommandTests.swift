import MeterCore
import Testing

private let targetID = TrackID(140_523_312_345)

/// Every `BridgeCommand` names the track it acts on.
@Suite struct BridgeCommandTests {
    @Test(arguments: [
        BridgeCommand.select(targetID),
        .setMute(targetID, true),
        .setMute(targetID, false),
        .setSolo(targetID, true, exclusive: nil),
        .setSolo(targetID, true, exclusive: true),
        .setSolo(targetID, false, exclusive: false),
        .setArm(targetID, true),
        .setVolume(targetID, 0.8123),
        .endVolumeDrag(targetID, 0.5),
    ])
    func trackIDNamesTheTarget(command: BridgeCommand) {
        #expect(command.trackID == targetID)
    }

    @Test func distinguishesTargets() {
        #expect(BridgeCommand.select(TrackID(1)).trackID == TrackID(1))
        #expect(BridgeCommand.setVolume(TrackID(2), 0.5).trackID == TrackID(2))
        #expect(BridgeCommand.select(TrackID(1)) != .select(TrackID(2)))
    }

    @Test func soloExclusivityIsPartOfIdentity() {
        let plain = BridgeCommand.setSolo(TrackID(1), true, exclusive: nil)
        let additive = BridgeCommand.setSolo(TrackID(1), true, exclusive: false)
        let exclusive = BridgeCommand.setSolo(TrackID(1), true, exclusive: true)
        #expect(Set([plain, additive, exclusive]).count == 3)
    }

    @Test func theEndOfADragIsNotAnotherDragStep() {
        #expect(BridgeCommand.endVolumeDrag(TrackID(1), 0.5) != .setVolume(TrackID(1), 0.5))
    }
}

@Suite struct MeterLevelTests {
    @Test func keepsChannelsSeparate() {
        let level = MeterLevel(id: TrackID(5), left: 0.6123, right: 0.5871)
        #expect(level.id == TrackID(5))
        #expect(level.left == 0.6123)
        #expect(level.right == 0.5871)
    }
}
