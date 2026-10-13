import BridgeLayout
import CoreGraphics
import Foundation

/// The state of a two-point calibration of one group: marker 1 over the first fader's centre, marker 2
/// over the last fader's centre, in display-local x. A one-strip group has a single marker that centres it.
struct CalibrationModel: Equatable, Sendable {
    /// The group as it was when calibration began.
    var group: StripGroup
    /// Display-local x of each marker (one for a single strip, else two).
    private(set) var markers: [CGFloat]
    /// The marker that arrow keys move.
    var activeMarker = 0

    init(group: StripGroup) {
        self.group = group
        if group.stripCount > 1 {
            markers = [group.stripCenterX(at: 0), group.stripCenterX(at: group.stripCount - 1)]
        } else {
            markers = [group.stripCenterX(at: 0)]
        }
    }

    var firstCenterX: CGFloat { markers[0] }
    var lastCenterX: CGFloat { markers[markers.count - 1] }

    /// Strip number a marker stands for (1-based), for its label.
    func stripNumber(ofMarker index: Int) -> Int {
        index == 0 ? 1 : group.stripCount
    }

    mutating func setMarker(_ index: Int, to x: CGFloat) {
        guard markers.indices.contains(index) else { return }
        markers[index] = x
    }

    /// The group's frame if applied now, or nil when the markers are reversed or too close.
    var previewFrame: CGRect? {
        StripCalibration.frame(group.frame, stripCount: group.stripCount, firstCenterX: firstCenterX, lastCenterX: lastCenterX)
    }

    /// The group as it would be after applying, or nil (see `previewFrame`).
    var calibratedGroup: StripGroup? {
        group.calibrated(firstCenterX: firstCenterX, lastCenterX: lastCenterX)
    }

    /// Strip pitch in points the markers imply (nil for one strip, or when invalid).
    var pitch: CGFloat? {
        guard group.stripCount > 1, previewFrame != nil else { return nil }
        return (lastCenterX - firstCenterX) / CGFloat(group.stripCount - 1)
    }

    /// Points per millimetre the markers imply, when the group's physical pitch is known.
    var pointsPerMillimeter: Double? {
        guard let pitch, let physical = group.physicalPitchMillimeters, physical > 0 else { return nil }
        return Double(pitch) / physical
    }

    /// Index of the marker nearest a display-local x.
    func nearestMarker(to x: CGFloat) -> Int {
        markers.indices.min { abs(markers[$0] - x) < abs(markers[$1] - x) } ?? 0
    }

    /// Strip centres the markers imply, for preview ticks.
    var previewCenters: [CGFloat] {
        guard let frame = previewFrame else { return [] }
        let width = frame.width / CGFloat(max(1, group.stripCount))
        return (0..<group.stripCount).map { frame.minX + (CGFloat($0) + 0.5) * width }
    }
}
