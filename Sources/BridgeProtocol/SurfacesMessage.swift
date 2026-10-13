import MeterCore

/// One `MackieControl` / `MackieControlXT` instance in a `surfaces` message.
public struct WireSurfaceUnit: Codable, Hashable, Sendable {
    /// 1-based Control Surface slot.
    public var slot: Int
    /// Script class name, e.g. "MackieControl".
    public var script: String
    /// `"main"` or `"xt"`.
    public var role: String
    /// Track id on each strip, left to right; `nil` for an empty strip.
    public var strips: [TrackID?]

    public init(slot: Int, script: String, role: String, strips: [TrackID?]) {
        self.slot = slot
        self.script = script
        self.role = role
        self.strips = strips
    }

    /// The wire record for a model unit.
    public init(_ unit: SurfaceUnit) {
        self.init(slot: unit.slot, script: unit.scriptName, role: unit.role.rawValue, strips: unit.strips)
    }

    /// The model unit. An unknown `role` is inferred from the script name ("…XT" = extender).
    public var surfaceUnit: SurfaceUnit {
        let resolvedRole = SurfaceUnit.Role(rawValue: role)
            ?? (script.hasSuffix("XT") ? .extender : .main)
        return SurfaceUnit(slot: slot, scriptName: script, role: resolvedRole, strips: strips)
    }
}

/// `surfaces`: what each hardware strip shows, units in physical left-to-right order.
public struct SurfacesMessage: WireMessage {
    public static let messageType = "surfaces"

    /// Mackie units, left to right. Empty when no Mackie surface is configured.
    public var units: [WireSurfaceUnit]
    /// Human-readable problem when introspection partly failed; always written (`null` when fine).
    public var warn: String?

    public init(units: [WireSurfaceUnit], warn: String? = nil) {
        self.units = units
        self.warn = warn
    }

    /// The units as MeterCore models them.
    public var surfaceUnits: [SurfaceUnit] { units.map(\.surfaceUnit) }

    private enum CodingKeys: String, CodingKey {
        case units
        case warn
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(units, forKey: .units)
        try container.encodeNullable(warn, forKey: .warn)
    }
}
