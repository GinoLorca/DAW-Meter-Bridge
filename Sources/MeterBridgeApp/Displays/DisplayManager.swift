import AppKit
import BridgeLayout

/// Enumerates the connected displays and reports when they change.
///
/// `NSApplication.didChangeScreenParametersNotification` arrives several times while a display is
/// plugged in or a mode changes, so changes are debounced before `onChange` is called.
@MainActor
final class DisplayManager {
    /// Displays as of the last refresh, main display first.
    private(set) var displays: [ConnectedDisplay] = []
    /// Called after a (debounced) change of the connected displays or their modes.
    var onChange: (([ConnectedDisplay]) -> Void)?

    private let debounce: Duration
    private var observer: (any NSObjectProtocol)?
    private var pendingRefresh: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(500)) {
        self.debounce = debounce
        displays = Self.currentDisplays()
    }

    /// The main display (with the menu bar), or the first one.
    var mainDisplay: ConnectedDisplay? {
        displays.first(where: \.isMain) ?? displays.first
    }

    /// Starts listening for display changes.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    /// Re-reads the displays now. Returns true (and calls `onChange`) if anything changed.
    @discardableResult
    func refresh() -> Bool {
        let current = Self.currentDisplays()
        guard current != displays else { return false }
        displays = current
        onChange?(current)
        return true
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let delay = debounce
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingRefresh = nil
            self?.refresh()
        }
    }

    // MARK: - Reading displays

    /// The CoreGraphics id of a screen.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// All connected screens, main display first.
    static func currentDisplays() -> [ConnectedDisplay] {
        let result = NSScreen.screens.compactMap(display(for:))
        return result.sorted { lhs, rhs in lhs.isMain && !rhs.isMain }
    }

    /// Fingerprint, scale and EDID size of one screen.
    static func display(for screen: NSScreen) -> ConnectedDisplay? {
        guard let id = displayID(of: screen) else { return nil }
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        var pixelSize = CGSize(width: frame.width * scale, height: frame.height * scale)
        if let mode = CGDisplayCopyDisplayMode(id), mode.pixelWidth > 0, mode.pixelHeight > 0 {
            pixelSize = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).flatMap { unmanaged -> String? in
            let uuid = unmanaged.takeRetainedValue()
            return CFUUIDCreateString(nil, uuid) as String?
        }
        let fingerprint = DisplayFingerprint(
            uuid: uuid,
            vendorID: CGDisplayVendorNumber(id),
            modelID: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id),
            name: screen.localizedName,
            pixelSize: pixelSize,
            pointSize: frame.size
        )
        let physical = CGDisplayScreenSize(id)
        return ConnectedDisplay(
            displayID: id,
            fingerprint: fingerprint,
            frame: frame,
            backingScale: scale,
            physicalSizeMillimeters: physical,
            pointsPerMillimeter: pointsPerMillimeter(pointSize: frame.size, physicalMillimeters: physical),
            isMain: CGDisplayIsMain(id) != 0
        )
    }

    /// Points per millimetre from the EDID size, or nil when it looks wrong.
    ///
    /// Besides the plausible range in `DisplayMetrics`, the scale from the height must agree with the
    /// scale from the width within 15 %: cheap panels often report a made-up or swapped size. A size
    /// reported for the other orientation (a rotated panel) is accepted when it matches once swapped.
    nonisolated static func pointsPerMillimeter(pointSize: CGSize, physicalMillimeters: CGSize) -> Double? {
        func consistent(_ physical: CGSize) -> Double? {
            guard let byWidth = DisplayMetrics.pointsPerMillimeter(
                pointWidth: pointSize.width,
                physicalWidthMillimeters: Double(physical.width)
            ) else { return nil }
            guard physical.height > 0, pointSize.height > 0 else { return byWidth }
            let byHeight = Double(pointSize.height / physical.height)
            return abs(byHeight - byWidth) / byWidth <= 0.15 ? byWidth : nil
        }
        if let scale = consistent(physicalMillimeters) { return scale }
        return consistent(CGSize(width: physicalMillimeters.height, height: physicalMillimeters.width))
    }
}
