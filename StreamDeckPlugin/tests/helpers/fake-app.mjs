// A fake DAW Meter Bridge control endpoint (docs/CONTROL.md) on an ephemeral UDP port on 127.0.0.1.
// It records every datagram, answers ctl.sub and ctl like the app, and can be made silent to
// simulate an app that is not running.

import dgram from "node:dgram";
import { EventEmitter } from "node:events";
import { waitForMessage } from "./wait.mjs";

export class FakeApp extends EventEmitter {
    /**
     * @param {object} [options]
     * @param {boolean} [options.respond] answer messages (false = behave like a stopped app)
     * @param {boolean} [options.applyCommands] change the state on ctl commands
     * @param {object} [options.state] initial ctl.state fields
     */
    constructor({ respond = true, applyCommands = true, state = {} } = {}) {
        super();
        this.respond = respond;
        this.applyCommands = applyCommands;
        this.state = { bridge: true, main: false, edit: false, source: "simulator", connected: true, app: "0.0.0-test", ...state };
        /** Every JSON message received, in order. */
        this.messages = [];
        /** Subscriber ports from ctl.sub. */
        this.subscribers = new Set();
        this.socket = null;
        this.port = null;
    }

    async start() {
        this.socket = dgram.createSocket("udp4");
        this.socket.on("message", (data, remote) => this.onDatagram(data, remote));
        await new Promise((resolve, reject) => {
            this.socket.once("error", reject);
            this.socket.bind(0, "127.0.0.1", () => {
                this.socket.off("error", reject);
                resolve();
            });
        });
        this.port = this.socket.address().port;
        return this.port;
    }

    async stop() {
        if (this.socket) {
            await new Promise((resolve) => this.socket.close(resolve));
            this.socket = null;
        }
    }

    /** Changes state fields and pushes ctl.state to every subscriber (like a menu or hotkey change). */
    push(patch) {
        Object.assign(this.state, patch);
        for (const port of this.subscribers) {
            this.sendState(port);
        }
    }

    mark() {
        return this.messages.length;
    }

    since(from, predicate = () => true) {
        return this.messages.slice(from).filter(predicate);
    }

    waitFor(predicate, { from = 0, timeoutMs = 3000, label = "message to the app" } = {}) {
        return waitForMessage(this, this.messages, predicate, { from, timeoutMs, label });
    }

    onDatagram(data, remote) {
        let message;
        try {
            message = JSON.parse(data.toString("utf8"));
        } catch {
            return;
        }
        message.receivedFromPort = remote.port;
        this.messages.push(message);
        this.emit("message", message);
        if (!this.respond || message.v !== 1) {
            return;
        }
        if (message.t === "ctl.sub" && Number.isInteger(message.port)) {
            this.subscribers.add(message.port);
            this.sendState(message.port);
        } else if (message.t === "ctl") {
            if (this.applyCommands && (message.op === "bridge" || message.op === "main")) {
                this.state[message.op] = typeof message.on === "boolean" ? message.on : !this.state[message.op];
            }
            this.sendState(remote.port);
            for (const port of this.subscribers) {
                if (port !== remote.port) {
                    this.sendState(port);
                }
            }
        }
    }

    sendState(port) {
        const body = Buffer.from(JSON.stringify({ v: 1, t: "ctl.state", ...this.state }));
        this.socket?.send(body, port, "127.0.0.1");
    }
}
