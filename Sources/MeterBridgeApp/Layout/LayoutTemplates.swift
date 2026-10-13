import BridgeLayout
import CoreGraphics
import Foundation

/// A template the menus offer under New Profile from Template and Add Strip Group.
struct LayoutTemplate: Identifiable, Sendable {
    var id: String
    /// Menu title.
    var title: String
    var template: SurfaceTemplate
    /// Also offered as a whole new profile (single meters like the UF1 are only offered as groups).
    var offeredAsProfile: Bool
}

/// The templates of the menus, and where their groups go.
enum LayoutTemplates {
    static let uf8 = LayoutTemplate(id: "uf8", title: "SSL UF8", template: .sslUF8, offeredAsProfile: true)
    static let bronxRow = LayoutTemplate(id: "bronx-row", title: "SSL UF8 + UF1 + UC1 Row", template: .bronxRow, offeredAsProfile: true)
    static let wing = LayoutTemplate(id: "wing", title: "Behringer WING (MCU + 2 Extenders)", template: .wingMCUPlus2Extenders, offeredAsProfile: true)
    static let trackList24 = LayoutTemplate(id: "tracks-24", title: "24-Track List (No Surface)", template: trackList24Template, offeredAsProfile: true)
    static let uf1 = LayoutTemplate(id: "uf1", title: "SSL UF1 (Selected Track)", template: .sslUF1, offeredAsProfile: false)
    static let mainMeter = LayoutTemplate(id: "main", title: "Main Track Meter", template: mainMeterTemplate, offeredAsProfile: false)

    /// Every template, in menu order.
    static let all: [LayoutTemplate] = [uf8, bronxRow, wing, trackList24, uf1, mainMeter]
    /// Offered under New Profile from Template.
    static var profileTemplates: [LayoutTemplate] { all.filter(\.offeredAsProfile) }

    /// Rows of hardware whose units the user may add one at a time: adding the UF1 to a profile that has the
    /// UF8 puts its meter where the UF1 sits in this row, measured from the UF8 group.
    static let knownRows: [SurfaceTemplate] = [.bronxRow]

    /// 24 consecutive tracks as three groups of 8 at the UF8's pitch, for setups without a surface
    /// (the simulator, a bare Live set).
    static let trackList24Template: SurfaceTemplate = {
        let pitch = SurfaceTemplate.uf8PitchMillimeters
        let sections = (0..<3).map { block in
            TemplateSection(
                name: "Tracks \(block * 8 + 1)-\(block * 8 + 8)",
                binding: .trackList(offset: block * 8),
                firstCenterMillimeters: pitch / 2 + Double(block * 8) * pitch,
                pitchMillimeters: pitch,
                count: 8
            )
        }
        return SurfaceTemplate(id: "app.tracklist24", name: "24-Track List", widthMillimeters: 24 * pitch, sections: sections)
    }()

    /// One meter on the main track, one UF8 pitch wide.
    static let mainMeterTemplate = SurfaceTemplate(
        id: "app.main",
        name: "Main Track Meter",
        widthMillimeters: SurfaceTemplate.uf8PitchMillimeters,
        sections: [
            TemplateSection(
                name: "Main",
                binding: .mainTrack,
                faderCentersMillimeters: [SurfaceTemplate.uf8PitchMillimeters / 2]
            ),
        ]
    )

    /// A new one-display profile from `template`, along the bottom of `display` (see `DefaultLayouts`).
    static func profile(_ template: LayoutTemplate, named name: String, on display: ConnectedDisplay) -> LayoutProfile {
        DefaultLayouts.profile(named: name, template: template.template, on: display)
    }

    /// The groups `template` adds to `layout` (the profile's layout for `display`, if it has one), and the
    /// points-per-mm they were sized with (nil when guessed).
    ///
    /// - If `layout` has a group for another unit of a known row (the UF8, when adding the UF1), the new
    ///   groups go where the row puts them, measured from that group's strips.
    /// - Otherwise they are centred along the bottom of the display at the layout's scale (from a
    ///   calibration) or the display's EDID scale, and moved up above any groups they would cover.
    static func groups(_ template: LayoutTemplate, on display: ConnectedDisplay, existing layout: DisplayLayout?) -> (groups: [StripGroup], pointsPerMillimeter: Double?) {
        let existing = layout?.groups.filter(\.isVisible) ?? []
        if let anchored = anchoredGroups(template.template, displaySize: display.localBounds.size, existing: existing) {
            return anchored
        }
        var sizing = display
        if let scale = layout?.pointsPerMillimeter { sizing.pointsPerMillimeter = scale }
        let profile = DefaultLayouts.profile(named: template.title, template: template.template, on: sizing)
        let built = profile.displays.first
        var groups = built?.groups ?? []
        let grid = PixelGrid(scale: display.backingScale)
        let frames = EditMath.stackedAbove(groups.map(\.frame), existing: existing.map(\.frame), display: display.localBounds)
        for index in groups.indices {
            groups[index].frame = grid.snap(frames[index])
        }
        return (groups, built?.pointsPerMillimeter)
    }

    /// Groups of `template` placed relative to an existing group of the same hardware row, or nil.
    static func anchoredGroups(_ template: SurfaceTemplate, displaySize: CGSize, existing: [StripGroup]) -> (groups: [StripGroup], pointsPerMillimeter: Double?)? {
        let wanted = Set(template.sections.map(\.name))
        guard !wanted.isEmpty else { return nil }
        for row in knownRows {
            let rowNames = Set(row.sections.map(\.name))
            guard wanted.isSubset(of: rowNames) else { continue }
            for anchorSection in row.sections where !wanted.contains(anchorSection.name) && anchorSection.stripCount >= 2 {
                guard let anchor = existing.first(where: { $0.name == anchorSection.name && $0.stripCount == anchorSection.stripCount }),
                      let first = anchorSection.faderCentersMillimeters.first,
                      let last = anchorSection.faderCentersMillimeters.last,
                      let fit = TwoPointFit(
                        firstMillimeters: first,
                        firstX: anchor.stripCenterX(at: 0),
                        secondMillimeters: last,
                        secondX: anchor.stripCenterX(at: anchor.stripCount - 1)
                      )
                else { continue }
                let placement = TemplatePlacement(
                    displaySize: displaySize,
                    pointsPerMillimeter: fit.pointsPerMillimeter,
                    hardwareLeftX: fit.originX,
                    meterY: anchor.frame.minY,
                    meterHeight: anchor.frame.height
                )
                var subset = row
                subset.sections = row.sections.filter { wanted.contains($0.name) }
                return (TemplateBuilder.groups(for: subset, placement: placement), fit.pointsPerMillimeter)
            }
        }
        return nil
    }
}
