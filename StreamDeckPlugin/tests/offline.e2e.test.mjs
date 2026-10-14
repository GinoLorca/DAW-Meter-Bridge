// End to end, with the app stopped or going away: bin/plugin.js against a fake Stream Deck and a
// fake app that can be silent. The plugin runs with DAWMB_NO_LAUNCH=1, so "launching" only logs.

import assert from "node:assert/strict";
import { test } from "node:test";
import { delay } from "./helpers/wait.mjs";
import {
    BRIDGE_ACTION, MAIN_ACTION, isCommand, isSetState, isShowAlert, startHarness,
} from "./helpers/harness.mjs";

const isLaunchLog = (message) => message.event === "logMessage"
    && /open -g -b com\.ginolorca\.DAWMeterBridge/.test(message.payload?.message ?? "");
const isSkippedLaunchLog = (message) => isLaunchLog(message) && /DAWMB_NO_LAUNCH/.test(message.payload.message);

test("keys fall back to state 0 when the app stops answering for 5 s", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true, main: true } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    const main = harness.appear(MAIN_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 1));
    await harness.streamDeck.waitFor(isSetState(main, 1));

    harness.app.respond = false;
    const silentAt = Date.now();
    const before = harness.streamDeck.mark();
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { from: before, timeoutMs: 7500, label: "bridge -> 0" });
    await harness.streamDeck.waitFor(isSetState(main, 0), { from: before, timeoutMs: 500, label: "main -> 0" });
    const elapsed = Date.now() - silentAt;
    assert.ok(elapsed >= 2500, `went offline after ${elapsed} ms of silence; expected about 3-5 s`);

    // It keeps subscribing, so the keys come back when the app does.
    harness.app.respond = true;
    await harness.streamDeck.waitFor(isSetState(bridge, 1), { from: before, timeoutMs: 3500, label: "bridge back to 1" });
    await harness.streamDeck.waitFor(isSetState(main, 1), { from: before, timeoutMs: 500, label: "main back to 1" });
});

test("when the app is not running at startup the keys show state 0 quickly", async (t) => {
    const harness = await startHarness({ app: { respond: false } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION, { state: 1 });
    const main = harness.appear(MAIN_ACTION, { state: 1 });
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { timeoutMs: 2500 });
    await harness.streamDeck.waitFor(isSetState(main, 0), { timeoutMs: 500 });
});

test("bridge pressed while offline launches the app, then turns the bridge on once", async (t) => {
    const harness = await startHarness({ app: { respond: false, state: { bridge: false, main: false } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { timeoutMs: 2500, label: "offline -> 0" });

    harness.press(BRIDGE_ACTION, bridge);
    await harness.streamDeck.waitFor(isLaunchLog, { label: "the launch (open -g -b ...)" });
    await harness.streamDeck.waitFor(isSkippedLaunchLog, { label: "the skipped launch (DAWMB_NO_LAUNCH)" });
    assert.match(harness.logText(), /launch skipped \(DAWMB_NO_LAUNCH=1\): open -g -b com\.ginolorca\.DAWMeterBridge/);

    // While it waits for the app it subscribes every 500 ms instead of every 2 s.
    const waiting = harness.app.mark();
    await delay(1300);
    const subs = harness.app.since(waiting, (message) => message.t === "ctl.sub");
    assert.ok(subs.length >= 2, `${subs.length} ctl.sub in 1.3 s`);

    // The app comes up with the bridge hidden.
    const appStartedAt = harness.app.mark();
    harness.app.respond = true;
    const turnOn = await harness.app.waitFor(isCommand("bridge", true), { from: appStartedAt, timeoutMs: 2000, label: "ctl bridge on:true" });
    assert.equal(turnOn.v, 1);
    await harness.streamDeck.waitFor(isSetState(bridge, 1), { label: "bridge -> 1" });

    await delay(2500);
    const commands = harness.app.since(0, (message) => message.t === "ctl");
    assert.equal(commands.length, 1, JSON.stringify(commands));
    assert.equal(harness.streamDeck.since(0, isShowAlert(bridge)).length, 0);
});

test("after a launch, on:true is sent only once even if the bridge stays hidden", async (t) => {
    const harness = await startHarness({ app: { respond: false, applyCommands: false, state: { bridge: false } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { timeoutMs: 2500 });
    harness.press(BRIDGE_ACTION, bridge);
    await harness.streamDeck.waitFor(isLaunchLog);
    harness.app.respond = true;
    await harness.app.waitFor(isCommand("bridge", true), { timeoutMs: 2000 });

    await delay(4500); // two more keep-alive answers, both with bridge:false
    assert.equal(harness.app.since(0, (message) => message.t === "ctl").length, 1);
});

test("after a launch, nothing is sent when the app comes up with the bridge already shown", async (t) => {
    const harness = await startHarness({ app: { respond: false, state: { bridge: true } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { timeoutMs: 2500 });
    harness.press(BRIDGE_ACTION, bridge);
    await harness.streamDeck.waitFor(isLaunchLog);
    harness.app.respond = true;
    await harness.streamDeck.waitFor(isSetState(bridge, 1), { timeoutMs: 2000 });

    await delay(700);
    assert.deepEqual(harness.app.since(0, (message) => message.t === "ctl"), []);
});

test("main pressed while offline shows an alert and sends nothing", async (t) => {
    const harness = await startHarness({ app: { respond: false } });
    t.after(() => harness.close());

    const main = harness.appear(MAIN_ACTION);
    await harness.streamDeck.waitFor(isSetState(main, 0), { timeoutMs: 2500 });

    harness.press(MAIN_ACTION, main);
    await harness.streamDeck.waitFor(isShowAlert(main), { label: "showAlert on the main key" });
    await delay(300);
    assert.deepEqual(harness.app.since(0, (message) => message.t === "ctl"), []);
    assert.equal(harness.streamDeck.since(0, isLaunchLog).length, 0, "main never launches the app");
});

test("Stream Deck reporting that the app quit turns the keys off at once", async (t) => {
    const harness = await startHarness({ app: { state: { bridge: true } } });
    t.after(() => harness.close());

    const bridge = harness.appear(BRIDGE_ACTION);
    await harness.streamDeck.waitFor(isSetState(bridge, 1));

    harness.app.respond = false;
    const before = harness.streamDeck.mark();
    harness.streamDeck.send({ event: "applicationDidTerminate", payload: { application: "com.ginolorca.DAWMeterBridge" } });
    await harness.streamDeck.waitFor(isSetState(bridge, 0), { from: before, timeoutMs: 1000 });
});
