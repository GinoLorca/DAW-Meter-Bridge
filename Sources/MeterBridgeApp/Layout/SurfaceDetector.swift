import BridgeLayout
import CoreMIDI

/// Guesses which control-surface families are connected from the MIDI ports macOS lists,
/// e.g. "SSL V-MIDI Port 1" (SSL 360°) or "WING" (Behringer WING over USB). Used to pick a profile.
enum SurfaceDetector {
    /// Surface families named by the online MIDI sources and destinations (a WING wins over SSL 360°'s
    /// always-present virtual ports; see `SurfaceHint.connectedFamilies`).
    static func connectedSurfaces() -> Set<SurfaceHint> {
        SurfaceHint.connectedFamilies(inDeviceNames: midiEndpointNames())
    }

    /// Display names of the MIDI sources and destinations that are online now.
    static func midiEndpointNames() -> [String] {
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            if let name = displayName(of: MIDIGetSource(index)) { names.append(name) }
        }
        for index in 0..<MIDIGetNumberOfDestinations() {
            if let name = displayName(of: MIDIGetDestination(index)) { names.append(name) }
        }
        return names
    }

    private static func displayName(of object: MIDIObjectRef) -> String? {
        guard object != 0 else { return nil }
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
