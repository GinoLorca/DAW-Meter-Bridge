import BridgeLayout
import CoreGraphics
import Foundation

extension AppController {
    // MARK: - Loading and saving

    /// Reads layouts.json, creating the first-run layouts when there is none (or `--reset-layout`).
    ///
    /// An unreadable file is moved aside by `LayoutStore` and reported. If the file exists but cannot
    /// even be read, the defaults are used in memory and nothing is saved, so the file is never lost.
    func loadLayouts() {
        var createDefaults = false
        if options.resetLayout {
            backUpLayoutsBeforeReset()
            createDefaults = true
        } else if isHeadless {
            createDefaults = !loadLayoutsReadOnly()
        } else {
            do {
                let result = try layoutStore.load()
                document = result.document
                switch result.status {
                case .loaded:
                    break
                case .missing:
                    createDefaults = true
                case let .recovered(backupURL, reason):
                    createDefaults = true
                    layoutMessages.append("layouts.json couldn’t be used (\(reason)). It was moved to \(backupURL.lastPathComponent) and the default layouts were created.")
                case let .newerFormat(reason):
                    // Keep the newer version's file as it is: defaults in memory, nothing saved.
                    canSaveLayouts = false
                    createDefaults = true
                    layoutMessages.append("\(reason) It was left unchanged; showing the default layouts, and changes won’t be saved. Use the newer version to keep your layouts.")
                }
            } catch {
                canSaveLayouts = false
                createDefaults = true
                layoutMessages.append("Couldn’t read \(layoutStore.url.path): \(error.localizedDescription) Using the default layouts; changes won’t be saved.")
            }
        }
        if createDefaults || document.profiles.isEmpty {
            let display = displayManager.mainDisplay ?? Self.standInDisplay
            document = DefaultLayouts.document(on: display, bottomInset: isHeadless ? 0 : display.bottomDockInset)
            saveLayouts()
        }
        addMainMetersOnce()
    }

    /// Version 0.2.0 gives every profile without a Main meter a visible one, once: the settings remember
    /// it (`addedMainMeters`), so a Main meter the user deletes later stays deleted. First-run layouts
    /// already have one. Snapshot runs apply it in memory only; when layouts.json can't be saved it is
    /// tried again next launch.
    private func addMainMetersOnce() {
        guard !settings.addedMainMeters else { return }
        let display = displayManager.mainDisplay ?? Self.standInDisplay
        let fallback = DefaultLayouts.mainMeterFallback(on: display, bottomInset: isHeadless ? 0 : display.bottomDockInset)
        let added = document.addMainMetersWhereMissing(fallback: fallback)
        if added > 0 {
            appLog.info("Added a Main meter to \(added) profile(s)")
            saveLayouts()
        }
        guard canSaveLayouts, !isHeadless else { return }
        settings.addedMainMeters = true
        saveSettings()
    }

    /// Snapshot mode: decodes layouts.json without the store's recovery, which would move a bad file
    /// aside. Returns false when there is no usable document.
    private func loadLayoutsReadOnly() -> Bool {
        guard let data = try? Data(contentsOf: layoutStore.url) else { return false }
        do {
            document = try JSONDecoder().decode(LayoutDocument.self, from: data)
            return true
        } catch {
            layoutMessages.append("layouts.json couldn’t be used (\(error.localizedDescription)) Showing the default layouts.")
            return false
        }
    }

    /// Writes layouts.json (never in snapshot mode or when the file could not be read).
    func saveLayouts() {
        pendingLayoutSave?.cancel()
        pendingLayoutSave = nil
        guard canSaveLayouts, !isHeadless else { return }
        do {
            try layoutStore.save(document)
        } catch {
            let message = "Couldn’t save layouts: \(error.localizedDescription)"
            appLog.error("\(message, privacy: .public)")
            if !layoutMessages.contains(message) { layoutMessages.append(message) }
        }
    }

    /// Saves layouts.json shortly, coalescing a burst of changes (nudges, menu edits) into one write.
    func scheduleLayoutSave(after delay: Duration = .milliseconds(300)) {
        guard canSaveLayouts, !isHeadless else { return }
        pendingLayoutSave?.cancel()
        pendingLayoutSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveLayouts()
        }
    }

    /// `--reset-layout`: copies layouts.json to the first free `layouts.json.before-reset[.N].bak`, so
    /// resetting twice never replaces the backup of the real layout.
    private func backUpLayoutsBeforeReset() {
        guard !isHeadless else { return }
        do {
            _ = try layoutStore.copyToBackup(suffix: "before-reset")
        } catch {
            canSaveLayouts = false
            layoutMessages.append("Couldn’t back up layouts.json before resetting (\(error.localizedDescription)); the reset layout won’t be saved.")
        }
    }

    /// Used only if macOS reports no screens at all.
    static let standInDisplay = ConnectedDisplay(
        displayID: 0,
        fingerprint: DisplayFingerprint(name: "Display", pixelSize: CGSize(width: 1920, height: 1080), pointSize: CGSize(width: 1920, height: 1080)),
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        backingScale: 1,
        physicalSizeMillimeters: .zero,
        pointsPerMillimeter: nil,
        isMain: true
    )

    // MARK: - Profiles and placement

    /// Picks the profile for the connected displays and surfaces (unless one was chosen by hand) and
    /// places its panels.
    func selectProfileAndPresent() {
        let previous = document.activeProfileID
        let previousMode = document.selectionMode
        document.selectProfile(connectedDisplays: displayManager.displays.map(\.fingerprint), surfaces: surfaces)
        if document.activeProfileID != previous || document.selectionMode != previousMode { saveLayouts() }
        presentLayout()
    }

    /// Places the active profile's groups on the connected displays and updates the panels.
    func presentLayout() {
        matchSimulatorToProfile()
        presentation = LayoutPresenter.present(document.activeProfile, on: displayManager.displays)
        if let updated = presentation.updatedProfile {
            document.upsert(updated)
            saveLayouts()
        }
        if !isHeadless {
            panelManager.apply(presentation.placements)
            if isEditing { layoutEditor?.panelsDidChange(host: self) }
        }
        updateWatchedTracks()
        keepAwake(for: 0.1)
        onStatusChange?()
    }

    func displaysChanged() {
        surfaces = SurfaceDetector.connectedSurfaces()
        selectProfileAndPresent()
    }

    /// CoreMIDI's setup changed: re-detect the surface families and re-pick the profile if they changed.
    func surfacesMayHaveChanged() {
        let current = SurfaceDetector.connectedSurfaces()
        guard current != surfaces else { return }
        surfaces = current
        selectProfileAndPresent()
    }

    /// Uses `id` until the user switches back to automatic (`nil`). Undoable like any layout change.
    func chooseProfile(_ id: UUID?) {
        if id == nil { surfaces = SurfaceDetector.connectedSurfaces() }
        let displays = displayManager.displays.map(\.fingerprint)
        let surfaces = self.surfaces
        let changed = performLayoutChange(id == nil ? "Automatic Profile" : "Switch Profile") { document in
            if let id {
                document.chooseManually(id)
            } else {
                document.chooseAutomatically()
            }
            document.selectProfile(connectedDisplays: displays, surfaces: surfaces)
        }
        if !changed { presentLayout() }
        saveLayouts()
    }

    // MARK: - Moving to another display

    /// "Slide it over": moves every group of the active profile onto `display`, keeping physical size
    /// and spacing when both displays' scales are known (else proportionally), puts the Main meter back
    /// at the new display's right edge, and saves.
    func moveBridge(to display: ConnectedDisplay) {
        guard var profile = document.activeProfile else { return }
        let result = profile.moveAllGroups(to: display.fingerprint, targetPointsPerMillimeter: display.pointsPerMillimeter)
        profile.reanchorMainMeters()
        performLayoutChange("Move Bridge to \(display.name)") { $0.upsert(profile) }
        saveLayouts()

        var message = result.mode == .physical
            ? "The meters kept their physical size and spacing."
            : "The meters were scaled to the new display because its physical size isn’t known yet."
        let bounds = display.fingerprint.bounds
        let offscreen = result.offscreenGroupIDs.compactMap { id in
            profile.group(withID: id).flatMap { $0.frame.intersects(bounds) ? nil : $0.name }
        }
        if !offscreen.isEmpty {
            message += " Not on the display (too wide to fit): \(offscreen.joined(separator: ", "))."
        }
        message += " Calibrate the strips over the faders in Edit Layout (⌃⌥⌘E)."
        onNotice?("Moved “\(profile.name)” to \(display.name)", message)
    }

    /// The display the active profile is shown on, if exactly one.
    var currentBridgeDisplay: ConnectedDisplay? {
        let ids = Set(presentation.placements.map(\.display.displayID))
        guard ids.count == 1 else { return nil }
        return presentation.placements.first?.display
    }
}
