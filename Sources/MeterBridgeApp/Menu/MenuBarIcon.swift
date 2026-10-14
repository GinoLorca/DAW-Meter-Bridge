import AppKit

/// The menu-bar icon: a miniature meter bridge, drawn like the app icon. Never signal bars or a battery.
///
/// Five segmented LED meters stand on a base rail (the "bridge"). Each meter shows its whole column of
/// segments, faint when unlit, so they read as meters of equal height at irregular levels rather than bars
/// of different heights; no outline around them, which is what made an earlier version read as a battery.
/// It is a template image (one colour, macOS tints it), drawn for the backing scale it is shown at, so every
/// segment and gap lands on whole device pixels at 1x and 2x.
///
/// - `shown`: the bridge is shown: meters lit at irregular levels, with peak-hold segments.
/// - `waiting`: shown, but the DAW isn't connected: only each meter's bottom segment is lit.
/// - `hidden`: the bridge is hidden: every segment and the rail unlit.
enum MenuBarIcon {
    enum State: CaseIterable, Sendable {
        case shown
        case waiting
        case hidden
    }

    // Geometry in points: 5 meters 3 pt wide with 2 pt between them, a 12 pt column of segments,
    // 1 pt of air, then a 1 pt rail across the full width. 23 × 14 pt.
    static let meterCount = 5
    static let meterWidth: CGFloat = 3
    static let meterGap: CGFloat = 2
    static let columnHeight: CGFloat = 12
    static let railGap: CGFloat = 1
    static let railHeight: CGFloat = 1
    /// Segments per meter, at every scale.
    static let segments = 6

    /// Lit segments of each meter, left to right: irregular, the loudest off-centre, never a staircase.
    static let litSegments = [3, 5, 2, 6, 4]
    /// Segment index (0 = bottom) of each meter's peak-hold segment, nil = none.
    static let peakSegments: [Int?] = [4, nil, 4, nil, 5]

    static let size = NSSize(
        width: CGFloat(meterCount) * meterWidth + CGFloat(meterCount - 1) * meterGap,
        height: columnHeight + railGap + railHeight
    )

    /// Opacity of unlit segments, and of the rail while the bridge is hidden.
    static let unlitAlpha: CGFloat = 0.3
    static let hiddenRailAlpha: CGFloat = 0.45

    @MainActor private static var cache: [State: NSImage] = [:]

    /// The template image for `state` (cached; it redraws itself for each backing scale).
    @MainActor
    static func image(for state: State) -> NSImage {
        if let image = cache[state] { return image }
        let image = NSImage(size: size, flipped: false) { rect in
            draw(state, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DAW Meter Bridge"
        cache[state] = image
        return image
    }

    /// Segment height and gap in device pixels at `scale`: 1 + 1 px at 1x, 3 + 1 px at 2x and above.
    static func segmentPixels(scale: CGFloat) -> (height: CGFloat, gap: CGFloat) {
        scale >= 2 ? (3, 1) : (1, 1)
    }

    /// Frame of segment `segment` (0 = bottom) of meter `meter`, in icon points, on whole device pixels.
    static func segmentFrame(meter: Int, segment: Int, scale: CGFloat) -> CGRect {
        let (height, gap) = segmentPixels(scale: scale)
        let base = (railHeight + railGap) * scale
        let x = CGFloat(meter) * (meterWidth + meterGap)
        let y = (base + CGFloat(segment) * (height + gap)) / scale
        return CGRect(x: x, y: y, width: meterWidth, height: height / scale)
    }

    /// Whether segment `segment` of meter `meter` is lit in `state`.
    static func isLit(meter: Int, segment: Int, state: State) -> Bool {
        switch state {
        case .shown: return segment < litSegments[meter] || segment == peakSegments[meter]
        case .waiting: return segment == 0
        case .hidden: return false
        }
    }

    /// Draws the icon into `rect` of the current graphics context in black, at the context's device scale.
    static func draw(_ state: State, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        draw(state, in: rect, context: context)
    }

    /// Draws the icon into `rect` of `context`.
    static func draw(_ state: State, in rect: CGRect, context: CGContext) {
        // Device pixels per icon point: the context's scale times the image's drawn size per point.
        let transform = context.userSpaceToDeviceSpaceTransform
        let scale = max(1, (hypot(transform.a, transform.b) * rect.width / size.width).rounded())

        // Draw in the icon's own point grid, whatever size the image is drawn at.
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
        defer { context.restoreGState() }

        let ink = NSColor.black
        context.setFillColor(ink.withAlphaComponent(state == .hidden ? hiddenRailAlpha : 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: railHeight))

        for meter in 0..<meterCount {
            for segment in 0..<segments {
                let lit = isLit(meter: meter, segment: segment, state: state)
                context.setFillColor(ink.withAlphaComponent(lit ? 1 : unlitAlpha).cgColor)
                context.fill(segmentFrame(meter: meter, segment: segment, scale: scale))
            }
        }
    }
}
