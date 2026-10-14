import BridgeControl
import Foundation
import Testing

@Suite struct ControlURLTests {
    private func command(_ text: String) -> ControlCommand? {
        URL(string: text).flatMap(ControlURL.command(from:))
    }

    @Test func everyDocumentedURLParses() {
        #expect(command("dawmeterbridge://bridge/toggle") == ControlCommand(.bridge, .toggle))
        #expect(command("dawmeterbridge://bridge/show") == ControlCommand(.bridge, .show))
        #expect(command("dawmeterbridge://bridge/hide") == ControlCommand(.bridge, .hide))
        #expect(command("dawmeterbridge://main/toggle") == ControlCommand(.main, .toggle))
        #expect(command("dawmeterbridge://main/show") == ControlCommand(.main, .show))
        #expect(command("dawmeterbridge://main/hide") == ControlCommand(.main, .hide))
        #expect(command("dawmeterbridge://edit/toggle") == ControlCommand(.edit, .toggle))
    }

    @Test func spellingVariantsAreAccepted() {
        #expect(command("DAWMeterBridge://Main/Toggle") == ControlCommand(.main, .toggle))
        #expect(command("dawmeterbridge://bridge/hide/") == ControlCommand(.bridge, .hide))
        #expect(command("dawmeterbridge:bridge/show") == ControlCommand(.bridge, .show))
        #expect(command("dawmeterbridge://main/show?from=streamdeck#x") == ControlCommand(.main, .show))
        #expect(command("dawmeterbridge://edit/show") == ControlCommand(.edit, .show))
    }

    @Test func unknownURLsAreIgnored() {
        for text in [
            "dawmeterbridge://",
            "dawmeterbridge://bridge",
            "dawmeterbridge://bridge/flip",
            "dawmeterbridge://mixer/toggle",
            "dawmeterbridge://bridge/toggle/now",
            "dawmeterbridge:///bridge",
            "https://bridge/toggle",
            "meterbridge://bridge/toggle",
            "file:///bridge/toggle",
        ] {
            #expect(command(text) == nil, "\(text)")
        }
    }

    @Test func urlsRoundTrip() {
        for target in ControlTarget.allCases {
            for action in ControlAction.allCases {
                let command = ControlCommand(target, action)
                #expect(ControlURL.command(from: ControlURL.url(for: command)) == command)
            }
        }
        #expect(ControlURL.url(for: ControlCommand(.main, .toggle)).absoluteString == "dawmeterbridge://main/toggle")
    }

    @Test func aToggleThatLaunchesTheAppShows() {
        #expect(ControlURL.launchResolved([ControlCommand(.bridge, .toggle)]) == [ControlCommand(.bridge, .show)])
        #expect(ControlURL.launchResolved([ControlCommand(.main, .toggle)]) == [ControlCommand(.main, .show)])
        // Edit mode starts off, so its toggle already turns it on.
        #expect(ControlURL.launchResolved([ControlCommand(.edit, .toggle)]) == [ControlCommand(.edit, .toggle)])
        #expect(ControlURL.launchResolved([]) == [])
    }

    @Test func onlyTheFirstCommandPerSwitchIsResolvedAtLaunch() {
        let queued = [
            ControlCommand(.bridge, .toggle), ControlCommand(.main, .hide), ControlCommand(.bridge, .toggle),
            ControlCommand(.main, .toggle), ControlCommand(.bridge, .hide),
        ]
        #expect(ControlURL.launchResolved(queued) == [
            ControlCommand(.bridge, .show), ControlCommand(.main, .hide), ControlCommand(.bridge, .toggle),
            ControlCommand(.main, .toggle), ControlCommand(.bridge, .hide),
        ])
        // An explicit first command is kept, and a toggle after it still toggles.
        #expect(ControlURL.launchResolved([ControlCommand(.bridge, .show), ControlCommand(.bridge, .toggle)])
            == [ControlCommand(.bridge, .show), ControlCommand(.bridge, .toggle)])
    }
}
