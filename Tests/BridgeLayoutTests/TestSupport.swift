import BridgeLayout
import CoreGraphics
import Foundation
import MeterCore

// Shared fixtures for the BridgeLayout tests.

func approx(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

func approx(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

func approx(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 1e-6) -> Bool {
    approx(a.minX, b.minX, tolerance) && approx(a.minY, b.minY, tolerance)
        && approx(a.width, b.width, tolerance) && approx(a.height, b.height, tolerance)
}

enum Fixtures {
    /// LG 34" ultrawide at 1x: 3440×1440, about 797 mm wide.
    static let lg = DisplayFingerprint(
        uuid: "6A1B2C3D-LG",
        vendorID: 7789,
        modelID: 30_481,
        serialNumber: 0x0004_A1B2,
        name: "LG ULTRAWIDE",
        pixelSize: CGSize(width: 3440, height: 1440),
        pointSize: CGSize(width: 3440, height: 1440)
    )
    static let lgPointsPerMillimeter = 3440.0 / 797.2

    /// 12.6" 1920×515 bar, about 309.3 mm wide, no serial.
    static let bar = DisplayFingerprint(
        uuid: "BAR-0001",
        vendorID: 0x1E6D,
        modelID: 515,
        serialNumber: 0,
        name: "12.6 Bar",
        pixelSize: CGSize(width: 1920, height: 515),
        pointSize: CGSize(width: 1920, height: 515)
    )
    static let barPointsPerMillimeter = 1920.0 / 309.3

    /// The Brooklyn studio's display.
    static let brooklyn = DisplayFingerprint(
        uuid: "BROOKLYN-27",
        vendorID: 0x10AC,
        modelID: 41_000,
        serialNumber: 12_345,
        name: "DELL U2723QE",
        pixelSize: CGSize(width: 3840, height: 2160),
        pointSize: CGSize(width: 1920, height: 1080)
    )

    /// Tracks with ids 1000, 1001, ... and the main track last.
    static func tracks(_ count: Int) -> [TrackInfo] {
        var result = (0..<count).map { i in
            TrackInfo(id: TrackID(Int64(1000 + i)), index: i, name: "Track \(i + 1)")
        }
        result.append(TrackInfo(id: TrackID(9999), index: count, name: "Main", kind: .main, isArmed: nil))
        return result
    }

    static func id(_ n: Int) -> TrackID { TrackID(Int64(1000 + n)) }

    /// A snapshot with `count` tracks and the given units (strip k of unit u shows track u*8+k+offset).
    static func snapshot(tracks count: Int = 32, unitCount: Int = 0, bankOffset: Int = 0, selected: TrackID? = nil) -> BridgeSnapshot {
        let units = (0..<unitCount).map { u in
            SurfaceUnit(
                slot: u + 1,
                scriptName: u == 0 ? "MackieControl" : "MackieControlXT",
                role: u == 0 ? .main : .extender,
                strips: (0..<8).map { k in
                    let n = bankOffset + u * 8 + k
                    return n < count ? id(n) : nil
                }
            )
        }
        return BridgeSnapshot(tracks: tracks(count), selected: selected, units: units)
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeLayoutTests-\(UUID().uuidString)", isDirectory: true)
    }
}
