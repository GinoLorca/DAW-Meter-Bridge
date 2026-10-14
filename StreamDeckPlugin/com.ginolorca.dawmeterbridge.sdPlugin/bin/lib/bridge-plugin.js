// The plugin's behavior (docs/CONTROL.md, "Stream Deck plugin"):
// - key states follow the app's ctl.state; while the app is offline both keys show state 0,
// - pressing a key sends the matching ctl toggle,
// - pressing "bridge" while the app is offline launches it and then turns the bridge on once,
// - pressing "main" while the app is offline shows an alert.
//
// Stream Deck I/O, the UDP link and the launcher are passed in, so tests can replace them.

import { ACTION_SWITCHES, APP_BUNDLE_ID, TIMING } from "./constants.js";

export class MeterBridgePlugin {
    /**
     * @param {object} options
     * @param {{setState: Function, showAlert: Function, logMessage: Function}} options.streamDeck
     * @param {import("./app-link.js").AppLink} options.app
     * @param {{launch: () => Promise<{skipped: boolean}>, command?: string[]}} options.launcher
     * @param {{debug: Function, info: Function, warn: Function, error: Function}} options.log
     * @param {Partial<typeof TIMING>} [options.timing]
     */
    constructor({ streamDeck, app, launcher, log, timing = {} }) {
        this.streamDeck = streamDeck;
        this.app = app;
        this.launcher = launcher;
        this.log = log;
        this.timing = { ...TIMING, ...timing };

        /** Visible keys: context -> {op, inMultiAction, shown}. `shown` is the state Stream Deck shows. */
        this.keys = new Map();
        /** The launch started by an offline "bridge" press: {context, timer, done}. */
        this.launch = null;
        /** Presses waiting for a ctl.state answer: timer -> context. */
        this.pendingCommands = new Map();
        /** Presses made before the app's status is known (the first 1.5 s). */
        this.deferredPresses = [];

        this.app.on("status", (status, previous) => this.onAppStatus(status, previous));
        this.app.on("state", (state, changed) => this.onAppState(state, changed));
    }

    /** Handles one message from Stream Deck. */
    handleEvent(message) {
        switch (message.event) {
        case "willAppear":
            this.onWillAppear(message);
            break;
        case "willDisappear":
            this.keys.delete(message.context);
            break;
        case "keyUp":
            this.onKeyUp(message);
            break;
        case "applicationDidLaunch":
            if (message.payload?.application === APP_BUNDLE_ID) {
                this.log.info("Stream Deck reports that the app started");
                this.app.boost(this.timing.launchTimeoutMs);
            }
            break;
        case "applicationDidTerminate":
            if (message.payload?.application === APP_BUNDLE_ID) {
                this.app.markOffline("Stream Deck reports that the app quit");
            }
            break;
        case "systemDidWakeUp":
            this.log.info("system woke up");
            this.app.subscribe();
            break;
        default:
            this.log.debug(`ignored Stream Deck event "${message.event}"`);
        }
    }

    dispose() {
        for (const timer of this.pendingCommands.keys()) {
            clearTimeout(timer);
        }
        this.pendingCommands.clear();
        if (this.launch !== null) {
            clearTimeout(this.launch.timer);
            this.launch = null;
        }
    }

    // MARK: Stream Deck events

    onWillAppear({ action, context, payload = {} }) {
        const op = ACTION_SWITCHES[action];
        if (op === undefined || typeof context !== "string") {
            this.log.debug(`ignored willAppear for "${action}"`);
            return;
        }
        const key = {
            op,
            inMultiAction: payload.isInMultiAction === true,
            shown: typeof payload.state === "number" ? payload.state : null,
        };
        this.keys.set(context, key);
        this.render(context, key, { force: true });
    }

    onKeyUp({ action, context, payload = {} }) {
        const op = ACTION_SWITCHES[action];
        if (op === undefined || typeof context !== "string") {
            return;
        }
        const key = this.keys.get(context);
        if (key !== undefined && typeof payload.state === "number") {
            key.shown = payload.state;
        }
        // In a multi-action the user picks the state the key should end in (0 = hidden, 1 = shown).
        const on = payload.isInMultiAction === true && typeof payload.userDesiredState === "number"
            ? payload.userDesiredState === 1
            : null;
        this.press(context, op, on);
    }

    // MARK: pressing

    /**
     * @param {string} context
     * @param {"bridge" | "main"} op
     * @param {boolean | null} on null = toggle
     */
    press(context, op, on) {
        switch (this.app.status) {
        case "unknown":
            this.log.info(`${op} pressed before the app answered: waiting for it`);
            this.deferredPresses.push({ context, op, on });
            break;
        case "online":
            this.sendCommand(context, op, on);
            break;
        default:
            this.pressWhileOffline(context, op, on);
        }
    }

    pressWhileOffline(context, op, on) {
        if (on === false) {
            this.log.info(`${op} off requested while the app is not running: nothing to do`);
        } else if (op === "bridge") {
            this.startLaunch(context);
        } else {
            this.alert(context, "Main meter pressed while DAW Meter Bridge is not running");
        }
    }

    sendCommand(context, op, on) {
        if (!this.app.command(op, on)) {
            this.alert(context, "the control socket is not ready");
            return;
        }
        const timer = setTimeout(() => {
            this.pendingCommands.delete(timer);
            this.alert(context, `the app did not answer the ${op} command`);
        }, this.timing.commandTimeoutMs);
        this.pendingCommands.set(timer, context);
    }

    startLaunch(context) {
        if (this.launch !== null) {
            this.log.info("bridge pressed while the app is starting: ignored");
            return;
        }
        const launch = { context, timer: null, done: false };
        this.launch = launch;
        launch.timer = setTimeout(
            () => this.finishLaunch(launch, `the app did not come online within ${this.timing.launchTimeoutMs / 1000} s`),
            this.timing.launchTimeoutMs,
        );
        this.app.boost(this.timing.launchTimeoutMs);

        const command = (this.launcher.command ?? ["open"]).join(" ");
        this.streamDeck.logMessage(`bridge pressed while the app is not running: ${command}`);
        this.launcher.launch().then(
            (result) => {
                if (result?.skipped) {
                    this.streamDeck.logMessage(`launch skipped (DAWMB_NO_LAUNCH=1): ${command}`);
                }
            },
            (error) => this.finishLaunch(launch, error.message),
        );
    }

    /** Ends `launch`; with a failure message, the pressed key shows an alert. */
    finishLaunch(launch, failure) {
        if (launch.done) {
            return;
        }
        launch.done = true;
        clearTimeout(launch.timer);
        if (this.launch === launch) {
            this.launch = null;
        }
        if (failure) {
            this.alert(launch.context, failure);
        }
    }

    alert(context, reason) {
        this.log.warn(reason);
        this.streamDeck.showAlert(context);
    }

    // MARK: app updates

    onAppStatus(status, previous) {
        this.log.info(`app ${previous} -> ${status}`);
        this.streamDeck.logMessage(status === "online" ? "app online" : "app offline");
        this.renderAll({ force: true });
        if (previous === "unknown" && this.deferredPresses.length > 0) {
            const presses = this.deferredPresses;
            this.deferredPresses = [];
            // After the "state" event that comes with this status change has been handled.
            queueMicrotask(() => {
                for (const { context, op, on } of presses) {
                    this.press(context, op, on);
                }
            });
        }
    }

    onAppState(state, changed) {
        for (const timer of this.pendingCommands.keys()) {
            clearTimeout(timer);
        }
        this.pendingCommands.clear();

        const launch = this.launch;
        if (launch !== null && !launch.done) {
            this.finishLaunch(launch, null);
            if (state.bridge === true) {
                this.log.info("the app is up and the bridge is already shown");
            } else {
                // The offline press meant "turn the bridge on". Sent once.
                this.log.info("the app is up with the bridge hidden: turning it on");
                this.sendCommand(launch.context, "bridge", true);
            }
        }

        if (changed) {
            this.renderAll();
        }
    }

    // MARK: key states

    /** The state the keys for `op` should show, or null while the app's status is unknown. */
    desiredState(op) {
        switch (this.app.status) {
        case "online":
            return this.app.state?.[op] === true ? 1 : 0;
        case "offline":
            return 0;
        default:
            return null;
        }
    }

    /** Updates every visible key; with `force`, also keys that already show the right state. */
    renderAll({ force = false } = {}) {
        for (const [context, key] of this.keys) {
            this.render(context, key, { force });
        }
    }

    render(context, key, { force }) {
        if (key.inMultiAction) {
            return; // Keys inside a multi-action are not on screen.
        }
        const desired = this.desiredState(key.op);
        if (desired === null) {
            return;
        }
        if (force || key.shown !== desired) {
            this.streamDeck.setState(context, desired);
            key.shown = desired;
        }
    }
}
