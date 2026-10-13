import AppKit
import BridgeLayout
import MeterCore
import MeterRendering

/// Draws frames for panels. Implemented by `AppController`.
@MainActor
protocol GroupPanelRenderer: AnyObject {
    /// Called by a panel's display link on every refresh while it runs. Advance shared state (once per
    /// frame), call `panel.render(...)`, and return false to let the link idle until `wake()`.
    func renderFrame(for panel: GroupPanelController, at time: TimeInterval) -> Bool
}

/// One strip group on screen: its panel, bank view and display link.
@MainActor
final class GroupPanelController {
    /// Where the group is shown.
    private(set) var placement: GroupPlacement
    let panel: BridgePanel
    let hostView: GroupHostView
    let bankView: BankView
    /// Whether the panel is ordered in (its display link may run).
    private(set) var isShown = false

    private weak var renderer: (any GroupPanelRenderer)?
    private var driver: DisplayLinkDriver?
    private var resolvedRevision = -1
    /// Track on each strip as of the last rendered snapshot revision.
    private(set) var trackIDs: [TrackID?] = []

    var group: StripGroup { placement.group }
    var display: ConnectedDisplay { placement.display }
    var groupID: UUID { placement.group.id }

    init(
        placement: GroupPlacement,
        style: MeterStyle,
        calibration: MeterCalibration,
        renderer: any GroupPanelRenderer,
        bankDelegate: any BankViewDelegate
    ) {
        self.placement = placement
        self.renderer = renderer
        let frames = Self.frames(for: placement)
        panel = BridgePanel(contentRect: frames.panel)
        hostView = GroupHostView(frame: CGRect(origin: .zero, size: frames.panel.size))
        bankView = BankView(frame: frames.bank, stripCount: placement.group.stripCount, style: style)
        bankView.calibration = calibration
        bankView.delegate = bankDelegate
        hostView.addSubview(bankView)
        hostView.controller = self
        panel.contentView = hostView
        panel.setFrame(frames.panel, display: false)
        panel.level = Self.level(for: placement)
    }

    /// Just below the Dock, so a revealed Dock draws over the bridge and stays clickable, but above every
    /// app window; status-bar level only where the group covers a menu bar (a short bar display).
    static func level(for placement: GroupPlacement) -> NSWindow.Level {
        let belowDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        guard let screen = placement.display.screen else { return belowDock }
        let menuBarBottom = screen.visibleFrame.maxY
        let coversMenuBar = menuBarBottom < screen.frame.maxY && placement.globalFrame.maxY > menuBarBottom
        return coversMenuBar ? .statusBar : belowDock
    }

    /// Window frames are whole points, but a group (snapped to device pixels) may start at a half point
    /// on a Retina display. The panel covers the group rounded outward, and the bank sits at the group's
    /// exact position inside it; the sliver around it is transparent.
    ///
    /// The group is snapped to the display's pixel grid here too, as a safety net: a frame scaled from
    /// another display or mode that missed snapping would otherwise blur every LED gap and rail.
    static func frames(for placement: GroupPlacement) -> (panel: CGRect, bank: CGRect) {
        let global = PixelGrid(scale: placement.display.backingScale).snap(placement.globalFrame)
        let panel = NSIntegralRectWithOptions(global, .alignAllEdgesOutward)
        let bank = CGRect(x: global.minX - panel.minX, y: global.minY - panel.minY, width: global.width, height: global.height)
        return (panel, bank)
    }

    /// Moves or resizes the panel for a new placement of the same group.
    func update(_ newPlacement: GroupPlacement) {
        let old = placement
        placement = newPlacement
        if old.group != newPlacement.group { resolvedRevision = -1 }
        if newPlacement.group.stripCount != bankView.stripCount {
            bankView.stripCount = newPlacement.group.stripCount
        }
        if old.globalFrame != newPlacement.globalFrame {
            let frames = Self.frames(for: newPlacement)
            panel.setFrame(frames.panel, display: isShown)
            bankView.frame = frames.bank
        }
        let level = Self.level(for: newPlacement)
        if panel.level != level { panel.level = level }
        if old.display.displayID != newPlacement.display.displayID, let driver, driver.isRunning {
            // The link follows the view's screen; restart it so it ticks at the new display's rate.
            driver.stop()
            driver.start()
        }
        wake()
    }

    /// Orders the panel in and starts its display link.
    func show() {
        guard !isShown else { return }
        isShown = true
        panel.orderFrontRegardless()
        if driver == nil {
            driver = DisplayLinkDriver(view: bankView) { [weak self] time in
                guard let self, let renderer = self.renderer else { return false }
                return renderer.renderFrame(for: self, at: time)
            }
        }
        driver?.start()
    }

    /// Orders the panel out and stops its display link.
    func hide() {
        guard isShown else { return }
        isShown = false
        driver?.stop()
        panel.orderOut(nil)
    }

    /// Hides the panel for good (the controller is being dropped).
    func close() {
        hide()
        driver = nil
        bankView.delegate = nil
        hostView.eventHandler = nil
        panel.close()
    }

    /// Resumes an idle display link (new meters or state arrived). Does nothing while hidden.
    func wake() {
        guard isShown else { return }
        driver?.wake()
    }

    /// Edit mode: guides on the bank, events to `hostView.eventHandler`, and the panel may become key.
    var isEditing: Bool {
        get { bankView.isEditing }
        set {
            bankView.isEditing = newValue
            panel.allowsKey = newValue
            if !newValue, panel.isKeyWindow { giveUpKeyFocus() }
            wake()
        }
    }

    /// Stops being the key window, so keys go back to the DAW. (`resignKey()` only reports a change; it
    /// doesn't make one.) Ordering the panel out and straight back in lets the window server pick the
    /// active app's window again.
    private func giveUpKeyFocus() {
        guard isShown else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Draws one frame: resolves the group's tracks when the snapshot changed, then pushes strip states.
    func render(snapshot: BridgeSnapshot, revision: Int, store: MeterStore, mixFocus: MixFocusSettings) {
        if resolvedRevision != revision {
            resolvedRevision = revision
            trackIDs = group.resolveTracks(in: snapshot)
            let curve = snapshot.volumeCurve ?? .liveApproximation
            bankView.volumeTextProvider = { curve.text(atNormalized: $0) }
        }
        bankView.update(strips: StripStateBuilder.states(
            for: trackIDs, snapshot: snapshot, store: store, mixFocus: mixFocus
        ))
    }
}
