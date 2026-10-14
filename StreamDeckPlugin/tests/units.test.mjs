// In-process tests: argument parsing, the rotating log, and plugin behavior with short timings
// (launch timeout, launch failure, unanswered commands) against the fake app.

import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { FakeApp } from "./helpers/fake-app.mjs";
import { decodeFrame, encodeFrame } from "./helpers/fake-streamdeck.mjs";
import { BRIDGE_ACTION, MAIN_ACTION } from "./helpers/harness.mjs";
import { delay, waitForMessage } from "./helpers/wait.mjs";
import { AppLink } from "../com.ginolorca.dawmeterbridge.sdPlugin/bin/lib/app-link.js";
import {
    controlPortFromEnv, launchDisabledFromEnv, parseRegistrationArgs,
} from "../com.ginolorca.dawmeterbridge.sdPlugin/bin/lib/args.js";
import { MeterBridgePlugin } from "../com.ginolorca.dawmeterbridge.sdPlugin/bin/lib/bridge-plugin.js";
import { FileLogger } from "../com.ginolorca.dawmeterbridge.sdPlugin/bin/lib/logger.js";

const quietLog = { debug() {}, info() {}, warn() {}, error() {} };

// MARK: arguments

test("parses Stream Deck's registration arguments", () => {
    const info = { application: { version: "7.4.2" } };
    const parsed = parseRegistrationArgs([
        "-port", "28196", "-pluginUUID", "com.ginolorca.dawmeterbridge",
        "-registerEvent", "registerPlugin", "-info", JSON.stringify(info),
    ]);
    assert.deepEqual(parsed, {
        port: 28196, pluginUUID: "com.ginolorca.dawmeterbridge", registerEvent: "registerPlugin", info,
    });
});

test("names the missing registration arguments", () => {
    assert.throws(() => parseRegistrationArgs(["-port", "1"]), /-pluginUUID, -registerEvent, -info/);
    assert.throws(
        () => parseRegistrationArgs(["-port", "http", "-pluginUUID", "x", "-registerEvent", "r", "-info", "{}"]),
        /-port must be a port number/,
    );
});

test("tolerates -info that is not JSON", () => {
    const parsed = parseRegistrationArgs(["-port", "1", "-pluginUUID", "x", "-registerEvent", "r", "-info", "{oops"]);
    assert.equal(parsed.info, null);
});

test("reads DAWMB_CONTROL_PORT and DAWMB_NO_LAUNCH", () => {
    assert.equal(controlPortFromEnv({}), 47802);
    assert.equal(controlPortFromEnv({ DAWMB_CONTROL_PORT: "" }), 47802);
    assert.equal(controlPortFromEnv({ DAWMB_CONTROL_PORT: "50123" }), 50123);
    assert.throws(() => controlPortFromEnv({ DAWMB_CONTROL_PORT: "70000" }), /DAWMB_CONTROL_PORT/);
    assert.throws(() => controlPortFromEnv({ DAWMB_CONTROL_PORT: "12ab" }), /DAWMB_CONTROL_PORT/);
    assert.equal(launchDisabledFromEnv({ DAWMB_NO_LAUNCH: "1" }), true);
    assert.equal(launchDisabledFromEnv({ DAWMB_NO_LAUNCH: "0" }), false);
    assert.equal(launchDisabledFromEnv({}), false);
});

// MARK: log

test("the log starts a new file per run and rotates by size, keeping a few files", (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dawmb-log-"));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const files = () => fs.readdirSync(dir).sort();

    const first = new FileLogger({ dir, name: "p", maxBytes: 200, maxFiles: 3 });
    first.info("first run");
    assert.deepEqual(files(), ["p.0.log"]);

    const second = new FileLogger({ dir, name: "p", maxBytes: 200, maxFiles: 3 });
    second.info("second run");
    assert.deepEqual(files(), ["p.0.log", "p.1.log"]);
    assert.match(fs.readFileSync(path.join(dir, "p.1.log"), "utf8"), /INFO  first run/);

    for (let i = 0; i < 20; i += 1) {
        second.info(`line ${i} ${"x".repeat(40)}`);
    }
    assert.deepEqual(files(), ["p.0.log", "p.1.log", "p.2.log"]);
    for (const file of files()) {
        assert.ok(fs.statSync(path.join(dir, file)).size <= 200, `${file} is too big`);
    }
    second.debug("not written at info level");
    assert.doesNotMatch(fs.readFileSync(path.join(dir, "p.0.log"), "utf8"), /not written/);
});

test("warnings also go to the warning sink", (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dawmb-log-"));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const log = new FileLogger({ dir, name: "p" });
    const seen = [];
    log.onWarning = (level, message) => seen.push(`${level}: ${message}`);
    log.info("fine");
    log.warn("careful", { port: 1 });
    log.error(new Error("boom"));
    assert.equal(seen.length, 2);
    assert.equal(seen[0], "warn: careful { port: 1 }");
    assert.match(seen[1], /^error: Error: boom/);
});

// MARK: test helper sanity

test("the fake Stream Deck's frame codec round-trips short, medium and long payloads", () => {
    for (const size of [0, 5, 125, 126, 1000, 70_000]) {
        const payload = Buffer.alloc(size, 0x61);
        const frame = decodeFrame(encodeFrame(0x1, payload));
        assert.equal(frame.payload.length, size);
        assert.equal(frame.opcode, 0x1);
        assert.equal(frame.fin, true);
    }
    // A masked client frame: "Hi".
    const masked = Buffer.from([0x81, 0x82, 1, 2, 3, 4, 0x48 ^ 1, 0x69 ^ 2]);
    assert.equal(decodeFrame(masked).payload.toString(), "Hi");
    assert.equal(decodeFrame(masked.subarray(0, 5)), null);
});

// MARK: plugin behavior with short timings

class RecordingStreamDeck extends EventEmitter {
    constructor() {
        super();
        this.messages = [];
    }

    record(message) {
        this.messages.push(message);
        this.emit("message", message);
    }

    setState(context, state) {
        this.record({ event: "setState", context, payload: { state } });
    }

    showAlert(context) {
        this.record({ event: "showAlert", context });
    }

    logMessage(message) {
        this.record({ event: "logMessage", payload: { message } });
    }

    waitFor(predicate, options) {
        return waitForMessage(this, this.messages, predicate, options);
    }
}

const SHORT_TIMING = {
    keepAliveMs: 200, fastKeepAliveMs: 50, offlineMs: 1000, probeMs: 150,
    launchTimeoutMs: 400, commandTimeoutMs: 250, rebindMs: 50,
};

async function startInProcess(t, { app: appOptions = {}, launch } = {}) {
    const fakeApp = new FakeApp(appOptions);
    await fakeApp.start();
    const streamDeck = new RecordingStreamDeck();
    const link = new AppLink({ port: fakeApp.port, log: quietLog, timing: SHORT_TIMING });
    const launches = [];
    const launcher = {
        command: ["open", "-g", "-b", "com.ginolorca.DAWMeterBridge"],
        launch() {
            launches.push(Date.now());
            return launch ? launch() : Promise.resolve({ skipped: true });
        },
    };
    const plugin = new MeterBridgePlugin({ streamDeck, app: link, launcher, log: quietLog, timing: SHORT_TIMING });
    link.start();
    t.after(async () => {
        plugin.dispose();
        link.stop();
        await fakeApp.stop();
    });
    const appear = (action, context, state = 0) => plugin.handleEvent({
        action, event: "willAppear", context, payload: { state, isInMultiAction: false },
    });
    const press = (action, context, payload = {}) => plugin.handleEvent({
        action, event: "keyUp", context, payload: { state: 0, isInMultiAction: false, ...payload },
    });
    return { fakeApp, streamDeck, link, plugin, launches, appear, press };
}

const setState = (context, state) => (message) => message.event === "setState"
    && message.context === context && message.payload.state === state;
const alertOn = (context) => (message) => message.event === "showAlert" && message.context === context;

test("an offline bridge press shows an alert when the app never comes online", async (t) => {
    const { streamDeck, appear, press, launches } = await startInProcess(t, { app: { respond: false } });
    appear(BRIDGE_ACTION, "k1", 1);
    await streamDeck.waitFor(setState("k1", 0), { timeoutMs: 1000 });

    const pressedAt = Date.now();
    press(BRIDGE_ACTION, "k1");
    await streamDeck.waitFor(alertOn("k1"), { timeoutMs: 1500, label: "alert after the launch timeout" });
    assert.ok(Date.now() - pressedAt >= 350, "the alert waits for the launch timeout");
    assert.equal(launches.length, 1);

    // A later press tries again.
    press(BRIDGE_ACTION, "k1");
    assert.equal(launches.length, 2);
});

test("an offline bridge press shows an alert at once when open fails", async (t) => {
    const { streamDeck, appear, press } = await startInProcess(t, {
        app: { respond: false },
        launch: () => Promise.reject(new Error("Unable to find application with identifier")),
    });
    appear(BRIDGE_ACTION, "k1");
    await streamDeck.waitFor(setState("k1", 0), { timeoutMs: 1000 });

    const pressedAt = Date.now();
    press(BRIDGE_ACTION, "k1");
    await streamDeck.waitFor(alertOn("k1"), { timeoutMs: 300 });
    assert.ok(Date.now() - pressedAt < 300);
});

test("a second bridge press while the app is starting does not launch again", async (t) => {
    const { streamDeck, appear, press, launches } = await startInProcess(t, { app: { respond: false } });
    appear(BRIDGE_ACTION, "k1");
    await streamDeck.waitFor(setState("k1", 0), { timeoutMs: 1000 });
    press(BRIDGE_ACTION, "k1");
    press(BRIDGE_ACTION, "k1");
    assert.equal(launches.length, 1);
});

test("a press the app does not answer shows an alert", async (t) => {
    const { fakeApp, streamDeck, appear, press } = await startInProcess(t, { app: { state: { main: false } } });
    appear(MAIN_ACTION, "m1");
    await streamDeck.waitFor(setState("m1", 0), { timeoutMs: 1000 });
    await delay(50);

    fakeApp.respond = false;
    press(MAIN_ACTION, "m1");
    await streamDeck.waitFor(alertOn("m1"), { timeoutMs: 800, label: "alert after the command timeout" });
    await fakeApp.waitFor((message) => message.t === "ctl" && message.op === "main" && message.on === null);
});

test("a press before the app's status is known waits for it", async (t) => {
    const { fakeApp, streamDeck, plugin, press } = await startInProcess(t, { app: { state: { bridge: false } } });
    assert.equal(plugin.app.status, "unknown");
    press(BRIDGE_ACTION, "k1");
    await fakeApp.waitFor((message) => message.t === "ctl" && message.op === "bridge" && message.on === null, { timeoutMs: 1000 });
    await delay(350);
    assert.deepEqual(streamDeck.messages.filter(alertOn("k1")), []);
});

test("keys follow the app across an app restart", async (t) => {
    const { fakeApp, streamDeck, appear } = await startInProcess(t, { app: { state: { bridge: true } } });
    appear(BRIDGE_ACTION, "k1");
    await streamDeck.waitFor(setState("k1", 1), { timeoutMs: 1000 });

    fakeApp.respond = false;
    const from = streamDeck.messages.length;
    await streamDeck.waitFor(setState("k1", 0), { from, timeoutMs: 2000, label: "offline" });

    fakeApp.state.bridge = true;
    fakeApp.respond = true;
    await streamDeck.waitFor(setState("k1", 1), { from, timeoutMs: 1000, label: "online again" });
});
