import AppKit

/// A menu item that runs a closure.
final class MenuActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(
        _ title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        state: NSControl.StateValue = .off,
        isEnabled: Bool = true,
        handler: @escaping @MainActor () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: key)
        target = self
        keyEquivalentModifierMask = modifiers
        self.state = state
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("MenuActionItem is created in code")
    }

    @objc private func invoke() {
        // AppKit sends menu actions on the main thread.
        let handler = self.handler
        MainActor.assumeIsolated { handler() }
    }
}

extension NSMenuItem {
    /// A disabled, informational line. Long text is shortened; the full text is the tooltip.
    static func info(_ text: String, symbol: String? = nil, limit: Int = 90) -> NSMenuItem {
        let title = text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if title != text { item.toolTip = text }
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// A submenu item.
    static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }
}
