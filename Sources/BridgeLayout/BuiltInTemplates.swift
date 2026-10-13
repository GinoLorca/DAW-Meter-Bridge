// Hardware measurements from docs/research/03-physical-layouts-and-displays.md.

extension SurfaceTemplate {
    /// UF8 fader centre-to-centre pitch, measured from SSL's to-scale drawing (about ±0.3 mm).
    public static let uf8PitchMillimeters = 38.5

    /// SSL UF8: 431 mm wide, 8 faders 38.5 mm apart, fader 1 centre 84.3 mm from the left edge.
    /// One group of 8 bound to surface unit 0.
    public static let sslUF8 = SurfaceTemplate(
        id: "ssl.uf8",
        name: "SSL UF8",
        widthMillimeters: 431.0,
        sections: [
            TemplateSection(
                name: "UF8",
                binding: .surfaceUnit(index: 0, firstStrip: 0),
                firstCenterMillimeters: 84.3,
                pitchMillimeters: uf8PitchMillimeters,
                count: 8
            ),
        ],
        surfaceHint: .ssl
    )

    /// SSL UF1: 205 mm wide, one fader 45.0 mm from the left edge.
    ///
    /// The UF1 fader is not part of the UF8 bank (it follows its own channel, the selection, or the
    /// master), so its meter is bound to the selected track by default; the user can rebind it to
    /// `mainTrack`. The meter is one UF8 pitch wide.
    public static let sslUF1 = SurfaceTemplate(
        id: "ssl.uf1",
        name: "SSL UF1",
        widthMillimeters: 205.0,
        sections: [
            TemplateSection(
                name: "UF1",
                binding: .selectedTrack,
                faderCentersMillimeters: [45.0],
                singleStripWidthMillimeters: uf8PitchMillimeters
            ),
        ],
        surfaceHint: .ssl
    )

    /// SSL UC1: 300 mm wide, no faders. Only takes up space in a row.
    public static let sslUC1 = SurfaceTemplate(
        id: "ssl.uc1",
        name: "SSL UC1",
        widthMillimeters: 300.0,
        sections: [],
        surfaceHint: .ssl
    )

    /// Fader centres of the Behringer WING (870 mm wide) in mm from the console's left edge, L1–L12, C1–C8, R1–R4.
    ///
    /// ESTIMATES: measured from the manual's Figure 9, an undimensioned illustration (within-group
    /// pitch ≈23.3–23.8 mm, ≈34.5 mm across a group of four, ≈62 mm L12→C1, ≈186 mm C8→R1).
    /// Calibrate on the real console before trusting them.
    public static let wingFaderCentersMillimeters: [String: Double] = [
        "L1": 61.6, "L2": 84.9, "L3": 108.8, "L4": 132.1, "L5": 166.5, "L6": 189.9, "L7": 213.2, "L8": 236.5,
        "L9": 271.0, "L10": 294.3, "L11": 317.6, "L12": 341.5,
        "C1": 403.3, "C2": 426.6, "C3": 450.2, "C4": 473.8, "C5": 507.8, "C6": 531.3, "C7": 554.9, "C8": 578.2,
        "R1": 763.8, "R2": 787.1, "R3": 810.4, "R4": 834.0,
    ]

    /// Behringer WING in SETUP → DAW → CONFIGURATION "MCU + 2x EXTENDER" (Ableton: Mackie Control on
    /// WING 1, Mackie ControlXT on WING 2 and WING 3).
    ///
    /// Six groups, one per block of four faders (the WING's faders come in fours, one LCD each, with a
    /// wider gap between blocks), mapped onto the three 8-strip units:
    /// L1-4 = unit 0 strips 0–3, L5-8 = unit 0 strips 4–7, L9-12 = unit 1 strips 0–3,
    /// C1-4 = unit 1 strips 4–7, C5-8 = unit 2 strips 0–3, R1-4 = unit 2 strips 4–7.
    /// Each group's equally spaced meters sit within about 0.4 mm of their faders; one 8-strip L1-8
    /// group would be up to about 5 mm off at L4 and L5, which calibration can't fix.
    ///
    /// All positions are ESTIMATES (see `wingFaderCentersMillimeters`).
    public static let wingMCUPlus2Extenders: SurfaceTemplate = {
        func section(_ name: String, _ faders: [String], unit: Int, firstStrip: Int) -> TemplateSection {
            TemplateSection(
                name: name,
                binding: .surfaceUnit(index: unit, firstStrip: firstStrip),
                faderCentersMillimeters: faders.map { wingFaderCentersMillimeters[$0]! }
            )
        }
        return SurfaceTemplate(
            id: "behringer.wing.mcu+2xt",
            name: "Behringer WING (MCU + 2x Extender)",
            widthMillimeters: 870.0,
            sections: [
                section("L1-4", ["L1", "L2", "L3", "L4"], unit: 0, firstStrip: 0),
                section("L5-8", ["L5", "L6", "L7", "L8"], unit: 0, firstStrip: 4),
                section("L9-12", ["L9", "L10", "L11", "L12"], unit: 1, firstStrip: 0),
                section("C1-4", ["C1", "C2", "C3", "C4"], unit: 1, firstStrip: 4),
                section("C5-8", ["C5", "C6", "C7", "C8"], unit: 2, firstStrip: 0),
                section("R1-4", ["R1", "R2", "R3", "R4"], unit: 2, firstStrip: 4),
            ],
            surfaceHint: .wing,
            isEstimate: true
        )
    }()

    /// The Bronx studio row, left to right: UF8 | UF1 | UC1, butted together (936 mm).
    /// Two groups: "UF8" (surface unit 0) and "UF1" (selected track).
    public static let bronxRow = SurfaceTemplate.row(
        id: "bronx.uf8-uf1-uc1",
        name: "Bronx: UF8 | UF1 | UC1",
        units: [.sslUF8, .sslUF1, .sslUC1],
        surfaceHint: .ssl
    )

    /// Templates offered in the app's menus.
    public static let builtIn: [SurfaceTemplate] = [.bronxRow, .sslUF8, .sslUF1, .wingMCUPlus2Extenders]
}
