import CoreGraphics
import MeterCore
@testable import MeterRendering
import Testing

/// Layout math: strip frames, rows, pixel alignment, scaling and hit regions.
@Suite struct GeometryTests {
    static let bar = BankGeometry(size: CGSize(width: 1920, height: 515), stripCount: 8, style: .standard, scale: 1)
    static let retina = BankGeometry(size: CGSize(width: 860, height: 220), stripCount: 8, style: .standard, scale: 2)

    @Test func stripsTileTheWidthEvenly() {
        for geometry in [Self.bar, Self.retina] {
            #expect(geometry.stripFrames.count == 8)
            #expect(geometry.stripFrames.first?.minX == 0)
            #expect(geometry.stripFrames.last?.maxX == geometry.size.width)
            for (a, b) in zip(geometry.stripFrames, geometry.stripFrames.dropFirst()) {
                #expect(a.maxX == b.minX)
            }
            let widths = geometry.stripFrames.map(\.width)
            #expect(widths.max()! - widths.min()! <= 1 / geometry.scale + 1e-9)
        }
    }

    @Test func oddWidthStripsStayOnThePixelGrid() {
        let geometry = BankGeometry(size: CGSize(width: 1001, height: 300), stripCount: 7, style: .standard, scale: 2)
        for frame in geometry.stripFrames {
            #expect(isOnGrid(frame.minX, scale: 2) && isOnGrid(frame.maxX, scale: 2))
        }
        let strip = geometry.strip(3)
        for rect in strip.columns + [strip.monoColumn] + strip.buttons + [strip.name!, strip.readout!, strip.rail!] {
            #expect(isOnGrid(rect.minX, scale: 2) && isOnGrid(rect.maxX, scale: 2))
            #expect(isOnGrid(rect.minY, scale: 2) && isOnGrid(rect.maxY, scale: 2))
        }
    }

    @Test func rowsStackTopToBottomWithoutOverlap() throws {
        for geometry in [Self.bar, Self.retina] {
            let readout = try #require(geometry.readoutBand)
            let clip = try #require(geometry.clipBand)
            let name = try #require(geometry.nameBand)
            let buttons = try #require(geometry.buttonBand)
            #expect(readout.maxY <= geometry.size.height)
            #expect(clip.maxY <= readout.minY)
            #expect(geometry.meterBand.maxY <= clip.minY)
            #expect(name.maxY <= geometry.meterBand.minY)
            #expect(buttons.maxY <= name.minY)
            #expect(buttons.minY >= 0)
            #expect(geometry.meterHeight > geometry.size.height * 0.6, "the meter gets most of the height")
        }
    }

    @Test func segmentsFillTheMeterOnThePixelGrid() {
        for geometry in [Self.bar, Self.retina] {
            let segments = geometry.segments
            #expect(segments.count == 40)
            #expect(segments.first?.bottom == 0)
            #expect(abs(segments.last!.top - geometry.meterHeight) < 1e-9)
            for (a, b) in zip(segments, segments.dropFirst()) {
                #expect(b.bottom - a.top >= 1 / geometry.scale - 1e-9, "at least one pixel of gap")
                #expect(a.height > 0)
            }
            for span in segments {
                #expect(isOnGrid(span.bottom, scale: geometry.scale) && isOnGrid(span.top, scale: geometry.scale))
            }
            let heights = segments.map(\.height)
            #expect(heights.max()! - heights.min()! <= 1 / geometry.scale + 1e-9, "segments differ by at most a pixel")
        }
    }

    @Test func litHeightTracksSegments() {
        let geometry = Self.bar
        #expect(geometry.litHeight(segments: 0) == 0)
        #expect(geometry.litHeight(segments: 1) == geometry.segments[0].top)
        #expect(geometry.litHeight(segments: 40) == geometry.meterHeight)
        #expect(geometry.litHeight(segments: 99) == geometry.meterHeight)
    }

    @Test func sizesAndFontsScaleWithTheView() {
        let small = BankGeometry(size: CGSize(width: 860, height: 220), stripCount: 8, style: .standard, scale: 2)
        let large = BankGeometry(size: CGSize(width: 1920, height: 515), stripCount: 8, style: .standard, scale: 1)
        #expect(large.unit > small.unit * 2)
        #expect(large.readoutFontSize > small.readoutFontSize)
        #expect(large.nameFontSize > small.nameFontSize)
        #expect(large.columnWidth > small.columnWidth)
    }

    @Test func nameFontRespectsStyleBounds() {
        var style = MeterStyle()
        style.minNameFontSize = 11
        style.maxNameFontSize = 13
        let tiny = BankGeometry(size: CGSize(width: 400, height: 100), stripCount: 8, style: style, scale: 2)
        let huge = BankGeometry(size: CGSize(width: 4000, height: 1000), stripCount: 4, style: style, scale: 1)
        #expect(tiny.nameFontSize == 11)
        #expect(huge.nameFontSize == 13)
    }

    @Test func meterIsCentredOnTheStripCentre() {
        // The strip centre is what lines up with the physical fader.
        for index in 0..<8 {
            let strip = Self.bar.strip(index)
            #expect(abs(strip.meter.midX - strip.centerX) <= 0.5)
            #expect(abs(strip.centerX - strip.bounds.width / 2) <= 0.5)
            #expect(strip.rail!.minX > strip.meter.maxX)
            #expect(strip.rail!.midX + strip.capSize.width / 2 <= strip.bounds.width)
        }
    }

    @Test func hiddenRowsGiveTheMeterMoreRoom() {
        var style = MeterStyle()
        style.showNames = false
        style.showButtons = false
        style.showPeakReadout = false
        style.showClipIndicators = false
        style.showFaderMarker = false
        let geometry = BankGeometry(size: CGSize(width: 1920, height: 515), stripCount: 8, style: style, scale: 1)
        #expect(geometry.readoutBand == nil && geometry.nameBand == nil && geometry.buttonBand == nil && geometry.clipBand == nil)
        #expect(geometry.meterHeight > Self.bar.meterHeight + 100)
        let strip = geometry.strip(0)
        #expect(strip.rail == nil && strip.name == nil && strip.buttons.isEmpty && strip.readout == nil)
        #expect(geometry.hit(at: CGPoint(x: 120, y: 10)) == StripHit(strip: 0, region: .meter))
    }

    @Test func zeroStripsAndZeroSizeDoNotCrash() {
        let none = BankGeometry(size: CGSize(width: 800, height: 200), stripCount: 0, style: .standard, scale: 2)
        #expect(none.stripFrames.isEmpty)
        #expect(none.hit(at: CGPoint(x: 10, y: 10)) == nil)
        let flat = BankGeometry(size: .zero, stripCount: 8, style: .standard, scale: 2)
        #expect(flat.stripFrames.count == 8)
        _ = flat.strip(0).capRect(volume: 0.5)
    }

    private func isOnGrid(_ value: CGFloat, scale: CGFloat) -> Bool {
        abs((value * scale).rounded() - value * scale) < 1e-6
    }
}

/// Mapping points to strips and regions.
@Suite struct HitTestingTests {
    static let geometry = GeometryTests.bar

    private func point(strip index: Int, _ local: CGPoint) -> CGPoint {
        CGPoint(x: Self.geometry.stripFrames[index].minX + local.x, y: local.y)
    }

    @Test func eachRowMapsToItsRegion() throws {
        let g = Self.geometry
        for index in [0, 3, 7] {
            let strip = g.strip(index)
            let readout = try #require(strip.readout)
            let name = try #require(strip.name)
            let rail = try #require(strip.rail)
            #expect(g.hit(at: point(strip: index, CGPoint(x: readout.midX, y: readout.midY))) == StripHit(strip: index, region: .readout))
            #expect(g.hit(at: point(strip: index, CGPoint(x: strip.meter.midX, y: strip.meter.midY))) == StripHit(strip: index, region: .meter))
            #expect(g.hit(at: point(strip: index, CGPoint(x: rail.midX, y: strip.meter.midY))) == StripHit(strip: index, region: .fader))
            #expect(g.hit(at: point(strip: index, CGPoint(x: name.midX, y: name.midY))) == StripHit(strip: index, region: .name))
            for (k, button) in StripButton.allCases.enumerated() {
                let rect = strip.buttons[k]
                #expect(g.hit(at: point(strip: index, CGPoint(x: rect.midX, y: rect.midY))) == StripHit(strip: index, region: .button(button)))
            }
        }
    }

    @Test func clipLEDsCountAsMeter() throws {
        let strip = Self.geometry.strip(2)
        let clip = try #require(strip.clipLEDs.first)
        #expect(Self.geometry.hit(at: point(strip: 2, CGPoint(x: clip.midX, y: clip.midY)))?.region == .meter)
    }

    @Test func gapsSplitAtTheirMidpoint() throws {
        let g = Self.geometry
        let name = try #require(g.nameBand)
        let justBelowMeter = g.meterBand.minY - 1
        let justAboveName = name.maxY + 1
        #expect(g.hit(at: CGPoint(x: 100, y: justBelowMeter))?.region == .meter)
        #expect(g.hit(at: CGPoint(x: 100, y: justAboveName))?.region == .name)
    }

    @Test func edgesOfTheBankStillHit() {
        let g = Self.geometry
        #expect(g.hit(at: CGPoint(x: 0, y: 0))?.strip == 0)
        #expect(g.hit(at: CGPoint(x: 1919.5, y: 514))?.strip == 7)
        #expect(g.hit(at: CGPoint(x: 1919.5, y: 514))?.region == .readout)
        #expect(g.hit(at: CGPoint(x: 239.9, y: 300))?.strip == 0)
        #expect(g.hit(at: CGPoint(x: 240, y: 300))?.strip == 1)
    }

    @Test func outsideTheBankMissesEverything() {
        let g = Self.geometry
        #expect(g.hit(at: CGPoint(x: -1, y: 100)) == nil)
        #expect(g.hit(at: CGPoint(x: 1920, y: 100)) == nil)
        #expect(g.hit(at: CGPoint(x: 100, y: -1)) == nil)
        #expect(g.hit(at: CGPoint(x: 100, y: 516)) == nil)
    }

    @Test func buttonRowSplitsBetweenButtons() {
        let g = Self.geometry
        let strip = g.strip(0)
        let y = strip.buttons[0].midY
        #expect(g.hit(at: CGPoint(x: 1, y: y))?.region == .button(.solo))
        #expect(g.hit(at: CGPoint(x: strip.buttons[1].midX, y: y))?.region == .button(.mute))
        #expect(g.hit(at: CGPoint(x: strip.bounds.maxX - 1, y: y))?.region == .button(.arm))
    }
}
