// DAW Meter Bridge Stream Deck plugin: two keys that show/hide the bridge and its Main meter,
// and always show the app's real state. Runs on Stream Deck's bundled Node 24, no dependencies.
// Protocol: docs/CONTROL.md in the DAW Meter Bridge repository.
//
// Environment (for tests):
//   DAWMB_CONTROL_PORT=<n>  the app's control port (default 47802)
//   DAWMB_NO_LAUNCH=1       never run `open`, only log it
//   DAWMB_DEBUG=1           debug lines in the log

import path from "node:path";
import { fileURLToPath } from "node:url";
import { AppLink } from "./lib/app-link.js";
import { controlPortFromEnv, launchDisabledFromEnv, parseRegistrationArgs } from "./lib/args.js";
import { MeterBridgePlugin } from "./lib/bridge-plugin.js";
import { APP_BUNDLE_ID, PLUGIN_UUID, PLUGIN_VERSION } from "./lib/constants.js";
import { createLauncher } from "./lib/launcher.js";
import { FileLogger } from "./lib/logger.js";
import { StreamDeckConnection } from "./lib/streamdeck.js";

const pluginDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const log = new FileLogger({
    dir: path.join(pluginDir, "logs"),
    name: PLUGIN_UUID,
    level: process.env.DAWMB_DEBUG === "1" ? "debug" : "info",
});

let shuttingDown = false;
let cleanup = () => {};

function shutdown(code, reason) {
    if (shuttingDown) {
        return;
    }
    shuttingDown = true;
    log.info(`exiting (${reason})`);
    try {
        cleanup();
    } finally {
        process.exit(code);
    }
}

process.on("uncaughtException", (error) => {
    log.error("uncaught exception:", error);
    shutdown(1, "uncaught exception");
});
process.on("unhandledRejection", (reason) => {
    log.error("unhandled promise rejection:", reason);
});
process.on("SIGTERM", () => shutdown(0, "SIGTERM"));
process.on("SIGINT", () => shutdown(0, "SIGINT"));

function main() {
    let registration;
    let controlPort;
    try {
        registration = parseRegistrationArgs(process.argv.slice(2));
        controlPort = controlPortFromEnv(process.env);
    } catch (error) {
        log.error(`cannot start: ${error.message}`);
        process.stderr.write(`${error.message}\n`);
        process.exitCode = 1;
        return;
    }

    const streamDeckVersion = registration.info?.application?.version ?? "?";
    log.info(`DAW Meter Bridge plugin ${PLUGIN_VERSION} on Node ${process.versions.node}, `
        + `Stream Deck ${streamDeckVersion}, pid ${process.pid}`);

    const streamDeck = new StreamDeckConnection({
        port: registration.port,
        pluginUUID: registration.pluginUUID,
        registerEvent: registration.registerEvent,
        log,
    });
    const app = new AppLink({ port: controlPort, log });
    const launcher = createLauncher({
        bundleId: APP_BUNDLE_ID,
        disabled: launchDisabledFromEnv(process.env),
        log,
    });
    const plugin = new MeterBridgePlugin({ streamDeck, app, launcher, log });

    // Warnings also go to Stream Deck's own log.
    log.onWarning = (level, message) => streamDeck.logMessage(`${level}: ${message}`);

    streamDeck.on("event", (message) => {
        try {
            plugin.handleEvent(message);
        } catch (error) {
            log.error(`failed to handle "${message.event}":`, error);
        }
    });
    // Stream Deck closes the connection when it quits or unloads the plugin. Like the SDK, exit.
    streamDeck.on("close", ({ code, wasOpen }) => {
        shutdown(wasOpen ? 0 : 1, wasOpen ? `Stream Deck closed the connection (${code})` : "cannot connect to Stream Deck");
    });

    cleanup = () => {
        plugin.dispose();
        app.stop();
        streamDeck.close();
    };

    app.start();
    streamDeck.connect();
}

main();
