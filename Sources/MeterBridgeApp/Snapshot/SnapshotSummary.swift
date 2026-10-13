import BridgeLayout
import CoreGraphics
import Foundation
import MeterCore
import MeterRendering

/// summary.json written by `--snapshot`: what the bridge showed, per group and strip.
struct SnapshotSummary: Encodable {
    struct Rect: Encodable {
        var x, y, width, height: Double

        init(_ rect: CGRect) {
            x = Double(rect.minX)
            y = Double(rect.minY)
            width = Double(rect.width)
            height = Double(rect.height)
        }
    }

    struct Display: Encodable {
        var name: String
        var isMain: Bool
        var frame: Rect
        var backingScale: Double
        var physicalWidthMM: Double
        var physicalHeightMM: Double
        var pointsPerMM: Double?
    }

    struct Unit: Encodable {
        var slot: Int
        var script: String
        var role: String
        /// Track names on the unit's strips, left to right (nil = empty strip).
        var strips: [String?]
    }

    struct Strip: Encodable {
        var index: Int
        var trackID: Int64?
        var name: String?
        var kind: String?
        /// Displayed bar heights (left, right), 0...1.
        var bar: [Float]
        /// Peak-hold line, 0...1.
        var peak: Float
        /// Peak readout text as drawn.
        var readout: String
        var clipped: Bool
        var volume: Double?
        var volumeText: String?
        var muted: Bool
        var soloed: Bool
        var mutedViaSolo: Bool
        var armed: Bool
        var selected: Bool
        var dim: Double
    }

    struct Group: Encodable {
        var name: String
        var binding: String
        var stripCount: Int
        var display: String
        /// Display-local points, origin bottom-left.
        var frame: Rect
        /// Global AppKit points (the panel frame).
        var globalFrame: Rect
        /// True when the group's own display isn't connected and it is shown on the main display.
        var shownOnStandInDisplay: Bool
        var image: String
        var imagePixels: [Int]
        var strips: [Strip]
    }

    var createdAt: String
    var source: String
    var status: String
    var connection: String
    var warnings: [String]
    var trackCount: Int
    var selectedTrack: String?
    var units: [Unit]
    var activeProfile: String?
    var profiles: [String]
    var layoutsFile: String
    var displays: [Display]
    var groups: [Group]
    var waitedSeconds: Double

    static func describe(_ binding: StripBinding) -> String {
        switch binding {
        case let .surfaceUnit(index, firstStrip): return "surface unit \(index + 1), strips from \(firstStrip + 1)"
        case .selectedTrack: return "selected track"
        case .mainTrack: return "main track"
        case let .trackList(offset): return "track list from \(offset + 1)"
        }
    }

    static func describe(_ connection: ConnectionState) -> String {
        switch connection {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case let .disconnected(reason): return "disconnected: \(reason)"
        }
    }

    static func strip(_ state: StripRenderState, index: Int, calibration: MeterCalibration) -> Strip {
        Strip(
            index: index,
            trackID: state.trackID?.rawValue,
            name: state.isEmpty ? nil : state.name,
            kind: state.isEmpty ? nil : state.kind.rawValue,
            bar: [state.meter.left.bar, state.meter.right.bar],
            peak: max(state.meter.left.peak, state.meter.right.peak),
            readout: BankView.readoutText(for: state.meter.maxSinceReset, calibration: calibration),
            clipped: state.meter.clipped,
            volume: state.isEmpty ? nil : state.volume,
            volumeText: state.isEmpty ? nil : state.volumeText,
            muted: state.focus.isMuted,
            soloed: state.focus.isSoloed,
            mutedViaSolo: state.focus.isMutedViaSolo,
            armed: state.focus.isArmed,
            selected: state.focus.isSelected,
            dim: state.focus.dim
        )
    }
}
