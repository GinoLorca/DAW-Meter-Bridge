import AppKit
import MeterCore
@testable import MeterRendering
import Testing

/// Offscreen renders of a bank: writes PNGs (see `snapshotDirectory()`) and checks a few pixels.
@MainActor
@Suite struct RenderTests {
    /// A 12.6" 1920×515 bar display at 1×, one UF8 bank.
    static let barSize = CGSize(width: 1920, height: 515)
    /// A short strip along the bottom of a Retina ultrawide.
    static let ultrawideSize = CGSize(width: 860, height: 220)

    @Test func writesSnapshotsForInspection() throws {
        let strips = demoSession()
        let bar = try #require(BankView.renderImage(strips: strips, size: Self.barSize, scale: 1))
        #expect(bar.width == 1920 && bar.height == 515)
        #expect(writeSnapshot(bar, scale: 1, name: "bank-bar-1920x515@1x.png") != nil)

        let wide = try #require(BankView.renderImage(strips: strips, size: Self.ultrawideSize, scale: 2))
        #expect(wide.width == 1720 && wide.height == 440)
        writeSnapshot(wide, scale: 2, name: "bank-ultrawide-860x220@2x.png")

        var withEmpty = Array(strips.prefix(6))
        withEmpty.append(.empty)
        withEmpty.append(.empty)
        let edit = try #require(BankView.renderImage(strips: withEmpty, size: Self.ultrawideSize, scale: 2, isEditing: true))
        writeSnapshot(edit, scale: 2, name: "bank-edit-mode@2x.png")

        let narrow = (0..<16).map { i in strips[i % strips.count] }
        let sixteen = try #require(BankView.renderImage(strips: narrow, size: Self.ultrawideSize, scale: 2))
        writeSnapshot(sixteen, scale: 2, name: "bank-16-narrow-strips@2x.png")

        var allRows = MeterStyle()
        allRows.showButtons = false
        allRows.showPeakReadout = false
        let compact = try #require(BankView.renderImage(strips: strips, style: allRows, size: Self.ultrawideSize, scale: 2))
        writeSnapshot(compact, scale: 2, name: "bank-no-buttons-no-readout@2x.png")

        let png = try #require(BankView.renderPNG(strips: strips, size: Self.ultrawideSize, scale: 2))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func litSegmentIsGreenAndUnlitSegmentIsFaint() throws {
        let strip = makeStrip(1, "Kick", meter: makeMeter(left: 0.5, peak: 0.5))
        let image = try #require(BankView.renderImage(strips: [strip], size: CGSize(width: 240, height: 515), scale: 1))
        let reader = PixelReader(image, scale: 1)
        let geometry = BankGeometry(size: CGSize(width: 240, height: 515), stripCount: 1, style: .standard, scale: 1)
        let column = geometry.strip(0).columns[0]

        let low = geometry.segments[5]
        let lit = reader.pixel(at: CGPoint(x: column.midX, y: column.minY + (low.bottom + low.top) / 2))
        #expect(lit.isGreen, "segment 5 at level 0.5 should be lit green, got \(lit)")

        let high = geometry.segments[30]
        let unlit = reader.pixel(at: CGPoint(x: column.midX, y: column.minY + (high.bottom + high.top) / 2))
        #expect(unlit.luminance < lit.luminance * 0.3, "segment 30 should be unlit and faint, got \(unlit)")
        #expect(unlit.luminance > 3, "unlit segments should still be faintly visible, got \(unlit)")

        let gap = reader.pixel(at: CGPoint(x: column.midX, y: column.minY + (low.top + geometry.segments[6].bottom) / 2))
        #expect(gap.luminance < 10, "the gap between segments should be background, got \(gap)")
    }

    @Test func hotMeterLightsTopSegmentRedAndClipLED() throws {
        var meter = makeMeter(left: 0.99, right: 0.5, clipped: true)
        meter.right.peak = 0.5
        let strip = makeStrip(1, "Kick", meter: meter)
        let size = CGSize(width: 240, height: 515)
        let image = try #require(BankView.renderImage(strips: [strip], size: size, scale: 1))
        let reader = PixelReader(image, scale: 1)
        let geometry = BankGeometry(size: size, stripCount: 1, style: .standard, scale: 1)
        let strip0 = geometry.strip(0)
        let left = strip0.columns[0]
        let right = strip0.columns[1]

        let top = geometry.segments[39]
        let hot = reader.pixel(at: CGPoint(x: left.midX, y: left.minY + (top.bottom + top.top) / 2))
        #expect(hot.isRed, "top segment of a hot meter should be red, got \(hot)")

        let yellow = geometry.segments[34]
        let warm = reader.pixel(at: CGPoint(x: left.midX, y: left.minY + (yellow.bottom + yellow.top) / 2))
        #expect(warm.isYellow, "segment 34 should be yellow, got \(warm)")

        let quietTop = reader.pixel(at: CGPoint(x: right.midX, y: right.minY + (top.bottom + top.top) / 2))
        #expect(!quietTop.isRed && quietTop.luminance < 60, "the quiet right column's top should be unlit, got \(quietTop)")

        let clip = try #require(strip0.clipLEDs.first)
        let led = reader.pixel(at: CGPoint(x: clip.midX, y: clip.midY))
        #expect(led.isRed, "clip LED should be lit, got \(led)")
    }

    @Test func dimmedStripIsDarker() throws {
        let size = CGSize(width: 480, height: 515)
        let meter = makeMeter(left: 0.6, peak: 0.6)
        let normal = makeStrip(1, "A", color: 0x10A4EE, meter: meter)
        var dimmed = makeStrip(2, "B", color: 0x10A4EE, meter: meter)
        dimmed.focus.dim = 0.6
        let image = try #require(BankView.renderImage(strips: [normal, dimmed], size: size, scale: 1))
        let reader = PixelReader(image, scale: 1)
        let geometry = BankGeometry(size: size, stripCount: 2, style: .standard, scale: 1)
        let segment = geometry.segments[8]

        func segmentPixel(_ index: Int) -> Pixel {
            let column = geometry.strip(index).columns[0]
            let origin = geometry.stripFrames[index].origin
            return reader.pixel(at: CGPoint(x: origin.x + column.midX, y: column.minY + (segment.bottom + segment.top) / 2))
        }
        func pillPixel(_ index: Int) -> Pixel {
            let pill = try! #require(geometry.strip(index).name)
            let origin = geometry.stripFrames[index].origin
            return reader.pixel(at: CGPoint(x: origin.x + pill.minX + pill.height * 0.3, y: pill.midY))
        }

        let bright = segmentPixel(0)
        let dark = segmentPixel(1)
        #expect(bright.isGreen)
        #expect(dark.luminance < bright.luminance * 0.55, "dimmed segment \(dark) should be much darker than \(bright)")
        #expect(pillPixel(1).luminance < pillPixel(0).luminance * 0.55, "the name pill dims too")
    }

    @Test func emptyStripDrawsOnlyAFaintOutline() throws {
        let size = CGSize(width: 240, height: 515)
        let image = try #require(BankView.renderImage(strips: [.empty], size: size, scale: 1))
        let reader = PixelReader(image, scale: 1)
        let geometry = BankGeometry(size: size, stripCount: 1, style: .standard, scale: 1)
        let strip = geometry.strip(0)

        let inside = reader.pixels(in: strip.outline.insetBy(dx: 4, dy: 4))
        #expect(inside.allSatisfy { $0.luminance < 2 }, "nothing is drawn inside an empty strip")
        let edge = reader.pixel(at: CGPoint(x: strip.outline.minX + 0.5, y: strip.outline.midY))
        #expect(edge.luminance > 20 && edge.luminance < 120, "the outline is faint but visible, got \(edge)")
    }

    @Test func readoutTurnsRedWhenHotAndStaysNeutralWhenQuiet() throws {
        let size = CGSize(width: 480, height: 515)
        let quiet = makeStrip(1, "Quiet", meter: makeMeter(left: 0.5, maxSinceReset: 0.5))
        let hot = makeStrip(2, "Hot", meter: makeMeter(left: 0.95, maxSinceReset: 0.97))
        let image = try #require(BankView.renderImage(strips: [quiet, hot], size: size, scale: 1))
        let reader = PixelReader(image, scale: 1)
        let geometry = BankGeometry(size: size, stripCount: 2, style: .standard, scale: 1)

        func readoutPixels(_ index: Int) throws -> [Pixel] {
            let box = try #require(geometry.strip(index).readout)
            return reader.pixels(in: box.offsetBy(dx: geometry.stripFrames[index].minX, dy: 0))
        }
        let quietPixels = try readoutPixels(0)
        #expect(!quietPixels.contains { $0.isRed })
        #expect(quietPixels.contains { $0.luminance > 150 && abs($0.r - $0.b) < 20 }, "quiet readout is light grey")
        let hotPixels = try readoutPixels(1)
        #expect(hotPixels.contains { $0.isRed }, "hot readout is red")
    }

    @Test func selectedStripHasBrightOutline() throws {
        let size = CGSize(width: 480, height: 515)
        let plain = makeStrip(1, "A", color: 0x10A4EE)
        let selected = makeStrip(2, "B", color: 0x10A4EE, focus: StripFocus(isSelected: true))
        let image = try #require(BankView.renderImage(strips: [plain, selected], size: size, scale: 1))
        let reader = PixelReader(image, scale: 1)
        let geometry = BankGeometry(size: size, stripCount: 2, style: .standard, scale: 1)

        func edgePixel(_ index: Int) -> Pixel {
            let outline = geometry.strip(index).outline
            return reader.pixel(at: CGPoint(x: geometry.stripFrames[index].minX + outline.minX + 0.5, y: outline.midY))
        }
        #expect(edgePixel(1).luminance > 200, "selected strip has a bright outline, got \(edgePixel(1))")
        #expect(edgePixel(0).luminance < 40, "unselected strip has none, got \(edgePixel(0))")
    }
}

/// Frame cost: per-frame updates leave unchanged text alone and stay cheap with 24 strips.
@MainActor
@Suite struct FrameCostTests {
    private func session(count: Int, level: Float, maxSinceReset: Float) -> [StripRenderState] {
        (0..<count).map { i in
            makeStrip(Int64(i + 1), "Track \(i + 1)", color: 0x10A4EE,
                      meter: makeMeter(left: level, right: level * 0.9, maxSinceReset: maxSinceReset))
        }
    }

    @Test func framesOnlyRewriteTextThatChanged() {
        let view = BankView(frame: CGRect(x: 0, y: 0, width: 2580, height: 220), stripCount: 24)
        view.fixedScale = 2
        view.update(strips: session(count: 24, level: 0.5, maxSinceReset: 0.6))
        let afterFirst = view.textWriteCount
        #expect(afterFirst == 48, "one name and one readout per strip")

        // Levels move every frame but the readout value and names do not: no text writes.
        for frame in 0..<120 {
            let level = 0.3 + 0.3 * Float(frame % 10) / 10
            view.update(strips: session(count: 24, level: level, maxSinceReset: 0.6))
        }
        #expect(view.textWriteCount == afterFirst)

        // A new maximum rewrites only the readouts.
        view.update(strips: session(count: 24, level: 0.5, maxSinceReset: 0.7))
        #expect(view.textWriteCount == afterFirst + 24)
    }

    @Test func twentyFourStripFramesAreCheap() {
        let view = BankView(frame: CGRect(x: 0, y: 0, width: 2580, height: 220), stripCount: 24)
        view.fixedScale = 2
        let frames = (0..<20).map { k in session(count: 24, level: 0.2 + 0.035 * Float(k), maxSinceReset: 0.95) }
        view.update(strips: frames[0])
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for i in 0..<600 { view.update(strips: frames[i % frames.count]) }
        }
        let perFrame = elapsed / 600
        // Generous bound (debug build, shared CI machine); a 120 Hz frame is 8.3 ms.
        #expect(perFrame < .milliseconds(2), "update(strips:) took \(perFrame) per frame")
        print("BankView.update(strips:) with 24 strips: \(perFrame) per frame")
    }
}
