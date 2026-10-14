@testable import BridgeControl
import Foundation
import Testing

/// UTF-8 bytes of a JSON literal.
func datagram(_ json: String) -> Data { Data(json.utf8) }

/// Parses encoded output generically, to check exact keys and explicit nulls.
func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite struct ControlCodecTests {
    // MARK: ctl.sub

    @Test func subscribeWithPortAndClient() throws {
        let request = try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl.sub","port":51234,"client":"streamdeck"}"#))
        #expect(request == .subscribe(port: 51234, client: "streamdeck"))
    }

    @Test func subscribeWithoutPortUsesTheSender() throws {
        #expect(try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl.sub"}"#)) == .subscribe(port: nil, client: nil))
    }

    @Test func subscribeIgnoresUnknownFieldsAndABadClient() throws {
        let request = try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl.sub","port":40000,"client":7,"extra":{"a":[1,2]}}"#))
        #expect(request == .subscribe(port: 40000, client: nil))
    }

    @Test(arguments: ["0", "65536", "-1", "\"51234\""])
    func subscribeRejectsABadPort(_ port: String) {
        #expect(throws: ControlCodecError.self) {
            try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl.sub","port":\#(port)}"#))
        }
    }

    // MARK: ctl

    @Test func commandOnMeansShowHideOrToggle() throws {
        #expect(try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl","op":"bridge","on":true}"#)) == .command(ControlCommand(.bridge, .show)))
        #expect(try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl","op":"main","on":false}"#)) == .command(ControlCommand(.main, .hide)))
        #expect(try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl","op":"bridge","on":null}"#)) == .command(ControlCommand(.bridge, .toggle)))
        #expect(try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl","op":"main"}"#)) == .command(ControlCommand(.main, .toggle)))
    }

    @Test(arguments: [
        #"{"v":1,"t":"ctl","op":"bridge","on":"yes"}"#,
        #"{"v":1,"t":"ctl","op":"bridge","on":1}"#,
        #"{"v":1,"t":"ctl","op":"volume","on":true}"#,
        #"{"v":1,"t":"ctl","op":"edit"}"#,
        #"{"v":1,"t":"ctl","on":true}"#,
        #"{"v":1,"t":"ctl","op":"BRIDGE"}"#,
    ])
    func invalidCommandsAreDropped(_ json: String) {
        #expect(throws: ControlCodecError.self) { try ControlCodec.decodeRequest(datagram(json)) }
    }

    // MARK: Envelope

    @Test func otherVersionsAndTypesAreDropped() {
        #expect(throws: ControlCodecError.unsupportedVersion(2)) {
            try ControlCodec.decodeRequest(datagram(#"{"v":2,"t":"ctl.sub","port":5000}"#))
        }
        #expect(throws: ControlCodecError.unsupportedVersion(nil)) {
            try ControlCodec.decodeRequest(datagram(#"{"t":"ctl.sub","port":5000}"#))
        }
        #expect(throws: ControlCodecError.unsupportedVersion(nil)) {
            try ControlCodec.decodeRequest(datagram(#"{"v":"1","t":"ctl.sub","port":5000}"#))
        }
        #expect(throws: ControlCodecError.unknownType("ctl.reboot")) {
            try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl.reboot"}"#))
        }
        // A client must not send ctl.state to the app.
        #expect(throws: ControlCodecError.unknownType("ctl.state")) {
            try ControlCodec.decodeRequest(datagram(#"{"v":1,"t":"ctl.state","bridge":true}"#))
        }
    }

    @Test func garbageAndOversizedDatagramsAreDropped() {
        #expect(throws: ControlCodecError.self) { try ControlCodec.decodeRequest(datagram("not json")) }
        #expect(throws: ControlCodecError.self) { try ControlCodec.decodeRequest(datagram("[1,2]")) }
        #expect(throws: ControlCodecError.self) { try ControlCodec.decodeRequest(Data()) }
        let padding = String(repeating: "x", count: 2100)
        let big = #"{"v":1,"t":"ctl.sub","port":5000,"client":"\#(padding)"}"#
        #expect(throws: ControlCodecError.oversized(big.utf8.count)) { try ControlCodec.decodeRequest(datagram(big)) }
        // Just under 2 KB is fine.
        let fits = #"{"v":1,"t":"ctl.sub","port":5000,"client":"\#(String(repeating: "x", count: 1990))"}"#
        #expect(fits.utf8.count < 2048)
        #expect(throws: Never.self) { try ControlCodec.decodeRequest(datagram(fits)) }
    }

    // MARK: ctl.state

    @Test func stateHasExactlyTheDocumentedFields() throws {
        let state = ControlState(bridge: true, main: false, edit: false, source: "live", connected: true, app: "0.2.0")
        let data = ControlCodec.encode(state)
        let object = try jsonObject(data)
        #expect(Set(object.keys) == ["v", "t", "bridge", "main", "edit", "source", "connected", "app"])
        #expect(object["v"] as? Int == 1)
        #expect(object["t"] as? String == "ctl.state")
        #expect(object["bridge"] as? Bool == true)
        #expect(object["main"] as? Bool == false)
        #expect(object["source"] as? String == "live")
        #expect(object["app"] as? String == "0.2.0")
        #expect(data.count < ControlProtocol.maxDatagramSize)
        #expect(!String(decoding: data, as: UTF8.self).contains(" "))
        #expect(try ControlCodec.decodeState(data) == state)
    }

    @Test func theDocumentedStateExampleDecodes() throws {
        let example = #"{"v":1,"t":"ctl.state","bridge":true,"main":true,"edit":false,"source":"live","connected":true,"app":"0.1.0"}"#
        let state = try ControlCodec.decodeState(datagram(example))
        #expect(state == ControlState(bridge: true, main: true, edit: false, source: "live", connected: true, app: "0.1.0"))
    }

    @Test func requestsRoundTripAndAToggleSendsAnExplicitNull() throws {
        let requests: [ControlRequest] = [
            .subscribe(port: 51234, client: "streamdeck"),
            .subscribe(port: nil, client: nil),
            .command(ControlCommand(.bridge, .toggle)),
            .command(ControlCommand(.bridge, .show)),
            .command(ControlCommand(.main, .hide)),
        ]
        for request in requests {
            #expect(try ControlCodec.decodeRequest(ControlCodec.encode(request)) == request)
        }
        let toggle = try jsonObject(ControlCodec.encode(.command(ControlCommand(.main, .toggle))))
        #expect(toggle["on"] is NSNull)
        #expect(toggle["op"] as? String == "main")
    }

    // MARK: Semantics

    @Test func actionsResolveAgainstTheCurrentValue() {
        #expect(ControlAction.toggle.resolve(current: true) == false)
        #expect(ControlAction.toggle.resolve(current: false) == true)
        #expect(ControlAction.show.resolve(current: false) == true)
        #expect(ControlAction.show.resolve(current: true) == true)
        #expect(ControlAction.hide.resolve(current: true) == false)
        #expect(ControlAction.hide.resolve(current: false) == false)
        for action in ControlAction.allCases {
            #expect(ControlAction(on: action.on) == action)
        }
    }

    @Test func stateReadsEachSwitch() {
        let state = ControlState(bridge: true, main: false, edit: true, source: "simulator", connected: true, app: "0.2.0")
        #expect(state.value(of: .bridge))
        #expect(!state.value(of: .main))
        #expect(state.value(of: .edit))
    }

    @Test func commandsResolveAgainstTheirOwnSwitch() {
        let state = ControlState(bridge: false, main: true, edit: false, source: "live", connected: false, app: "0.2.0")
        #expect(ControlCommand(.bridge, .toggle).newValue(in: state) == true)
        #expect(ControlCommand(.main, .toggle).newValue(in: state) == false)
        #expect(ControlCommand(.edit, .toggle).newValue(in: state) == true)
        #expect(ControlCommand(.main, .show).newValue(in: state) == true)
        #expect(ControlCommand(.bridge, .hide).newValue(in: state) == false)
        // The switches are independent: showing the bridge doesn't change what "main" toggles to.
        var shownBridge = state
        shownBridge.bridge = true
        #expect(ControlCommand(.main, .toggle).newValue(in: shownBridge) == false)
        #expect(ControlCommand(.bridge, .toggle).newValue(in: shownBridge) == false)
    }
}
