import CoreGraphics

/// A linear map from millimetres on the hardware to display-local x, solved from two reference points
/// (for example: the user drags one marker over the UF8's fader 1 and another over fader 8).
public struct TwoPointFit: Hashable, Sendable {
    /// Display scale implied by the two points.
    public var pointsPerMillimeter: Double
    /// Display-local x of 0 mm (the hardware's left edge when millimetres are measured from it).
    public var originX: CGFloat

    /// Solves the fit. Returns nil when the points are the same in millimetres, or when the points
    /// would map right-to-left (the second marker left of the first for a fader further right).
    public init?(firstMillimeters: Double, firstX: CGFloat, secondMillimeters: Double, secondX: CGFloat) {
        let dmm = secondMillimeters - firstMillimeters
        guard abs(dmm) > 1e-9 else { return nil }
        let scale = Double(secondX - firstX) / dmm
        guard scale > 0, scale.isFinite else { return nil }
        pointsPerMillimeter = scale
        originX = firstX - CGFloat(firstMillimeters * scale)
    }

    public init(pointsPerMillimeter: Double, originX: CGFloat) {
        self.pointsPerMillimeter = pointsPerMillimeter
        self.originX = originX
    }

    /// Display-local x of `millimeters`.
    public func x(atMillimeters millimeters: Double) -> CGFloat {
        originX + CGFloat(millimeters * pointsPerMillimeter)
    }
}

/// Two-point calibration of a single strip group.
public enum StripCalibration {
    /// Smallest pitch (points) a calibration may produce; closer markers are treated as a mistake.
    public static let minimumPitch: CGFloat = 2

    /// The frame whose first and last strip centres land exactly on `firstCenterX` and `lastCenterX`,
    /// keeping the vertical extent of `frame`. The pitch is `(last - first) / (stripCount - 1)` and is
    /// not rounded, so the strips stay centred over evenly spaced faders.
    ///
    /// With one strip, the strip is centred between the two markers and keeps its width.
    /// Returns nil when the markers are reversed or closer than `minimumPitch` per strip.
    public static func frame(_ frame: CGRect, stripCount: Int, firstCenterX: CGFloat, lastCenterX: CGFloat) -> CGRect? {
        guard stripCount > 1 else {
            let center = (firstCenterX + lastCenterX) / 2
            return CGRect(x: center - frame.width / 2, y: frame.minY, width: frame.width, height: frame.height)
        }
        let pitch = (lastCenterX - firstCenterX) / CGFloat(stripCount - 1)
        guard pitch >= minimumPitch else { return nil }
        return CGRect(
            x: firstCenterX - pitch / 2,
            y: frame.minY,
            width: pitch * CGFloat(stripCount),
            height: frame.height
        )
    }
}

extension StripGroup {
    /// This group with its first and last strip centres moved onto the given display-local x positions.
    /// See `StripCalibration.frame(_:stripCount:firstCenterX:lastCenterX:)`.
    public func calibrated(firstCenterX: CGFloat, lastCenterX: CGFloat) -> StripGroup? {
        guard let newFrame = StripCalibration.frame(frame, stripCount: stripCount, firstCenterX: firstCenterX, lastCenterX: lastCenterX) else {
            return nil
        }
        var copy = self
        copy.frame = newFrame
        return copy
    }
}
