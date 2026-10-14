// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DAWMeterBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeterBridge", targets: ["MeterBridgeApp"]),
    ],
    targets: [
        // Track/snapshot model, commands, MeterSource protocol, ballistics, mix focus, volume curve.
        .target(name: "MeterCore"),
        // Wire messages for the Ableton Remote Script <-> app protocol (docs/PROTOCOL.md).
        .target(name: "BridgeProtocol", dependencies: ["MeterCore"]),
        // MeterSource implementations: SimulatedSource and LiveSource (UDP).
        .target(name: "MeterSources", dependencies: ["MeterCore", "BridgeProtocol"]),
        // Layout model, templates, calibration/edit math, persistence.
        .target(name: "BridgeLayout", dependencies: ["MeterCore"]),
        // Core Animation strip/bank views.
        .target(name: "MeterRendering", dependencies: ["MeterCore"]),
        // App control (docs/CONTROL.md): ctl messages, subscribers, dawmeterbridge:// URLs, UDP control server.
        .target(name: "BridgeControl", dependencies: ["MeterSources"]),
        // Menu-bar app: panels, edit mode, hotkeys, settings.
        .executableTarget(
            name: "MeterBridgeApp",
            dependencies: ["MeterCore", "BridgeProtocol", "MeterSources", "BridgeLayout", "MeterRendering", "BridgeControl"]
        ),

        .testTarget(name: "MeterCoreTests", dependencies: ["MeterCore"]),
        .testTarget(name: "BridgeProtocolTests", dependencies: ["BridgeProtocol", "MeterCore"]),
        .testTarget(name: "MeterSourcesTests", dependencies: ["MeterSources", "BridgeProtocol", "MeterCore"]),
        .testTarget(name: "BridgeLayoutTests", dependencies: ["BridgeLayout", "MeterCore"]),
        .testTarget(name: "MeterRenderingTests", dependencies: ["MeterRendering", "MeterCore"]),
        .testTarget(name: "BridgeControlTests", dependencies: ["BridgeControl", "MeterSources"]),
    ],
    swiftLanguageModes: [.v6]
)
