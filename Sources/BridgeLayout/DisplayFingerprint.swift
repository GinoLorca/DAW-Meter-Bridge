import CoreGraphics

/// Identifies a physical display across reconnects, so a layout follows its display.
///
/// The app fills this from `CGDisplayCreateUUIDFromDisplayID`, `CGDisplayVendorNumber`,
/// `CGDisplayModelNumber`, `CGDisplaySerialNumber`, `NSScreen.localizedName` and the screen's
/// current mode. No single field is reliable on every display (cheap bar panels often report
/// serial 0, and UUIDs can change between Macs), so `match(_:)` grades how sure a match is.
public struct DisplayFingerprint: Hashable, Sendable {
    /// Display UUID as a string, or nil when unavailable.
    public var uuid: String?
    /// EDID vendor number.
    public var vendorID: UInt32
    /// EDID model number.
    public var modelID: UInt32
    /// EDID serial number; 0 means the display reports none.
    public var serialNumber: UInt32
    /// Display name as macOS shows it, e.g. "LG ULTRAWIDE".
    public var name: String
    /// Current mode in device pixels.
    public var pixelSize: CGSize
    /// Current mode in points (`NSScreen.frame.size`).
    public var pointSize: CGSize

    public init(
        uuid: String? = nil,
        vendorID: UInt32 = 0,
        modelID: UInt32 = 0,
        serialNumber: UInt32 = 0,
        name: String,
        pixelSize: CGSize,
        pointSize: CGSize
    ) {
        self.uuid = uuid
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.name = name
        self.pixelSize = pixelSize
        self.pointSize = pointSize
    }

    /// The display's bounds in display-local points (origin at the bottom-left, like AppKit).
    public var bounds: CGRect { CGRect(origin: .zero, size: pointSize) }

    /// Device pixels per point (2 on a Retina mode), or 1 when the sizes are unknown.
    public var backingScale: CGFloat {
        guard pointSize.width > 0, pixelSize.width > 0 else { return 1 }
        return pixelSize.width / pointSize.width
    }

    /// How confidently `other` is the same display as this one.
    ///
    /// Tiers, strongest first: same UUID; same vendor, model and non-zero serial; same vendor,
    /// model, name and size (pixel or point); same name. Empty names never match.
    public func match(_ other: DisplayFingerprint) -> DisplayMatch {
        if let uuid, !uuid.isEmpty, uuid == other.uuid {
            return .uuid
        }
        let sameModel = vendorID == other.vendorID && modelID == other.modelID
        if sameModel, serialNumber != 0, serialNumber == other.serialNumber {
            return .vendorModelSerial
        }
        let sameName = !name.isEmpty && name == other.name
        if sameModel, sameName, hasSameSize(as: other) {
            return .vendorModelNameSize
        }
        if sameName {
            return .name
        }
        return .none
    }

    private func hasSameSize(as other: DisplayFingerprint) -> Bool {
        Self.sizesEqual(pixelSize, other.pixelSize) || Self.sizesEqual(pointSize, other.pointSize)
    }

    private static func sizesEqual(_ a: CGSize, _ b: CGSize) -> Bool {
        guard a.width > 0, a.height > 0 else { return false }
        return abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}

/// Strength of a display fingerprint match. Higher is more certain.
public enum DisplayMatch: Int, Comparable, Sendable, CaseIterable {
    case none = 0
    case name = 1
    case vendorModelNameSize = 2
    case vendorModelSerial = 3
    case uuid = 4

    public var isMatch: Bool { self != .none }

    public static func < (lhs: DisplayMatch, rhs: DisplayMatch) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension DisplayFingerprint: Codable {
    private enum CodingKeys: String, CodingKey {
        case uuid, vendorID = "vendor", modelID = "model", serialNumber = "serial", name, pixelSize = "pixels", pointSize = "points"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid)
        vendorID = try c.decodeIfPresent(UInt32.self, forKey: .vendorID) ?? 0
        modelID = try c.decodeIfPresent(UInt32.self, forKey: .modelID) ?? 0
        serialNumber = try c.decodeIfPresent(UInt32.self, forKey: .serialNumber) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        pixelSize = try c.decodeIfPresent(CodableSize.self, forKey: .pixelSize)?.cgSize ?? .zero
        pointSize = try c.decodeIfPresent(CodableSize.self, forKey: .pointSize)?.cgSize ?? .zero
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(uuid, forKey: .uuid)
        try c.encode(vendorID, forKey: .vendorID)
        try c.encode(modelID, forKey: .modelID)
        try c.encode(serialNumber, forKey: .serialNumber)
        try c.encode(name, forKey: .name)
        try c.encode(CodableSize(pixelSize), forKey: .pixelSize)
        try c.encode(CodableSize(pointSize), forKey: .pointSize)
    }
}
