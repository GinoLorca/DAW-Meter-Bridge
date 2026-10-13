import CoreGraphics

/// The part of a strip a point falls on.
public enum StripRegion: Hashable, Sendable {
    /// The peak readout box (click resets peaks).
    case readout
    /// The meter columns and clip LEDs (drag sets volume, double-click resets peaks).
    case meter
    /// The fader rail beside the meter (drag sets volume).
    case fader
    /// The name pill (click selects).
    case name
    /// An S / M / R button.
    case button(StripButton)

    /// Whether a vertical drag on this region changes the volume.
    public var isVolumeArea: Bool {
        switch self {
        case .meter, .fader: return true
        default: return false
        }
    }
}

/// A point resolved to a strip and the part of it under the point.
public struct StripHit: Hashable, Sendable {
    public var strip: Int
    public var region: StripRegion

    public init(strip: Int, region: StripRegion) {
        self.strip = strip
        self.region = region
    }
}

extension BankGeometry {
    /// Index of the strip under `x` (bank coordinates), or nil outside the bank.
    public func stripIndex(atX x: CGFloat) -> Int? {
        guard x >= 0, x < size.width else { return nil }
        return stripFrames.firstIndex { x >= $0.minX && x < $0.maxX }
    }

    /// The strip and region under `point` (bank coordinates). Rows split at the midpoints of the gaps between them,
    /// so there are no dead bands; nil only outside the bank.
    public func hit(at point: CGPoint) -> StripHit? {
        guard point.y >= 0, point.y <= size.height, let index = stripIndex(atX: point.x) else { return nil }
        let frame = stripFrames[index]
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        guard let region = strip(index).region(at: local, bank: self) else { return nil }
        return StripHit(strip: index, region: region)
    }
}

extension StripGeometry {
    /// The region under a strip-local point.
    func region(at point: CGPoint, bank: BankGeometry) -> StripRegion? {
        // Rows top to bottom with their drawn extent. The meter row includes the clip LEDs.
        var rows: [(kind: RowKind, band: Band)] = []
        if let readout = bank.readoutBand { rows.append((.readout, readout)) }
        let meterTop = bank.clipBand?.maxY ?? bank.meterBand.maxY
        rows.append((.meter, Band(minY: bank.meterBand.minY, maxY: meterTop)))
        if let name = bank.nameBand { rows.append((.name, name)) }
        if let buttons = bank.buttonBand { rows.append((.buttons, buttons)) }

        for (k, row) in rows.enumerated() {
            let upper = k == 0 ? CGFloat.infinity : (rows[k - 1].band.minY + row.band.maxY) / 2
            let lower = k == rows.count - 1 ? -CGFloat.infinity : (row.band.minY + rows[k + 1].band.maxY) / 2
            guard point.y >= lower, point.y <= upper else { continue }
            switch row.kind {
            case .readout: return .readout
            case .name: return .name
            case .meter: return isOnRail(point.x) ? .fader : .meter
            case .buttons: return .button(button(atX: point.x))
            }
        }
        return nil
    }

    private enum RowKind { case readout, meter, name, buttons }

    /// True when `x` is closer to the rail than to the meter's right edge (the rail's grab zone is the cap width).
    private func isOnRail(_ x: CGFloat) -> Bool {
        guard let rail else { return false }
        let halfZone = max(capSize.width / 2, (rail.minX - meter.maxX) / 2)
        return abs(x - rail.midX) <= halfZone
    }

    /// The button nearest to `x`, splitting at the midpoints between buttons.
    private func button(atX x: CGFloat) -> StripButton {
        guard buttons.count == 3 else { return .solo }
        if x < (buttons[0].maxX + buttons[1].minX) / 2 { return .solo }
        if x < (buttons[1].maxX + buttons[2].minX) / 2 { return .mute }
        return .arm
    }
}
