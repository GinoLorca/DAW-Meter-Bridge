import Foundation

/// The `dawmeterbridge://` URL scheme (docs/CONTROL.md): `dawmeterbridge://<bridge|main|edit>/<toggle|show|hide>`.
public enum ControlURL {
    public static let scheme = "dawmeterbridge"

    /// The command a URL names, or nil when it isn't one of ours.
    ///
    /// Scheme, target and action are case-insensitive; a trailing slash, a query and a fragment are
    /// ignored. `dawmeterbridge:bridge/toggle` (no `//`) is accepted too.
    public static func command(from url: URL) -> ControlCommand? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else { return nil }
        var parts: [String] = []
        if let host = components.host, !host.isEmpty { parts.append(host) }
        parts += components.path.split(separator: "/").map(String.init)
        guard parts.count == 2,
              let target = ControlTarget(rawValue: parts[0].lowercased()),
              let action = ControlAction(rawValue: parts[1].lowercased()) else { return nil }
        return ControlCommand(target, action)
    }

    /// The command's URL, e.g. `dawmeterbridge://main/toggle`.
    public static func url(for command: ControlCommand) -> URL {
        // Built from fixed ASCII names, so it is always a valid URL.
        URL(string: "\(scheme)://\(command.target.rawValue)/\(command.action.rawValue)")!
    }

    /// The commands of URLs that arrived while the app was launching (the URLs that launched it), as they
    /// are applied once it has started.
    ///
    /// Such a toggle means "turn it on": the app wasn't showing anything, so it must not undo what the app
    /// restores at launch (the bridge and the Main meter as they were when it quit). The first command
    /// for `bridge` or `main` therefore becomes `show` when it is a toggle; the commands after it see the
    /// state it left and stay as they are. Edit mode always starts off, so `edit` is left alone.
    public static func launchResolved(_ commands: [ControlCommand]) -> [ControlCommand] {
        var seen = Set<ControlTarget>()
        return commands.map { command in
            guard seen.insert(command.target).inserted, command.action == .toggle, command.target != .edit else {
                return command
            }
            return ControlCommand(command.target, .show)
        }
    }
}
