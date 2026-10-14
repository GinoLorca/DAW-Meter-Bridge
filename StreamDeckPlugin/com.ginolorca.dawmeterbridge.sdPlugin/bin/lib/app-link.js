// The plugin's side of the app control protocol (docs/CONTROL.md): a UDP socket on 127.0.0.1
// that subscribes with `ctl.sub` every 2 s, sends `ctl` commands, and tracks `ctl.state`.
//
// Events:
//   "status" (status, previous)  status is "unknown" (just started), "online" or "offline"
//   "state"  (state, changed)    every ctl.state received; `changed` is true when a field differs
//                                from the last one (or the app just came online)

import dgram from "node:dgram";
import { EventEmitter } from "node:events";
import { CONTROL_PROTOCOL_VERSION, TIMING } from "./constants.js";

const STATE_FIELDS = Object.freeze({
    bridge: "boolean",
    main: "boolean",
    edit: "boolean",
    source: "string",
    connected: "boolean",
    app: "string",
});

const MAX_DATAGRAM_BYTES = 16 * 1024;

export class AppLink extends EventEmitter {
    /**
     * @param {object} options
     * @param {number} options.port the app's control port
     * @param {string} [options.host]
     * @param {string} [options.client] free text the app logs for this subscriber
     * @param {{debug: Function, info: Function, warn: Function, error: Function}} options.log
     * @param {Partial<typeof TIMING>} [options.timing]
     */
    constructor({ port, host = "127.0.0.1", client = "streamdeck", log, timing = {} }) {
        super();
        this.port = port;
        this.host = host;
        this.client = client;
        this.log = log;
        this.timing = { ...TIMING, ...timing };

        /** @type {"unknown" | "online" | "offline"} */
        this.status = "unknown";
        /** The last ctl.state, with only known fields (a missing field is undefined). Null while not online. */
        this.state = null;
        this.localPort = null;

        this.socket = null;
        this.stopped = false;
        this.keepAliveTimer = null;
        this.keepAliveMs = this.timing.keepAliveMs;
        this.offlineTimer = null;
        this.probeTimer = null;
        this.boostTimer = null;
        this.rebindTimer = null;
    }

    start() {
        this.stopped = false;
        this.bind();
    }

    stop() {
        this.stopped = true;
        for (const timer of [this.offlineTimer, this.probeTimer, this.boostTimer, this.rebindTimer]) {
            clearTimeout(timer);
        }
        clearInterval(this.keepAliveTimer);
        this.keepAliveTimer = null;
        this.closeSocket();
    }

    /** Sends `ctl.sub` now (the app answers with `ctl.state`). */
    subscribe() {
        if (this.localPort === null) {
            return false;
        }
        return this.send({ v: CONTROL_PROTOCOL_VERSION, t: "ctl.sub", port: this.localPort, client: this.client });
    }

    /**
     * Sends a `ctl` command.
     * @param {"bridge" | "main"} op
     * @param {boolean | null} on true = show, false = hide, null = toggle
     * @returns {boolean} false when the socket is not ready
     */
    command(op, on = null) {
        const message = { v: CONTROL_PROTOCOL_VERSION, t: "ctl", op, on: typeof on === "boolean" ? on : null };
        this.log.info(`-> app: ${JSON.stringify(message)}`);
        return this.send(message);
    }

    /**
     * Subscribes every 500 ms instead of every 2 s until a `ctl.state` arrives or `durationMs`
     * passes, so a key reacts quickly when the app has just been started.
     */
    boost(durationMs) {
        clearTimeout(this.boostTimer);
        this.boostTimer = setTimeout(() => this.endBoost(), durationMs);
        this.setKeepAlivePeriod(this.timing.fastKeepAliveMs);
        this.subscribe();
    }

    /** Marks the app offline now, for example when Stream Deck reports that it quit. */
    markOffline(reason) {
        clearTimeout(this.offlineTimer);
        clearTimeout(this.probeTimer);
        if (this.status !== "offline") {
            this.log.info(`app offline: ${reason}`);
            this.state = null;
            this.setStatus("offline");
        }
    }

    // MARK: socket

    bind() {
        if (this.stopped) {
            return;
        }
        const socket = dgram.createSocket({ type: "udp4" });
        let bound = false;
        socket.on("message", (data, remote) => this.onDatagram(data, remote));
        socket.on("error", (error) => {
            this.log.warn(`control socket error: ${error.message}`);
            if (socket === this.socket || !bound) {
                this.closeSocket(socket);
                this.scheduleRebind();
            }
        });
        socket.bind({ address: this.host, port: 0 }, () => {
            bound = true;
            if (this.stopped) {
                socket.close();
                return;
            }
            this.socket = socket;
            this.localPort = socket.address().port;
            this.log.info(`control socket on ${this.host}:${this.localPort}, app at ${this.host}:${this.port}`);
            this.subscribe();
            this.setKeepAlivePeriod(this.keepAliveMs);
            if (this.status === "unknown") {
                clearTimeout(this.probeTimer);
                this.probeTimer = setTimeout(() => {
                    if (this.status === "unknown") {
                        this.log.info("app offline: no answer to ctl.sub");
                        this.setStatus("offline");
                    }
                }, this.timing.probeMs);
            }
        });
    }

    closeSocket(socket = this.socket) {
        if (socket === null) {
            return;
        }
        if (socket === this.socket) {
            this.socket = null;
            this.localPort = null;
        }
        try {
            socket.close();
        } catch {
            // Already closed.
        }
    }

    scheduleRebind() {
        if (this.stopped) {
            return;
        }
        clearTimeout(this.rebindTimer);
        this.rebindTimer = setTimeout(() => this.bind(), this.timing.rebindMs);
    }

    send(message) {
        const socket = this.socket;
        if (socket === null) {
            return false;
        }
        const data = Buffer.from(JSON.stringify(message));
        try {
            socket.send(data, this.port, this.host, (error) => {
                if (error) {
                    this.log.debug(`send to ${this.host}:${this.port} failed: ${error.message}`);
                }
            });
        } catch (error) {
            this.log.warn(`control socket send failed: ${error.message}`);
            this.closeSocket(socket);
            this.scheduleRebind();
            return false;
        }
        return true;
    }

    setKeepAlivePeriod(periodMs) {
        this.keepAliveMs = periodMs;
        clearInterval(this.keepAliveTimer);
        this.keepAliveTimer = setInterval(() => this.subscribe(), periodMs);
    }

    endBoost() {
        clearTimeout(this.boostTimer);
        this.boostTimer = null;
        if (this.keepAliveMs !== this.timing.keepAliveMs) {
            this.setKeepAlivePeriod(this.timing.keepAliveMs);
        }
    }

    // MARK: receiving

    onDatagram(data, remote) {
        if (data.length > MAX_DATAGRAM_BYTES) {
            return;
        }
        let message;
        try {
            message = JSON.parse(data.toString("utf8"));
        } catch {
            this.log.debug(`ignored a datagram that is not JSON from ${remote.address}:${remote.port}`);
            return;
        }
        if (message === null || typeof message !== "object" || message.v !== CONTROL_PROTOCOL_VERSION) {
            return;
        }
        if (message.t !== "ctl.state") {
            this.log.debug(`ignored "${message.t}" from the app`);
            return;
        }
        this.onState(message);
    }

    onState(message) {
        const state = {};
        for (const [field, type] of Object.entries(STATE_FIELDS)) {
            state[field] = typeof message[field] === type ? message[field] : undefined;
        }

        const wasOnline = this.status === "online";
        const changed = !wasOnline || this.state === null
            || Object.keys(STATE_FIELDS).some((field) => this.state[field] !== state[field]);
        this.state = state;

        clearTimeout(this.probeTimer);
        clearTimeout(this.offlineTimer);
        this.offlineTimer = setTimeout(
            () => this.markOffline(`no ctl.state for ${this.timing.offlineMs / 1000} s`),
            this.timing.offlineMs,
        );
        if (this.boostTimer !== null) {
            this.endBoost();
        }

        if (changed) {
            this.log.info(`<- app: bridge=${state.bridge} main=${state.main} edit=${state.edit} `
                + `source=${state.source} connected=${state.connected} app=${state.app}`);
        }
        if (!wasOnline) {
            this.setStatus("online");
        }
        this.emit("state", state, changed);
    }

    setStatus(status) {
        const previous = this.status;
        if (previous === status) {
            return;
        }
        this.status = status;
        this.emit("status", status, previous);
    }
}
