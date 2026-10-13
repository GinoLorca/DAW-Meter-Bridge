import AppKit
import MeterCore

/// A bank of meter strips spread evenly across the view: peak readout, clip LEDs, stereo LED meter with
/// peak hold, fader rail, name pill and S/M/R buttons per strip.
///
/// The view hosts its own Core Animation tree. Call `update(strips:)` on every display frame; it only mutates
/// layers whose drawn value changed, with implicit animations disabled. Geometry, fonts and LED artwork are
/// rebuilt only when the size, backing scale, strip count or style change.
@MainActor
public final class BankView: NSView {
    /// Receives clicks, button presses, volume drags and context-menu requests.
    public weak var delegate: (any BankViewDelegate)?

    /// Number of strips shown, evenly across the width. Missing states in `update(strips:)` draw as empty strips.
    public var stripCount: Int {
        didSet {
            if stripCount < 0 { stripCount = 0 }
            if stripCount != oldValue { rebuildStrips() }
        }
    }

    /// Look of the meters.
    public var style: MeterStyle {
        didSet {
            guard style != oldValue else { return }
            env.style = style
            env.palette = Palette(style: style)
            setNeedsRebuild()
        }
    }

    /// Converts meter values to the dB readout text.
    public var calibration: MeterCalibration {
        didSet {
            guard calibration != oldValue else { return }
            env.calibration = calibration
            stripLayers.forEach { $0.invalidateReadout() }
            redraw()
        }
    }

    /// Edit mode: draws strip centre guides and numbers, and passes mouse events up the responder chain
    /// instead of acting on them, so the app can move and resize the bank.
    public var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            cancelPress()
            withoutActions { editGuides.container.isHidden = !isEditing }
        }
    }

    /// Text for the overlay shown while dragging a volume, e.g. `curve.text(atNormalized:)`.
    /// When nil the overlay shows the strip's `volumeText` before the value moves, then a percentage.
    public var volumeTextProvider: ((Double) -> String)?

    /// The states last passed to `update(strips:)`.
    public private(set) var strips: [StripRenderState] = []

    /// Fixed backing scale for offscreen rendering; nil follows the window's screen.
    var fixedScale: CGFloat? {
        didSet { if fixedScale != oldValue { setNeedsRebuild() } }
    }

    let env: RenderEnvironment
    let canvas = CALayer()
    private let root = CALayer()
    private let stripsLayer = CALayer()
    private let editGuides = EditGuides()
    let dragOverlay = DragOverlay()
    private var stripLayers: [StripLayers] = []
    private var geometryDirty = true

    struct Press {
        var strip: Int
        /// The track on the strip at mouse-down; every volume of the drag goes to it.
        var trackID: TrackID?
        var drag: VolumeDrag
        /// The value last reported to the delegate; nil until the drag first changes the volume.
        var sentValue: Double?
    }

    struct VolumeOverride {
        var strip: Int
        var trackID: TrackID?
        var value: Double
        /// When the drag ended; the override then lasts until the DAW echoes the value or `overrideHold` passes.
        var releasedAt: TimeInterval?
    }

    var press: Press?
    var volumeOverride: VolumeOverride?
    /// How long a released drag keeps the cap at the dragged value while waiting for the DAW to echo it.
    static let overrideHold: TimeInterval = 0.5

    /// Creates a bank of `stripCount` strips.
    public init(frame frameRect: NSRect = .zero, stripCount: Int = 8, style: MeterStyle = .standard) {
        let count = max(stripCount, 0)
        self.stripCount = count
        self.style = style
        self.calibration = .uncalibrated
        env = RenderEnvironment(
            style: style,
            geometry: BankGeometry(size: frameRect.size, stripCount: count, style: style, scale: 2),
            calibration: .uncalibrated
        )
        super.init(frame: frameRect)
        // Layer-hosting: the view owns this tree, AppKit only positions the root.
        layer = root
        wantsLayer = true
        root.addSublayer(canvas)
        canvas.addSublayer(stripsLayer)
        canvas.addSublayer(editGuides.container)
        canvas.addSublayer(dragOverlay.container)
        rebuildStrips()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BankView is created in code")
    }

    // MARK: - Frames

    /// Pushes this frame's state. Cheap: call it from the display link on every frame.
    ///
    /// A press whose strip now shows another track (a bank change, a new selection) ends here, so a drag
    /// never moves a fader the user did not grab.
    public func update(strips newStrips: [StripRenderState]) {
        strips = newStrips
        if let current = press, state(ofStrip: current.strip).trackID != current.trackID {
            cancelPress()
        }
        redraw()
    }

    /// The state drawn on strip `index` (`.empty` when none was supplied).
    public func state(ofStrip index: Int) -> StripRenderState {
        index >= 0 && index < strips.count ? strips[index] : .empty
    }

    /// Current geometry (rebuilt first if the size, scale, count or style changed).
    public var geometry: BankGeometry {
        withoutActions { rebuildGeometryIfNeeded() }
        return env.geometry
    }

    /// The strip and region under a point in view coordinates.
    public func hit(at point: CGPoint) -> StripHit? {
        geometry.hit(at: point)
    }

    /// Display text of a peak readout: the calibration's text, with silence shown as "-∞".
    public nonisolated static func readoutText(for value: Float, calibration: MeterCalibration) -> String {
        let text = calibration.readout(for: value)
        return text == "-inf" ? "-∞" : text
    }

    /// Total text-layer string writes so far (for tests: frames must not rewrite unchanged text).
    var textWriteCount: Int { stripLayers.reduce(0) { $0 + $1.textWrites } }

    func redraw() {
        withoutActions {
            rebuildGeometryIfNeeded()
            for (i, layers) in stripLayers.enumerated() {
                let state = i < strips.count ? strips[i] : StripRenderState.empty
                layers.apply(state, volumeOverride: overrideValue(for: i, state: state))
            }
        }
    }

    private func overrideValue(for index: Int, state: StripRenderState) -> Double? {
        guard let override = volumeOverride, override.strip == index else { return nil }
        guard override.trackID == state.trackID else {
            volumeOverride = nil
            return nil
        }
        if let released = override.releasedAt,
           abs(state.volume - override.value) < 0.0005 || ProcessInfo.processInfo.systemUptime - released > BankView.overrideHold {
            volumeOverride = nil
            return nil
        }
        return override.value
    }

    // MARK: - Geometry

    private var backingScale: CGFloat {
        fixedScale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func rebuildStrips() {
        cancelPress()
        volumeOverride = nil
        withoutActions {
            stripLayers.forEach { $0.container.removeFromSuperlayer() }
            stripLayers = (0..<stripCount).map { _ in StripLayers(environment: env) }
            stripLayers.forEach { stripsLayer.addSublayer($0.container) }
            editGuides.setStripCount(stripCount)
        }
        setNeedsRebuild()
    }

    private func setNeedsRebuild() {
        geometryDirty = true
        needsLayout = true
        redraw()
    }

    private func rebuildGeometryIfNeeded() {
        let scale = backingScale
        let size = bounds.size
        let current = env.geometry
        guard geometryDirty || current.size != size || current.scale != scale || current.stripCount != stripCount else { return }
        geometryDirty = false
        env.setGeometry(BankGeometry(size: size, stripCount: stripCount, style: style, scale: scale))

        let geometry = env.geometry
        root.contentsScale = scale
        canvas.frame = CGRect(origin: .zero, size: geometry.size)
        canvas.contentsScale = scale
        canvas.backgroundColor = env.palette.background
        stripsLayer.frame = canvas.bounds
        for (i, layers) in stripLayers.enumerated() {
            layers.container.frame = geometry.stripFrames[i]
            layers.layout(geometry.strip(i))
        }
        editGuides.layout(env)
        dragOverlay.hide()
    }

    public override func layout() {
        super.layout()
        redraw()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        setNeedsRebuild()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setNeedsRebuild()
    }

    // MARK: - Events

    public override var isFlipped: Bool { false }

    /// Clicks act immediately, without first activating the app (the bridge never takes focus from the DAW).
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override var mouseDownCanMoveWindow: Bool { false }

    public override func mouseDown(with event: NSEvent) {
        guard !isEditing else { return super.mouseDown(with: event) }
        handleMouseDown(event)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard !isEditing else { return super.mouseDragged(with: event) }
        handleMouseDragged(event)
    }

    public override func mouseUp(with event: NSEvent) {
        guard !isEditing else { return super.mouseUp(with: event) }
        handleMouseUp(event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard !isEditing else { return super.rightMouseDown(with: event) }
        handleContextMenu(event)
    }
}

/// Runs `body` in a Core Animation transaction with implicit animations off.
@MainActor
func withoutActions(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}
