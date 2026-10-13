import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's `RegisterEventHotKey`, which needs no Accessibility
/// permission (unlike a global `NSEvent` monitor).
///
/// The hotkey stays registered until `unregister()`; keep the object for the app's lifetime.
@MainActor
final class GlobalHotKey {
    /// Mac virtual key code, e.g. `kVK_ANSI_M`.
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    private let identifier: UInt32
    private var reference: EventHotKeyRef?

    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static var handlerInstalled = false
    /// 'MBdg'
    nonisolated private static let signature: OSType = 0x4D42_6467

    /// Registers the hotkey. Returns nil if registration fails.
    ///
    /// Registration is exclusive, so it fails when another app already holds the combination exclusively,
    /// but macOS does not report other apps' non-exclusive hotkeys or system shortcuts: a conflict with
    /// those can't be detected here.
    init?(keyCode: Int, modifiers: NSEvent.ModifierFlags, action: @escaping @MainActor () -> Void) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1
        guard Self.installHandlerIfNeeded() else { return nil }

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            self.keyCode,
            Self.carbonModifiers(modifiers),
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            appLog.error("Could not register hotkey \(keyCode) (status \(status))")
            return nil
        }
        reference = hotKeyRef
        Self.actions[identifier] = action
    }

    /// Releases the hotkey.
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[identifier] = nil
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    private static func installHandlerIfNeeded() -> Bool {
        guard !handlerInstalled else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            // Carbon dispatches application events on the main thread.
            MainActor.assumeIsolated { GlobalHotKey.fire(id) }
            return noErr
        }, 1, &eventType, nil, nil)
        handlerInstalled = status == noErr
        if !handlerInstalled { appLog.error("Could not install the hotkey handler (status \(status))") }
        return handlerInstalled
    }

    private static func fire(_ id: UInt32) {
        actions[id]?()
    }
}
