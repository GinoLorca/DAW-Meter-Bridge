import SwiftUI

/// The settings window's content: meter look, ballistics, mix-focus dimming, hotkeys, the Live connection
/// and the layout file. Every control applies at once.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            metersSection
            ballisticsSection
            mixFocusSection
            hotKeysSection
            liveSection
            layoutSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 540, minHeight: 560, idealHeight: 720)
    }

    private var metersSection: some View {
        Section("Meters") {
            Toggle("Track names", isOn: model.binding(\.style.showNames))
            Toggle("Solo, mute and arm buttons", isOn: model.binding(\.style.showButtons))
            Toggle("Peak readout", isOn: model.binding(\.style.showPeakReadout))
            Toggle("Fader marker", isOn: model.binding(\.style.showFaderMarker))
            Toggle("Clip indicators", isOn: model.binding(\.style.showClipIndicators))
            Stepper(value: model.binding(\.style.segmentCount), in: 10...80, step: 2) {
                LabeledContent("LED segments", value: "\(model.settings.style.segmentCount)")
            }
        }
    }

    private var ballisticsSection: some View {
        Section {
            SliderRow(title: "Peak hold", value: model.binding(\.ballistics.peakHoldSeconds), range: 0...5, step: 0.1) {
                String(format: "%.1f s", $0)
            }
            SliderRow(title: "Bar fall", value: model.doubleBinding(\.ballistics.barFallPerSecond), range: 0.2...6, step: 0.05) {
                String(format: "%.2f × full scale/s", $0)
            }
            SliderRow(title: "Peak line fall", value: model.doubleBinding(\.ballistics.peakFallPerSecond), range: 0.05...2, step: 0.05) {
                String(format: "%.2f × full scale/s", $0)
            }
        } header: {
            Text("Ballistics")
        } footer: {
            Text("How fast bars and peak-hold lines fall between DAW updates. Bars always rise instantly.")
        }
    }

    private var mixFocusSection: some View {
        Section {
            SliderRow(title: "Muted tracks", value: model.binding(\.mixFocus.muteDim), range: 0...0.9, step: 0.05) {
                String(format: "%.0f%% dimmer", $0 * 100)
            }
            SliderRow(title: "Tracks silenced by a solo", value: model.binding(\.mixFocus.soloDim), range: 0...0.9, step: 0.05) {
                String(format: "%.0f%% dimmer", $0 * 100)
            }
        } header: {
            Text("Mix Focus")
        } footer: {
            Text("Dims strips the way the mix silences them. 0% turns dimming off.")
        }
    }

    private var hotKeysSection: some View {
        Section {
            ForEach(Self.hotKeys, id: \.0) { name, keys in
                LabeledContent(name) { Text(keys).monospaced() }
            }
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("The two global hotkeys work in any app. The rest work while Edit Layout is on. They can't be changed yet.")
        }
    }

    static let hotKeys: [(String, String)] = [
        ("Show or hide the bridge", "⌃⌥⌘M"),
        ("Edit layout on/off", "⌃⌥⌘E"),
        ("Nudge selected group 1 px / 10 px", "←→↑↓ / ⌥ arrows"),
        ("Resize selected group 1 px / 10 px", "⇧ arrows / ⇧⌥ arrows"),
        ("Fine drag (×0.1), no snapping", "⇧ drag, ⌘ drag"),
        ("Next / previous group", "Tab / ⇧Tab"),
        ("Delete group", "⌫"),
        ("Undo / redo layout change", "⌘Z / ⇧⌘Z"),
        ("Leave edit mode", "Esc"),
    ]

    private var liveSection: some View {
        Section("Ableton Live") {
            LabeledContent("Source in use", value: model.connection.activeSource)
            LabeledContent("Status") {
                Text(model.connection.statusLine).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            LabeledContent("Ports (UDP, 127.0.0.1)") {
                Text(portsText).monospacedDigit()
            }
            if let version = model.connection.liveVersion, !version.isEmpty {
                LabeledContent("Live version", value: version)
            }
            if let script = model.connection.scriptVersion {
                LabeledContent("MeterBridge script", value: script)
            }
            if let rate = model.connection.meterRate {
                LabeledContent("Meter rate", value: "\(rate) Hz")
            }
            ForEach(model.connection.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
            }
        }
    }

    private var portsText: String {
        let info = model.connection
        var text = "app \(info.listenPort), script \(info.scriptPort)"
        if let bound = info.boundPort, bound != info.listenPort { text += " (listening on \(bound))" }
        return text
    }

    private var layoutSection: some View {
        Section {
            LabeledContent("Layouts file") {
                Text(model.layoutsPath).font(.caption).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
            LabeledContent("Settings") {
                Text(model.settingsLocation).font(.caption).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
            HStack {
                Button("Restore Default Meter Settings") { model.restoreDefaultMeterSettings() }
                Spacer()
                Button("Reset Layout…", role: .destructive) { model.confirmResetLayout() }
            }
        } header: {
            Text("Layout and Files")
        } footer: {
            Text("Reset Layout replaces every profile with the first-run layouts along the bottom of the main display.")
        }
    }
}

/// A labelled slider with its value shown as text.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(format(value)).monospacedDigit().frame(minWidth: 140, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
