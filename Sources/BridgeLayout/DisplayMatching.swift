/// Which connected display a saved `DisplayLayout` belongs on.
public struct DisplayAssignment: Hashable, Sendable {
    /// Index into the saved layouts (e.g. `LayoutProfile.displays`).
    public var layoutIndex: Int
    /// Index into the connected displays passed to `DisplayMatcher.assign`.
    public var displayIndex: Int
    public var match: DisplayMatch

    public init(layoutIndex: Int, displayIndex: Int, match: DisplayMatch) {
        self.layoutIndex = layoutIndex
        self.displayIndex = displayIndex
        self.match = match
    }
}

/// Pairs saved display layouts with the displays that are connected now.
public enum DisplayMatcher {
    /// Pairs saved display fingerprints with connected ones, strongest matches first, each side used at most once.
    ///
    /// Layouts without any matching display are left out; the app decides where to show them
    /// (for example on the main screen, or not at all). Results are sorted by `layoutIndex`.
    public static func assign(_ saved: [DisplayFingerprint], to connected: [DisplayFingerprint]) -> [DisplayAssignment] {
        var candidates: [DisplayAssignment] = []
        for (layoutIndex, fingerprint) in saved.enumerated() {
            for (displayIndex, display) in connected.enumerated() {
                let match = fingerprint.match(display)
                if match.isMatch {
                    candidates.append(DisplayAssignment(layoutIndex: layoutIndex, displayIndex: displayIndex, match: match))
                }
            }
        }
        // Strongest first; ties keep saved order, then connected order, so the result is deterministic.
        candidates.sort {
            if $0.match != $1.match { return $0.match > $1.match }
            if $0.layoutIndex != $1.layoutIndex { return $0.layoutIndex < $1.layoutIndex }
            return $0.displayIndex < $1.displayIndex
        }
        var usedLayouts = Set<Int>()
        var usedDisplays = Set<Int>()
        var result: [DisplayAssignment] = []
        for candidate in candidates where !usedLayouts.contains(candidate.layoutIndex) && !usedDisplays.contains(candidate.displayIndex) {
            usedLayouts.insert(candidate.layoutIndex)
            usedDisplays.insert(candidate.displayIndex)
            result.append(candidate)
        }
        return result.sorted { $0.layoutIndex < $1.layoutIndex }
    }
}
