import BridgeLayout
import CoreGraphics
import Foundation

// Layout commands of the menus and edit mode. Each is one undo step, re-places the panels and is saved
// shortly after (see `performLayoutChange`).
extension AppController {
    // MARK: - Profiles

    /// Adds a profile built from `template` on the bridge's display (or the main display) and switches to it.
    @discardableResult
    func newProfile(from template: LayoutTemplate) -> UUID? {
        let display = preferredDisplay ?? Self.standInDisplay
        let profile = LayoutTemplates.profile(template, named: document.uniqueProfileName(template.title), on: display)
        performLayoutChange("New Profile") { $0.addProfile(profile) }
        return profile.id
    }

    func renameProfile(_ id: UUID, to name: String) {
        performLayoutChange("Rename Profile") { $0.renameProfile(id, to: name) }
    }

    /// Deletes a profile (never the last one) and picks the best remaining one for the connected hardware.
    func deleteProfile(_ id: UUID) {
        guard document.profiles.count > 1 else { return }
        let displays = displayManager.displays.map(\.fingerprint)
        let surfaces = self.surfaces
        performLayoutChange("Delete Profile") { document in
            document.removeProfile(withID: id)
            document.selectProfile(connectedDisplays: displays, surfaces: surfaces)
        }
    }

    /// Replaces every profile with the first-run layouts on the main display (undoable). The file as it
    /// was is copied to `layouts.json.before-reset[.N].bak` first, so the old layout survives quitting.
    func resetLayouts() {
        flushPendingSaves()
        if canSaveLayouts, !isHeadless {
            do {
                _ = try layoutStore.copyToBackup(suffix: "before-reset")
            } catch {
                appLog.error("Couldn’t back up layouts.json before resetting: \(error.localizedDescription, privacy: .public)")
            }
        }
        let display = displayManager.mainDisplay ?? Self.standInDisplay
        let defaults = DefaultLayouts.document(on: display, bottomInset: display.bottomDockInset)
        performLayoutChange("Reset Layout") { $0 = defaults }
        saveLayouts()
    }
}
