import BridgeLayout

/// Human-readable descriptions of strip bindings for menus, tabs and the HUD.
enum BindingText {
    /// e.g. "Surface unit 1, strips 1–8", "Selected track", "Tracks 9–16".
    static func describe(_ binding: StripBinding, stripCount: Int) -> String {
        let count = max(1, stripCount)
        switch binding {
        case let .surfaceUnit(index, firstStrip):
            let last = firstStrip + count
            if count == 1 { return "Surface unit \(index + 1), strip \(firstStrip + 1)" }
            return "Surface unit \(index + 1), strips \(firstStrip + 1)–\(last)"
        case .selectedTrack:
            return "Selected track"
        case .mainTrack:
            return "Main track"
        case let .trackList(offset):
            return count == 1 ? "Track \(offset + 1)" : "Tracks \(offset + 1)–\(offset + count)"
        }
    }

    /// The short line on a group's tab, e.g. "8 strips · Surface unit 1, strips 1–8".
    static func summary(of group: StripGroup) -> String {
        let strips = group.stripCount == 1 ? "1 strip" : "\(group.stripCount) strips"
        return "\(strips) · \(describe(group.binding, stripCount: group.stripCount))"
    }
}
