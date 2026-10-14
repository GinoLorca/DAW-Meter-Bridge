// End to end, with the app running: bin/plugin.js against a fake Stream Deck and a fake app.

import assert from "node:assert/strict";
import { test } from "node:test";
import { delay } from "./helpers/wait.mjs";
import {
    BRIDGE_ACTION, MAIN_ACTION, PLUGIN_UUID, isCommand, isSetState, startHarness,
} from "./helpers/harness.mjs";

test("registers with Stream Deck first", async (t) => {
    const harness = await startHarness();
    t.after(() => harness.close());

    const first = await harness.streamDeck.waitFor(() => true, { label: "the registration message" });
    assert.deepEqual(first, { event: "registerPlugin", uuid: PLUGIN_UUID });
    assert.deepEqual(harness.streamDeck.protocolErrors, []);
});

test("subscribes with ctl.sub from its own port and repeats it every 2 s", async (t) => {
    const harness = await startHarness();
    t.after(() => harness.close());

    const isSub = (message) => message.t === "ctl.sub";
    const first = await harness.app.waitFor(isSub, { label: "ctl.sub" });
    const firstAt = Date.now();
    assert.equal(first.v, 1);
    assert.equal(first.client, "streamdeck");
    assert.equal(first.port, first.receivedFromPort, "ctl.sub names the port it is sent from");

    await harness.app.waitFor(isSub, { from: harness.app.messages.indexOf(first) + 1, timeoutMs: 3500, label: "the keep-alive" });
    const gap = Date.now() - firstAt;
    assert.ok(gap >= 1500 && gap <= 3000, `keep-alive after ${gap} ms`);
});

test("willAppear sets each key to the app's state", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true, main: false } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION, { state: 0 });
    const main = harness.appear(MAIN_ACTION, { state: 1 });
    await harness.streamDeck.waitFor(isSetState(bridge, 1), { label: "bridge -> 1" });
    await harness.streamDeck.waitFor(isSetState(main, 0), { label: "main -> 0" });

    // A key that appears later (page or profile switch) is set at once, too.
    await harness.app.waitFor((message) => message.t === "ctl.sub");
    await delay(100);
    const later = harness.appear(MAIN_ACTION, { state: 0 });
    await harness.streamDeck.waitFor(isSetState(later, 0), { timeoutMs: 1000, label: "late main -> 0" });
});

test("pressing a key sends a ctl toggle and the key follows the answer", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true, main: false } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 1));

    const before = harness.streamDeck.mark();
    harness.press(BRIDGE_ACTION, bridge, { state: 1 });
    const command = await harness.app.waitFor(isCommand("bridge", null), { label: "ctl bridge toggle" });
    assert.deepEqual(
        { v: command.v, t: command.t, op: command.op, on: command.on },
        { v: 1, t: "ctl", op: "bridge", on: null },
    );
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { from: before, label: "bridge -> 0" });

    const main = harness.appear(MAIN_ACTION);
    await harness.streamDeck.waitFor(isSetState(main, 0));
    harness.press(MAIN_ACTION, main, { state: 0 });
    await harness.app.waitFor(isCommand("main", null), { label: "ctl main toggle" });
    await harness.streamDeck.waitFor(isSetState(main, 1), { label: "main -> 1" });

    // The press itself never flips the key: only the app's answer does.
    assert.equal(harness.streamDeck.since(before, (message) => message.event === "showAlert").length, 0);
});

test("a change made in the app (menu, hotkey) updates every visible key", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true, main: false } } });
    t.after(() => harness.close());

    const bridgeA = harness.appear(BRIDGE_ACTION);
    const bridgeB = harness.appear(BRIDGE_ACTION);
    const main = harness.appear(MAIN_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridgeA, 1));
    await harness.streamDeck.waitFor(isSetState(bridgeB, 1));
    await harness.streamDeck.waitFor(isSetState(main, 0));

    const before = harness.streamDeck.mark();
    harness.app.push({ bridge: false, main: true });
    await harness.streamDeck.waitFor(isSetState(bridgeA, 0), { from: before });
    await harness.streamDeck.waitFor(isSetState(bridgeB, 0), { from: before });
    await harness.streamDeck.waitFor(isSetState(main, 1), { from: before });

    // Keep-alive answers with the same state don't resend anything.
    const settled = harness.streamDeck.mark();
    await delay(2300);
    assert.deepEqual(harness.streamDeck.since(settled, (message) => message.event === "setState"), []);
});

test("keys that disappeared are no longer updated", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 1));
    harness.streamDeck.send({ action: BRIDGE_ACTION, event: "willDisappear", context: bridge, device: "DEVICE1", payload: {} });
    await delay(100);

    const before = harness.streamDeck.mark();
    harness.app.push({ bridge: false });
    await delay(400);
    assert.deepEqual(harness.streamDeck.since(before, isSetState(bridge)), []);
});

test("in a multi-action the chosen state is sent as an explicit on/off", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true, main: true } } });
    t.after(() => harness.close());
    await harness.app.waitFor((message) => message.t === "ctl.sub");
    await delay(100);

    const mainInMulti = harness.appear(MAIN_ACTION, { isInMultiAction: true });
    harness.press(MAIN_ACTION, mainInMulti, { isInMultiAction: true, userDesiredState: 0 });
    await harness.app.waitFor(isCommand("main", false), { label: "ctl main on:false" });

    const bridgeInMulti = harness.appear(BRIDGE_ACTION, { isInMultiAction: true });
    harness.press(BRIDGE_ACTION, bridgeInMulti, { isInMultiAction: true, userDesiredState: 1 });
    await harness.app.waitFor(isCommand("bridge", true), { label: "ctl bridge on:true" });

    // Keys inside a multi-action are not on screen: no setState for them.
    await delay(200);
    assert.deepEqual(harness.streamDeck.since(0, isSetState(mainInMulti)), []);
    assert.deepEqual(harness.streamDeck.since(0, isSetState(bridgeInMulti)), []);
});

test("writes its log to logs/ in the plugin folder", async (t) => {
    const harness = await startHarness();
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge));
    const log = harness.logText();
    assert.match(log, /DAW Meter Bridge plugin 0\.2\.0\.0 on Node/);
    assert.match(log, /registered with Stream Deck/);
    assert.match(log, /app unknown -> online/);
});

test("exits when Stream Deck closes the connection", async (t) => {
    const harness = await startHarness();
    t.after(() => harness.close());
    await harness.streamDeck.waitFor((message) => message.event === "registerPlugin");

    harness.streamDeck.closeConnection();
    const timeout = delay(3000).then(() => "still running");
    const result = await Promise.race([harness.exited, timeout]);
    assert.deepEqual(result, { code: 0, signal: null }, harness.output);
    assert.match(harness.logText(), /exiting \(Stream Deck closed the connection/);
});
