import BridgeLayout
import CoreGraphics

/// The layouts created on first launch (no layouts.json) and by `--reset-layout`.
///
/// Both profiles sit along the bottom of the main display, where the LG ultrawide stands right behind
/// the desk, until the user moves the bridge to a bar display and calibrates. The Bronx desk is
/// UF8 | UF1 | UC1 left to right, so its profile uses the Bronx row template: the UF8 group plus the
/// UF1 meter bound to the selected track, with the row centred under the display. Both profiles also
/// have a visible Main meter at the display's right edge (`MainMeter`).
enum DefaultLayouts {
    static let bronxName = "Bronx — UF8"
    static let brooklynName = "Brooklyn — WING"
    /// Height of the meter strip on first launch.
    static let meterHeight: CGFloat = 200
    /// Strip width (per UF8 fader pitch) when the display's physical size is unknown or implausible.
    static let fallbackStripWidth: CGFloat = 70

    /// "Bronx — UF8" (active, the UF8 | UF1 | UC1 row) and "Brooklyn — WING", both on `display`,
    /// `bottomInset` points above its bottom edge (the height of a Dock that is always shown there).
    static func document(on display: ConnectedDisplay, bottomInset: CGFloat = 0) -> LayoutDocument {
        var bronx = profile(named: bronxName, template: .bronxRow, on: display, bottomInset: bottomInset)
        var brooklyn = profile(named: brooklynName, template: .wingMCUPlus2Extenders, on: display, bottomInset: bottomInset)
        let fallback = mainMeterFallback(on: display, bottomInset: bottomInset)
        bronx.addMainMeter(fallback: fallback)
        brooklyn.addMainMeter(fallback: fallback)
        return LayoutDocument(profiles: [bronx, brooklyn], activeProfileID: bronx.id, selectionMode: .automatic)
    }

    /// Where a Main meter goes in a profile without groups: the bottom of `display`, at the first-run height.
    static func mainMeterFallback(on display: ConnectedDisplay, bottomInset: CGFloat = 0) -> MainMeterFallback {
        let height = min(meterHeight, display.fingerprint.pointSize.height)
        let y = min(max(0, bottomInset), max(0, display.fingerprint.pointSize.height - height))
        return MainMeterFallback(display: display.fingerprint, y: y, height: height)
    }

    /// A one-display profile for `template`, centred along the bottom of `display` (raised by
    /// `bottomInset`, e.g. above a Dock that is always shown).
    ///
    /// Strips get their physical size from the display's EDID points-per-mm when that is plausible and
    /// the strips fit; otherwise each UF8 fader pitch gets `fallbackStripWidth` points (shrunk to fit)
    /// and the layout's scale is left unknown until a calibration measures it.
    static func profile(named name: String, template: SurfaceTemplate, on display: ConnectedDisplay, bottomInset: CGFloat = 0) -> LayoutProfile {
        let size = display.fingerprint.pointSize
        let meterY = min(max(0, bottomInset), max(0, size.height - meterHeight))
        let physical = display.pointsPerMillimeter.flatMap { scale in
            fits(template, pointsPerMillimeter: scale, displayWidth: size.width) ? scale : nil
        }
        let scale = physical ?? fallbackScale(for: template, displayWidth: size.width)
        var placement = TemplatePlacement.centered(
            template,
            displaySize: size,
            pointsPerMillimeter: scale,
            meterY: meterY,
            meterHeight: min(meterHeight, size.height)
        )
        // Centring a whole row can push its meters past an edge of a narrow display (the UC1 at the
        // Bronx row's right end has none): shift the row so every strip is on screen, keeping the spacing.
        if let left = template.sections.map(\.leftEdgeMillimeters).min(),
           let right = template.sections.map(\.rightEdgeMillimeters).max() {
            let minX = placement.x(atMillimeters: left)
            let maxX = placement.x(atMillimeters: right)
            if minX < 0 {
                placement.hardwareLeftX -= minX
            } else if maxX > size.width {
                placement.hardwareLeftX -= min(maxX - size.width, minX)
            }
        }
        var profile = TemplateBuilder.profile(named: name, template: template, on: display.fingerprint, placement: placement)
        let grid = PixelGrid(scale: display.backingScale)
        let bounds = display.localBounds
        for index in profile.displays.indices {
            profile.displays[index].pointsPerMillimeter = physical
            profile.displays[index].groups = profile.displays[index].groups.map { group in
                var group = group
                group.frame = grid.snap(group.frame)
                if group.isVisible { group.frame = GroupGeometry.clamp(group.frame, to: bounds) }
                return group
            }
        }
        return profile
    }

    /// Millimetres from the leftmost to the rightmost strip edge of the template's sections.
    static func stripExtentMillimeters(of template: SurfaceTemplate) -> Double {
        guard let left = template.sections.map(\.leftEdgeMillimeters).min(),
              let right = template.sections.map(\.rightEdgeMillimeters).max() else { return 0 }
        return right - left
    }

    private static func fits(_ template: SurfaceTemplate, pointsPerMillimeter scale: Double, displayWidth: CGFloat) -> Bool {
        let stripWidth = SurfaceTemplate.uf8PitchMillimeters * scale
        return stripWidth >= 24 && stripWidth <= 400
            && CGFloat(stripExtentMillimeters(of: template) * scale) <= displayWidth
    }

    private static func fallbackScale(for template: SurfaceTemplate, displayWidth: CGFloat) -> Double {
        let preferred = Double(fallbackStripWidth) / SurfaceTemplate.uf8PitchMillimeters
        let extent = stripExtentMillimeters(of: template)
        guard extent > 0, displayWidth > 0 else { return preferred }
        return min(preferred, Double(displayWidth) * 0.95 / extent)
    }
}
