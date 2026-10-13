import CoreGraphics
import Foundation

/// Display scale helpers.
public enum DisplayMetrics {
    /// Scales a real display can have, in points per millimetre: from a ~54 ppi signage bar at 1x
    /// (about 2.1) to a 283 ppi bar at 1x (about 11.2), with margin.
    public static let plausiblePointsPerMillimeter: ClosedRange<Double> = 1.0...20.0

    /// Points per millimetre from the display's width in points and its physical width in mm
    /// (`CGDisplayScreenSize`, from EDID). Returns nil when the physical size is missing or gives an
    /// implausible scale; cheap bar panels often report wrong sizes, so calibrate when it matters.
    public static func pointsPerMillimeter(pointWidth: CGFloat, physicalWidthMillimeters: Double) -> Double? {
        guard pointWidth > 0, physicalWidthMillimeters > 0, physicalWidthMillimeters.isFinite else { return nil }
        let scale = Double(pointWidth) / physicalWidthMillimeters
        return plausiblePointsPerMillimeter.contains(scale) ? scale : nil
    }
}

/// Where a template's hardware sits on a display.
public struct TemplatePlacement: Hashable, Sendable {
    /// The display's size in points.
    public var displaySize: CGSize
    /// Display scale; from EDID (may be wrong) or a calibration.
    public var pointsPerMillimeter: Double
    /// Display-local x (points) above which the hardware's left edge sits. May be negative or past the
    /// display when the hardware is wider than the display.
    public var hardwareLeftX: CGFloat
    /// Bottom of the meter area, display-local points (origin at the display's bottom).
    public var meterY: CGFloat
    /// Height of the meter area in points.
    public var meterHeight: CGFloat

    public init(displaySize: CGSize, pointsPerMillimeter: Double, hardwareLeftX: CGFloat, meterY: CGFloat, meterHeight: CGFloat) {
        self.displaySize = displaySize
        self.pointsPerMillimeter = pointsPerMillimeter
        self.hardwareLeftX = hardwareLeftX
        self.meterY = meterY
        self.meterHeight = meterHeight
    }

    /// A placement with the hardware centred under the display: a starting point before calibration.
    public static func centered(
        _ template: SurfaceTemplate,
        displaySize: CGSize,
        pointsPerMillimeter: Double,
        meterY: CGFloat = 0,
        meterHeight: CGFloat
    ) -> TemplatePlacement {
        let hardwareWidth = CGFloat(template.widthMillimeters * pointsPerMillimeter)
        return TemplatePlacement(
            displaySize: displaySize,
            pointsPerMillimeter: pointsPerMillimeter,
            hardwareLeftX: (displaySize.width - hardwareWidth) / 2,
            meterY: meterY,
            meterHeight: meterHeight
        )
    }

    /// Display-local x of a point `millimeters` right of the hardware's left edge.
    public func x(atMillimeters millimeters: Double) -> CGFloat {
        hardwareLeftX + CGFloat(millimeters * pointsPerMillimeter)
    }

    /// The same placement with the scale and left edge from a two-point fit, whose millimetres are
    /// measured from the hardware's left edge.
    public func calibrated(with fit: TwoPointFit) -> TemplatePlacement {
        var copy = self
        copy.pointsPerMillimeter = fit.pointsPerMillimeter
        copy.hardwareLeftX = fit.originX
        return copy
    }
}

/// Turns a physical template into strip groups on a display.
public enum TemplateBuilder {
    /// One group per template section, each strip centred over its fader: the frame runs from the
    /// first fader centre minus half a pitch to the last plus half a pitch, at the placement's meter area.
    ///
    /// Groups that land completely off the display are created hidden (`isVisible == false`).
    public static func groups(
        for template: SurfaceTemplate,
        placement: TemplatePlacement,
        makeID: () -> UUID = { UUID() }
    ) -> [StripGroup] {
        let display = CGRect(origin: .zero, size: placement.displaySize)
        return template.sections.map { section in
            let frame = frame(for: section, placement: placement)
            return StripGroup(
                id: makeID(),
                name: section.name,
                binding: section.binding,
                stripCount: section.stripCount,
                frame: frame,
                isVisible: frame.intersects(display),
                physicalPitchMillimeters: section.pitchMillimeters
            )
        }
    }

    /// The display-local frame of one section.
    public static func frame(for section: TemplateSection, placement: TemplatePlacement) -> CGRect {
        let minX = placement.x(atMillimeters: section.leftEdgeMillimeters)
        let maxX = placement.x(atMillimeters: section.rightEdgeMillimeters)
        return CGRect(x: minX, y: placement.meterY, width: maxX - minX, height: placement.meterHeight)
    }

    /// A display layout for `fingerprint` built from the template, recording the placement's scale.
    public static func displayLayout(for template: SurfaceTemplate, on fingerprint: DisplayFingerprint, placement: TemplatePlacement) -> DisplayLayout {
        DisplayLayout(
            fingerprint: fingerprint,
            groups: groups(for: template, placement: placement),
            pointsPerMillimeter: placement.pointsPerMillimeter
        )
    }

    /// A one-display profile built from the template, carrying its surface hint.
    public static func profile(named name: String, template: SurfaceTemplate, on fingerprint: DisplayFingerprint, placement: TemplatePlacement) -> LayoutProfile {
        LayoutProfile(
            name: name,
            displays: [displayLayout(for: template, on: fingerprint, placement: placement)],
            surfaceHint: template.surfaceHint
        )
    }

    /// Moves existing groups horizontally to a new placement (e.g. after a whole-template calibration),
    /// keeping their ids, bindings, visibility and vertical position. Groups are matched to sections by
    /// name; groups without a matching section are returned unchanged.
    public static func refit(_ groups: [StripGroup], to template: SurfaceTemplate, placement: TemplatePlacement) -> [StripGroup] {
        groups.map { group in
            guard let section = template.sections.first(where: { $0.name == group.name }) else { return group }
            let fitted = frame(for: section, placement: placement)
            var copy = group
            copy.frame = CGRect(x: fitted.minX, y: group.frame.minY, width: fitted.width, height: group.frame.height)
            copy.physicalPitchMillimeters = section.pitchMillimeters
            return copy
        }
    }
}
