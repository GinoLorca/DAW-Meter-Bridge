// End-to-end harness: a fake Stream Deck, a fake app, and the real bin/plugin.js running as a child
// process from a temporary copy of the plugin folder (so its logs/ never land in the repository).
// The plugin always runs with DAWMB_NO_LAUNCH=1 and a control port that is not the app's real one.

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FakeApp } from "./fake-app.mjs";
import { FakeStreamDeck } from "./fake-streamdeck.mjs";

export const PLUGIN_UUID = "com.ginolorca.dawmeterbridge";
export const BRIDGE_ACTION = "com.ginolorca.dawmeterbridge.bridge";
export const MAIN_ACTION = "com.ginolorca.dawmeterbridge.main";
export const SOURCE_PLUGIN_DIR = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)), "..", "..", "com.ginolorca.dawmeterbridge.sdPlugin",
);

const REAL_CONTROL_PORT = 47802;

const INFO = {
    application: { font: ".AppleSystemUIFont", language: "en", platform: "mac", platformVersion: "26.4.0", version: "7.4.2.0" },
    plugin: { uuid: PLUGIN_UUID, version: "0.2.0.0" },
    devicePixelRatio: 2,
    devices: [{ id: "DEVICE1", name: "Stream Deck", size: { columns: 5, rows: 3 }, type: 0 }],
};

/**
 * Starts the fake Stream Deck, the fake app and the plugin.
 * @param {object} [options]
 * @param {ConstructorParameters<typeof FakeApp>[0]} [options.app] fake app options
 * @param {Record<string, string>} [options.env] extra environment for the plugin
 */
export async function startHarness({ app: appOptions = {}, env = {} } = {}) {
    const streamDeck = new FakeStreamDeck();
    const app = new FakeApp(appOptions);
    await streamDeck.start();
    await app.start();
    if (app.port === REAL_CONTROL_PORT) {
        throw new Error("the fake app must not use the real control port");
    }

    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "dawmb-streamdeck-"));
    const pluginDir = path.join(tempDir, `${PLUGIN_UUID}.sdPlugin`);
    fs.mkdirSync(pluginDir);
    fs.cpSync(path.join(SOURCE_PLUGIN_DIR, "bin"), path.join(pluginDir, "bin"), { recursive: true });
    fs.copyFileSync(path.join(SOURCE_PLUGIN_DIR, "manifest.json"), path.join(pluginDir, "manifest.json"));

    const child = spawn(process.execPath, [
        path.join(pluginDir, "bin", "plugin.js"),
        "-port", String(streamDeck.port),
        "-pluginUUID", PLUGIN_UUID,
        "-registerEvent", "registerPlugin",
        "-info", JSON.stringify(INFO),
    ], {
        env: { ...process.env, DAWMB_DEBUG: "1", ...env, DAWMB_CONTROL_PORT: String(app.port), DAWMB_NO_LAUNCH: "1" },
        stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    const exited = new Promise((resolve) => {
        child.on("exit", (code, signal) => resolve({ code, signal }));
    });

    await streamDeck.connected();

    const harness = {
        streamDeck,
        app,
        child,
        exited,
        pluginDir,
        get output() {
            return output;
        },
        /** The plugin's current log file. */
        logText() {
            try {
                return fs.readFileSync(path.join(pluginDir, "logs", `${PLUGIN_UUID}.0.log`), "utf8");
            } catch {
                return "";
            }
        },
        /** Sends willAppear for a key and returns its context. */
        appear(action, { context = `${action}#${Math.random().toString(16).slice(2)}`, state = 0, isInMultiAction = false } = {}) {
            streamDeck.send({
                action,
                event: "willAppear",
                context,
                device: "DEVICE1",
                payload: {
                    settings: {},
                    coordinates: isInMultiAction ? undefined : { column: 0, row: 0 },
                    controller: "Keypad",
                    state,
                    isInMultiAction,
                },
            });
            return context;
        },
        /** Sends keyDown + keyUp for a key. */
        press(action, context, { state = 0, isInMultiAction = false, userDesiredState } = {}) {
            for (const event of ["keyDown", "keyUp"]) {
                const payload = { settings: {}, state, isInMultiAction };
                if (!isInMultiAction) {
                    payload.coordinates = { column: 0, row: 0 };
                }
                if (userDesiredState !== undefined) {
                    payload.userDesiredState = userDesiredState;
                }
                streamDeck.send({ action, event, context, device: "DEVICE1", payload });
            }
        },
        async close() {
            if (child.exitCode === null && child.signalCode === null) {
                child.kill("SIGTERM");
                const timer = setTimeout(() => child.kill("SIGKILL"), 2000);
                await exited;
                clearTimeout(timer);
            }
            await streamDeck.stop();
            await app.stop();
            fs.rmSync(tempDir, { recursive: true, force: true });
        },
    };
    return harness;
}

/** Matches a setState message for `context`, optionally with a given state. */
export function isSetState(context, state) {
    return (message) => message.event === "setState" && message.context === context
        && (state === undefined || message.payload?.state === state);
}

export function isShowAlert(context) {
    return (message) => message.event === "showAlert" && message.context === context;
}

export function isCommand(op, on) {
    return (message) => message.t === "ctl" && message.op === op && Object.hasOwn(message, "on") && message.on === on;
}
