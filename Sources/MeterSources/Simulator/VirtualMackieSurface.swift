import MeterCore

/// A virtual Mackie stack like Live's MackieControl plus right-hand XTs: `unitCount` units of
/// 8 strips over the visible tracks. As in MackieControl, one bank step moves by every strip
/// of the stack (8 × units), and strips past the last track are empty.
struct VirtualMackieSurface: Hashable, Sendable {
    static let stripsPerUnit = 8
    /// Live has 7 Control Surface slots, so at most 7 Mackie units.
    static let unitRange = 1...7

    private(set) var unitCount: Int
    /// Visible-track index shown on the first strip of the first unit.
    private(set) var bankOffset = 0

    init(unitCount: Int) {
        self.unitCount = min(max(unitCount, Self.unitRange.lowerBound), Self.unitRange.upperBound)
    }

    var stripCount: Int { unitCount * Self.stripsPerUnit }
    var bankStep: Int { stripCount }

    mutating func setUnitCount(_ count: Int, trackCount: Int) {
        unitCount = min(max(count, Self.unitRange.lowerBound), Self.unitRange.upperBound)
        clampOffset(trackCount: trackCount)
    }

    mutating func bankLeft() {
        bankOffset = max(0, bankOffset - bankStep)
    }

    mutating func bankRight(trackCount: Int) {
        if bankOffset + bankStep < trackCount { bankOffset += bankStep }
    }

    mutating func clampOffset(trackCount: Int) {
        bankOffset = min(bankOffset, max(0, trackCount - 1))
    }

    /// Units in physical left-to-right order: MackieControl in slot 1, XTs in slots 2...n.
    func units(over visibleTracks: [TrackID]) -> [SurfaceUnit] {
        (0..<unitCount).map { unit in
            let strips: [TrackID?] = (0..<Self.stripsPerUnit).map { strip in
                let position = bankOffset + unit * Self.stripsPerUnit + strip
                return visibleTracks.indices.contains(position) ? visibleTracks[position] : nil
            }
            return SurfaceUnit(
                slot: unit + 1,
                scriptName: unit == 0 ? "MackieControl" : "MackieControlXT",
                role: unit == 0 ? .main : .extender,
                strips: strips
            )
        }
    }
}
