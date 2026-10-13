import MeterCore

/// A small toggle button under a strip's name.
public enum StripButton: Int, Hashable, Sendable, CaseIterable {
    case solo
    case mute
    case arm

    /// The one-letter label drawn on the button.
    public var label: String {
        switch self {
        case .solo: return "S"
        case .mute: return "M"
        case .arm: return "R"
        }
    }
}

/// Everything one strip of a `BankView` draws in a frame.
public struct StripRenderState: Hashable, Sendable {
    /// The track shown, or nil for an empty strip.
    public var trackID: TrackID?
    public var name: String
    /// Track colour for the name pill; nil draws a neutral grey pill.
    public var color: RGBColor?
    public var kind: TrackKind
    /// Ballistics for the meter, peak line, clip LEDs and readout.
    public var meter: StripMeterState
    /// Selection, solo/mute/arm lights and dimming.
    public var focus: StripFocus
    /// Mixer volume, normalized 0...1 as the DAW stores it; positions the fader cap.
    public var volume: Double
    /// Volume as the DAW displays it, e.g. "-6.0 dB". Shown while dragging when no text provider is set.
    public var volumeText: String
    /// True when no track is on this strip: only a faint outline is drawn and gestures are ignored.
    public var isEmpty: Bool
    /// Two meter columns (left/right) when true, one wide column (the louder channel) when false.
    public var isStereo: Bool
    /// Whether the S button is drawn and clickable.
    public var canSolo: Bool
    /// Whether the M button is drawn and clickable.
    public var canMute: Bool
    /// Whether the R button is drawn and clickable.
    public var canArm: Bool

    /// Creates a strip state. `isEmpty` defaults to `trackID == nil`; the button flags default from `kind`
    /// (no S/M on the main track, R only on audio and MIDI tracks).
    public init(
        trackID: TrackID?,
        name: String = "",
        color: RGBColor? = nil,
        kind: TrackKind = .audio,
        meter: StripMeterState = .silent,
        focus: StripFocus = .none,
        volume: Double = 0.85,
        volumeText: String = "",
        isEmpty: Bool? = nil,
        isStereo: Bool = true,
        canSolo: Bool? = nil,
        canMute: Bool? = nil,
        canArm: Bool? = nil
    ) {
        self.trackID = trackID
        self.name = name
        self.color = color
        self.kind = kind
        self.meter = meter
        self.focus = focus
        self.volume = volume
        self.volumeText = volumeText
        self.isEmpty = isEmpty ?? (trackID == nil)
        self.isStereo = isStereo
        self.canSolo = canSolo ?? (kind != .main)
        self.canMute = canMute ?? (kind != .main)
        self.canArm = canArm ?? (kind == .audio || kind == .midi)
    }

    /// The state for a DAW track, with its meter ballistics and mix focus.
    public init(track: TrackInfo, meter: StripMeterState, focus: StripFocus, isStereo: Bool = true) {
        self.init(
            trackID: track.id,
            name: track.name,
            color: track.color,
            kind: track.kind,
            meter: meter,
            focus: focus,
            volume: track.volume,
            volumeText: track.volumeText,
            isEmpty: false,
            isStereo: isStereo,
            canSolo: track.canSolo,
            canMute: track.canMute,
            canArm: track.canArm
        )
    }

    /// A strip with no track.
    public static let empty = StripRenderState(trackID: nil)

    /// Whether `button` is drawn and clickable on this strip.
    public func allows(_ button: StripButton) -> Bool {
        guard !isEmpty else { return false }
        switch button {
        case .solo: return canSolo
        case .mute: return canMute
        case .arm: return canArm
        }
    }

    /// Whether `button` is lit.
    public func isLit(_ button: StripButton) -> Bool {
        switch button {
        case .solo: return focus.isSoloed
        case .mute: return focus.isMuted
        case .arm: return focus.isArmed
        }
    }
}
