/// A run of faders that one strip group covers, in millimetres from the template's left edge.
///
/// The group draws equally spaced meters, so its pitch is the average spacing of the faders and each
/// meter is centred over its fader as closely as equal spacing allows (exactly, when the faders are
/// themselves evenly spaced, as on the UF8).
public struct TemplateSection: Hashable, Sendable {
    /// Group name, e.g. "UF8" or "L9-12".
    public var name: String
    /// Binding of the group this section creates.
    public var binding: StripBinding
    /// Fader centres, left to right, in mm from the template's left edge. Never empty.
    public var faderCentersMillimeters: [Double]
    /// Strip width used when the section has a single fader (it has no pitch of its own).
    public var singleStripWidthMillimeters: Double

    public init(name: String, binding: StripBinding, faderCentersMillimeters: [Double], singleStripWidthMillimeters: Double = SurfaceTemplate.uf8PitchMillimeters) {
        precondition(!faderCentersMillimeters.isEmpty, "A template section needs at least one fader")
        self.name = name
        self.binding = binding
        self.faderCentersMillimeters = faderCentersMillimeters
        self.singleStripWidthMillimeters = singleStripWidthMillimeters
    }

    /// Faders that are evenly spaced: `first + pitch * k`.
    public init(name: String, binding: StripBinding, firstCenterMillimeters: Double, pitchMillimeters: Double, count: Int) {
        self.init(
            name: name,
            binding: binding,
            faderCentersMillimeters: (0..<max(1, count)).map { firstCenterMillimeters + pitchMillimeters * Double($0) },
            singleStripWidthMillimeters: pitchMillimeters
        )
    }

    public var stripCount: Int { faderCentersMillimeters.count }

    /// Meter pitch: average fader spacing, or `singleStripWidthMillimeters` for one fader.
    public var pitchMillimeters: Double {
        guard stripCount > 1, let first = faderCentersMillimeters.first, let last = faderCentersMillimeters.last else {
            return singleStripWidthMillimeters
        }
        return (last - first) / Double(stripCount - 1)
    }

    /// Left edge of the group: first fader centre minus half a pitch.
    public var leftEdgeMillimeters: Double { faderCentersMillimeters[0] - pitchMillimeters / 2 }

    /// Right edge of the group: last fader centre plus half a pitch.
    public var rightEdgeMillimeters: Double { faderCentersMillimeters[stripCount - 1] + pitchMillimeters / 2 }

    public var widthMillimeters: Double { rightEdgeMillimeters - leftEdgeMillimeters }

    /// Largest distance between a fader centre and its equally spaced meter centre.
    /// 0 for evenly spaced faders; about 5 mm if the WING's L1–L8 (two blocks of four) were one section.
    public var maximumCenterErrorMillimeters: Double {
        let first = faderCentersMillimeters[0]
        return faderCentersMillimeters.enumerated().map { k, center in
            abs(center - (first + pitchMillimeters * Double(k)))
        }.max() ?? 0
    }

    /// The same section moved right by `millimeters`.
    public func offset(by millimeters: Double) -> TemplateSection {
        var copy = self
        copy.faderCentersMillimeters = faderCentersMillimeters.map { $0 + millimeters }
        return copy
    }
}

/// A piece of hardware (or a row of them) described in millimetres from its left edge.
public struct SurfaceTemplate: Hashable, Sendable, Identifiable {
    /// Stable identifier, e.g. "ssl.uf8".
    public var id: String
    /// Shown in menus, e.g. "SSL UF8".
    public var name: String
    /// Overall width of the hardware.
    public var widthMillimeters: Double
    /// Groups the template creates, left to right. Empty for units without faders (UC1).
    public var sections: [TemplateSection]
    /// Surface family; copied to profiles built from the template.
    public var surfaceHint: SurfaceHint?
    /// True when the positions are estimates that need on-device calibration (the WING).
    public var isEstimate: Bool

    public init(id: String, name: String, widthMillimeters: Double, sections: [TemplateSection], surfaceHint: SurfaceHint? = nil, isEstimate: Bool = false) {
        self.id = id
        self.name = name
        self.widthMillimeters = widthMillimeters
        self.sections = sections
        self.surfaceHint = surfaceHint
        self.isEstimate = isEstimate
    }

    /// Number of Mackie units the template's `surfaceUnit` bindings use (UF8: 1, WING: 3, UF1: 0).
    public var surfaceUnitCount: Int {
        sections.reduce(0) { count, section in
            if case let .surfaceUnit(index, _) = section.binding { return max(count, index + 1) }
            return count
        }
    }

    /// Several units side by side, left to right, as one template.
    ///
    /// `gapsMillimeters[i]` is the space between unit i and unit i + 1 (missing entries are 0, i.e. butted).
    /// Surface-unit indices are renumbered so a second UF8 binds to unit 1, and repeated section names
    /// get a number ("UF8", "UF8 2").
    public static func row(
        id: String,
        name: String,
        units: [SurfaceTemplate],
        gapsMillimeters: [Double] = [],
        surfaceHint: SurfaceHint? = nil
    ) -> SurfaceTemplate {
        var sections: [TemplateSection] = []
        var x = 0.0
        var unitBase = 0
        var nameCounts: [String: Int] = [:]
        for (i, unit) in units.enumerated() {
            for section in unit.sections {
                var placed = section.offset(by: x)
                if case let .surfaceUnit(index, firstStrip) = section.binding {
                    placed.binding = .surfaceUnit(index: index + unitBase, firstStrip: firstStrip)
                }
                let seen = nameCounts[section.name, default: 0] + 1
                nameCounts[section.name] = seen
                if seen > 1 { placed.name = "\(section.name) \(seen)" }
                sections.append(placed)
            }
            unitBase += unit.surfaceUnitCount
            x += unit.widthMillimeters
            if i < units.count - 1 {
                x += i < gapsMillimeters.count ? gapsMillimeters[i] : 0
            }
        }
        return SurfaceTemplate(
            id: id,
            name: name,
            widthMillimeters: x,
            sections: sections,
            surfaceHint: surfaceHint ?? units.lazy.compactMap(\.surfaceHint).first,
            isEstimate: units.contains { $0.isEstimate }
        )
    }
}
