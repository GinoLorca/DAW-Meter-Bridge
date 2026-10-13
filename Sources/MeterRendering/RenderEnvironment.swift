import AppKit
import MeterCore

/// What every strip of a bank shares: style, colours, fonts, geometry, LED artwork and calibration.
/// One instance per `BankView`; strips hold a reference so frames copy nothing.
@MainActor
final class RenderEnvironment {
    var style: MeterStyle
    var palette: Palette
    var geometry: BankGeometry
    var fonts: FontSet
    var calibration: MeterCalibration
    /// Artwork for one stereo column and for the full-width mono column.
    var stereoArt: ColumnArt?
    var monoArt: ColumnArt?

    init(style: MeterStyle, geometry: BankGeometry, calibration: MeterCalibration) {
        self.style = style
        self.palette = Palette(style: style)
        self.geometry = geometry
        self.fonts = FontSet(geometry: geometry)
        self.calibration = calibration
    }

    var scale: CGFloat { geometry.scale }

    /// Rebuilds fonts and LED artwork for a new geometry (size, scale, strip count or style changed).
    func setGeometry(_ newGeometry: BankGeometry) {
        geometry = newGeometry
        fonts = FontSet(geometry: newGeometry)
        let heightPx = Int((newGeometry.meterHeight * newGeometry.scale).rounded())
        stereoArt = SegmentArtwork.make(
            widthPx: newGeometry.columnWidthPx, heightPx: heightPx, segments: newGeometry.segments,
            scale: newGeometry.scale, style: style, palette: palette
        )
        monoArt = SegmentArtwork.make(
            widthPx: 2 * newGeometry.columnWidthPx + newGeometry.columnGapPx, heightPx: heightPx,
            segments: newGeometry.segments, scale: newGeometry.scale, style: style, palette: palette
        )
    }

    /// Readout text for a meter value: the calibration's text with "-inf" shown as "-∞".
    func readoutText(for value: Float) -> String {
        BankView.readoutText(for: value, calibration: calibration)
    }
}
