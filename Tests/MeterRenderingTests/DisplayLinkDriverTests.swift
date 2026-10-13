import AppKit
@testable import MeterRendering
import Testing

/// Lifecycle of the display-link driver (frame delivery needs an on-screen window, so it is checked manually).
@MainActor
@Suite struct DisplayLinkDriverTests {
    @Test func startWakeStop() {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let driver = DisplayLinkDriver(view: view) { _ in true }
        #expect(!driver.isRunning)
        driver.start()
        #expect(driver.isRunning)
        driver.stop()
        #expect(!driver.isRunning)
        driver.wake()
        #expect(driver.isRunning, "wake starts a stopped driver")
        driver.stop()
    }
}
