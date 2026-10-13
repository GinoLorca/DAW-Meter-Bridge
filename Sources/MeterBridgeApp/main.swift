import AppKit

// DAW Meter Bridge: a menu-bar app (no Dock icon) that draws DAW meters above a control surface.
// See docs/ARCHITECTURE.md. Options: see LaunchOptions.usage.

let launchOptions: LaunchOptions
do {
    launchOptions = try LaunchOptions.parse(CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("MeterBridge: \(error)\n\n\(LaunchOptions.usage)\n".utf8))
    exit(64)
}
if launchOptions.showHelp {
    print(LaunchOptions.usage)
    exit(0)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate(options: launchOptions)
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        application.run()
    }
}
