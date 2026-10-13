import AppKit
import MeterCore

/// The right-click menu of a strip.
@MainActor
enum StripContextMenu {
    static func make(for track: TrackInfo?, controller: AppController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let track {
            let id = track.id
            menu.addItem(.info(track.name.isEmpty ? "Untitled track" : track.name))
            menu.addItem(MenuActionItem("Select") { [weak controller] in controller?.send(.select(id)) })
            if track.canSolo {
                menu.addItem(MenuActionItem(track.isSoloed ? "Unsolo" : "Solo") { [weak controller] in
                    controller?.send(.setSolo(id, !track.isSoloed, exclusive: nil))
                })
                if !track.isSoloed {
                    menu.addItem(MenuActionItem("Add to Solo") { [weak controller] in
                        controller?.send(.setSolo(id, true, exclusive: false))
                    })
                }
            }
            if track.canMute {
                menu.addItem(MenuActionItem(track.isMuted ? "Unmute" : "Mute") { [weak controller] in
                    controller?.send(.setMute(id, !track.isMuted))
                })
            }
            if track.canArm {
                let armed = track.isArmed ?? false
                menu.addItem(MenuActionItem(armed ? "Disarm" : "Arm") { [weak controller] in
                    controller?.send(.setArm(id, !armed))
                })
            }
            menu.addItem(MenuActionItem("Reset Peaks") { [weak controller] in
                controller?.store.resetPeaks(for: id)
                controller?.keepAwake(for: 0.1)
            })
            menu.addItem(.separator())
        }
        menu.addItem(MenuActionItem("Reset All Peaks") { [weak controller] in controller?.resetAllPeaks() })
        menu.addItem(MenuActionItem("Edit Layout", state: controller.isEditing ? .on : .off) { [weak controller] in
            controller?.toggleEditing()
        })
        menu.addItem(MenuActionItem("Hide Bridge") { [weak controller] in controller?.setBridgeVisible(false) })
        return menu
    }
}
