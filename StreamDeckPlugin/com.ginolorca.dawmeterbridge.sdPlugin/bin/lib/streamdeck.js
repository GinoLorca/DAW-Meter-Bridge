// The WebSocket connection to Stream Deck (SDK version 2), on Node's built-in WebSocket client.
//
// Events:
//   "open"                     registered with Stream Deck
//   "event" (message)          every JSON message Stream Deck sends
//   "close" ({code, wasOpen})  the connection closed (the plugin should exit)

import { EventEmitter } from "node:events";

const MAX_QUEUED = 200;

export class StreamDeckConnection extends EventEmitter {
    /**
     * @param {object} options
     * @param {number} options.port
     * @param {string} options.pluginUUID
     * @param {string} options.registerEvent
     * @param {{debug: Function, info: Function, warn: Function}} options.log
     */
    constructor({ port, pluginUUID, registerEvent, log }) {
        super();
        this.port = port;
        this.pluginUUID = pluginUUID;
        this.registerEvent = registerEvent;
        this.log = log;
        this.socket = null;
        this.isOpen = false;
        this.queue = [];
    }

    connect() {
        const url = `ws://127.0.0.1:${this.port}`;
        this.log.info(`connecting to Stream Deck at ${url}`);
        const socket = new WebSocket(url);
        this.socket = socket;

        socket.addEventListener("open", () => {
            this.isOpen = true;
            socket.send(JSON.stringify({ event: this.registerEvent, uuid: this.pluginUUID }));
            this.log.info("registered with Stream Deck");
            const queued = this.queue;
            this.queue = [];
            for (const text of queued) {
                socket.send(text);
            }
            this.emit("open");
        });

        socket.addEventListener("message", (event) => {
            if (typeof event.data !== "string") {
                return;
            }
            let message;
            try {
                message = JSON.parse(event.data);
            } catch {
                this.log.warn(`ignored a Stream Deck message that is not JSON: ${event.data.slice(0, 200)}`);
                return;
            }
            if (message !== null && typeof message === "object") {
                this.emit("event", message);
            }
        });

        socket.addEventListener("error", (event) => {
            const detail = event.message || event.error?.message || (this.isOpen ? "connection lost" : "cannot connect");
            this.log.warn(`Stream Deck connection error: ${detail}`);
        });

        socket.addEventListener("close", (event) => {
            const wasOpen = this.isOpen;
            this.isOpen = false;
            this.emit("close", { code: event.code, reason: event.reason, wasOpen });
        });
    }

    close() {
        try {
            this.socket?.close(1000);
        } catch {
            // Already closed.
        }
    }

    send(message) {
        const text = JSON.stringify(message);
        if (this.isOpen && this.socket?.readyState === WebSocket.OPEN) {
            this.socket.send(text);
        } else if (this.queue.length < MAX_QUEUED) {
            this.queue.push(text);
        }
    }

    /** Shows state `state` (0 or 1) on the key `context`. */
    setState(context, state) {
        this.send({ event: "setState", context, payload: { state } });
    }

    /** Shows the warning triangle on the key `context` for a moment. */
    showAlert(context) {
        this.send({ event: "showAlert", context });
    }

    /** Writes a line to Stream Deck's own log. */
    logMessage(message) {
        this.send({ event: "logMessage", payload: { message: `[DAW Meter Bridge] ${message}` } });
    }
}
