import Foundation

/// Constants of the app control protocol (docs/CONTROL.md): the Stream Deck plugin and other local
/// tools switch the bridge and the Main meter over UDP on 127.0.0.1.
public enum ControlProtocol {
    /// The `v` field every message carries. Messages with another version are dropped.
    public static let version = 1
    /// Port the app listens on for control messages (`--control-port` changes it).
    public static let defaultPort: UInt16 = 47802
    /// Datagrams of this size or larger are dropped ("under 2 KB").
    public static let maxDatagramSize = 2048
    /// A client counts as subscribed this many seconds after its last `ctl.sub` (it re-sends every 2 s).
    public static let subscriptionLifetime: TimeInterval = 6
    /// Most clients the app keeps at once; a new one replaces the one heard from least recently.
    public static let maxSubscribers = 8
}

/// What a command switches.
public enum ControlTarget: String, Hashable, Sendable, CaseIterable {
    /// The whole bridge is shown (Show/Hide Bridge, ⌃⌥⌘M).
    case bridge
    /// The active profile's Main meter group is shown ("Show Main Meter").
    case main
    /// Edit mode (⌃⌥⌘E). URL scheme only; `ctl` accepts `bridge` and `main`.
    case edit
}

/// What a command does to its switch.
public enum ControlAction: String, Hashable, Sendable, CaseIterable {
    case toggle
    case show
    case hide

    /// The action for a `ctl` message's `on` field: true = show, false = hide, null or absent = toggle.
    public init(on: Bool?) {
        switch on {
        case true?: self = .show
        case false?: self = .hide
        case nil: self = .toggle
        }
    }

    /// The switch's new value when it is `current` now.
    public func resolve(current: Bool) -> Bool {
        switch self {
        case .toggle: return !current
        case .show: return true
        case .hide: return false
        }
    }

    /// The `on` value of a `ctl` message for this action.
    public var on: Bool? {
        switch self {
        case .toggle: return nil
        case .show: return true
        case .hide: return false
        }
    }
}

/// One command from a `ctl` message or a `dawmeterbridge://` URL.
public struct ControlCommand: Hashable, Sendable, CustomStringConvertible {
    public var target: ControlTarget
    public var action: ControlAction

    public init(_ target: ControlTarget, _ action: ControlAction) {
        self.target = target
        self.action = action
    }

    /// E.g. "bridge/toggle", as in the URL.
    public var description: String { "\(target.rawValue)/\(action.rawValue)" }

    /// The value the command gives its switch when the app is in `state`.
    public func newValue(in state: ControlState) -> Bool {
        action.resolve(current: state.value(of: target))
    }
}

/// The app's state as `ctl.state` reports it.
public struct ControlState: Hashable, Sendable {
    /// The bridge is shown.
    public var bridge: Bool
    /// The Main meter group exists and is visible in the active profile (whatever `bridge` is).
    public var main: Bool
    /// Edit mode is on.
    public var edit: Bool
    /// `"live"` or `"simulator"`.
    public var source: String
    /// The source is connected (always true for the simulator).
    public var connected: Bool
    /// App version, e.g. "0.2.0".
    public var app: String

    public init(bridge: Bool, main: Bool, edit: Bool, source: String, connected: Bool, app: String) {
        self.bridge = bridge
        self.main = main
        self.edit = edit
        self.source = source
        self.connected = connected
        self.app = app
    }

    /// The value of a switch.
    public func value(of target: ControlTarget) -> Bool {
        switch target {
        case .bridge: return bridge
        case .main: return main
        case .edit: return edit
        }
    }
}
