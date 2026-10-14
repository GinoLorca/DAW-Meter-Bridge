import MeterCore
import MeterRendering

/// App preferences other than layouts. Saved as JSON; missing or unreadable keys fall back to defaults,
/// so settings written by an older or newer build still load.
struct AppSettings: Equatable, Sendable {
    /// Source used last; nil until the first launch picks one.
    var source: SourceKind?
    var style: MeterStyle = .standard
    var ballistics: BallisticsSettings = .standard
    var mixFocus: MixFocusSettings = .standard
    /// Whether the bridge panels are shown (Show/Hide Bridge).
    var isBridgeVisible = true
    /// Mackie units the simulator emulates: 1 = UF8, 3 = WING (MCU + 2 XT).
    var simulatorUnitCount = 1
    /// Live's measured meter curve and clip threshold (docs/ARCHITECTURE.md, open items), used for the
    /// dB readouts and the clip LEDs while the source is Live. Nil until measured: Live's values are then
    /// read as linear amplitude ("≈" readouts) and the clip LED latches at 0.999. The simulator always
    /// uses linear amplitude. Edit settings.json (or the app's defaults) to enter a measured table.
    var liveMeterCalibration: MeterCalibration?
    /// Set once every profile got a Main meter (version 0.2.0 adds one to profiles that have none, once,
    /// so a Main meter the user deletes later stays deleted).
    var addedMainMeters = false

    static let standard = AppSettings()
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case source, style, ballistics, mixFocus, isBridgeVisible = "bridgeVisible", simulatorUnitCount = "simulatorUnits"
        case liveMeterCalibration
        case addedMainMeters = "mainMetersAdded"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.standard
        source = (try? c.decodeIfPresent(SourceKind.self, forKey: .source)) ?? nil
        style = (try? c.decodeIfPresent(MeterStyle.self, forKey: .style)) ?? defaults.style
        ballistics = (try? c.decodeIfPresent(BallisticsSettings.self, forKey: .ballistics)) ?? defaults.ballistics
        mixFocus = (try? c.decodeIfPresent(MixFocusSettings.self, forKey: .mixFocus)) ?? defaults.mixFocus
        isBridgeVisible = (try? c.decodeIfPresent(Bool.self, forKey: .isBridgeVisible)) ?? defaults.isBridgeVisible
        simulatorUnitCount = (try? c.decodeIfPresent(Int.self, forKey: .simulatorUnitCount)) ?? defaults.simulatorUnitCount
        liveMeterCalibration = (try? c.decodeIfPresent(MeterCalibration.self, forKey: .liveMeterCalibration)) ?? nil
        addedMainMeters = (try? c.decodeIfPresent(Bool.self, forKey: .addedMainMeters)) ?? defaults.addedMainMeters
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(style, forKey: .style)
        try c.encode(ballistics, forKey: .ballistics)
        try c.encode(mixFocus, forKey: .mixFocus)
        try c.encode(isBridgeVisible, forKey: .isBridgeVisible)
        try c.encode(simulatorUnitCount, forKey: .simulatorUnitCount)
        try c.encodeIfPresent(liveMeterCalibration, forKey: .liveMeterCalibration)
        try c.encode(addedMainMeters, forKey: .addedMainMeters)
    }
}
