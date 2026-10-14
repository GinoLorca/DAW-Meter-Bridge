// A fake Stream Deck: the server side of a WebSocket (RFC 6455) on node:http + node:crypto, with
// no dependencies. It accepts one plugin connection, records every JSON message the plugin sends
// and can send Stream Deck events to it.

import crypto from "node:crypto";
import { EventEmitter } from "node:events";
import http from "node:http";
import { waitForMessage } from "./wait.mjs";

const WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const OPCODE = Object.freeze({ continuation: 0x0, text: 0x1, binary: 0x2, close: 0x8, ping: 0x9, pong: 0xa });

export class FakeStreamDeck extends EventEmitter {
    constructor() {
        super();
        /** Every JSON message received from the plugin, in order. */
        this.messages = [];
        /** Protocol problems seen on the plugin's frames (should stay empty). */
        this.protocolErrors = [];
        this.socket = null;
        this.server = null;
        this.port = null;
    }

    async start() {
        this.server = http.createServer((_request, response) => {
            response.writeHead(426, { "Content-Type": "text/plain" });
            response.end("WebSocket only\n");
        });
        this.server.on("upgrade", (request, socket, head) => this.accept(request, socket, head));
        await new Promise((resolve) => this.server.listen(0, "127.0.0.1", resolve));
        this.port = this.server.address().port;
        return this.port;
    }

    async stop() {
        this.socket?.destroy();
        this.socket = null;
        if (this.server) {
            this.server.closeAllConnections?.();
            await new Promise((resolve) => this.server.close(() => resolve()));
            this.server = null;
        }
    }

    /** Resolves once the plugin has connected. */
    async connected(timeoutMs = 5000) {
        if (this.socket) {
            return;
        }
        await new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error("the plugin did not connect")), timeoutMs);
            this.once("connection", () => {
                clearTimeout(timer);
                resolve();
            });
        });
    }

    /** Sends one Stream Deck event (an object) to the plugin. */
    send(message) {
        if (!this.socket) {
            throw new Error("no plugin connected");
        }
        this.socket.write(encodeFrame(OPCODE.text, Buffer.from(JSON.stringify(message))));
    }

    /** Closes the connection the way Stream Deck does when it quits (close frame, then FIN). */
    closeConnection(code = 1000) {
        if (!this.socket) {
            return;
        }
        const payload = Buffer.alloc(2);
        payload.writeUInt16BE(code, 0);
        this.socket.write(encodeFrame(OPCODE.close, payload));
        this.socket.end();
    }

    /** Index of the next message, to wait only for messages that arrive after this point. */
    mark() {
        return this.messages.length;
    }

    /** Messages since `from` that match `predicate`. */
    since(from, predicate = () => true) {
        return this.messages.slice(from).filter(predicate);
    }

    /** Waits for a message (at index >= `from`) that matches `predicate`. */
    waitFor(predicate, { from = 0, timeoutMs = 3000, label = "Stream Deck message" } = {}) {
        return waitForMessage(this, this.messages, predicate, { from, timeoutMs, label });
    }

    // MARK: server side of the handshake and framing

    accept(request, socket, head) {
        const key = request.headers["sec-websocket-key"];
        if (!key || String(request.headers.upgrade).toLowerCase() !== "websocket") {
            socket.end("HTTP/1.1 400 Bad Request\r\n\r\n");
            return;
        }
        if (this.socket) {
            socket.end("HTTP/1.1 409 Conflict\r\n\r\n");
            return;
        }
        const accept = crypto.createHash("sha1").update(`${key}${WEBSOCKET_GUID}`).digest("base64");
        socket.write([
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            `Sec-WebSocket-Accept: ${accept}`,
            "",
            "",
        ].join("\r\n"));
        socket.setNoDelay(true);
        this.socket = socket;

        let buffer = Buffer.from(head ?? []);
        let fragments = [];
        const onData = (chunk) => {
            buffer = Buffer.concat([buffer, chunk]);
            for (;;) {
                const frame = decodeFrame(buffer);
                if (frame === null) {
                    break;
                }
                buffer = buffer.subarray(frame.size);
                if (!frame.masked) {
                    this.protocolErrors.push("client frame without a mask");
                }
                if (frame.opcode === OPCODE.text || frame.opcode === OPCODE.binary
                    || frame.opcode === OPCODE.continuation) {
                    fragments.push(frame.payload);
                    if (frame.fin) {
                        const text = Buffer.concat(fragments).toString("utf8");
                        fragments = [];
                        this.onText(text);
                    }
                } else if (frame.opcode === OPCODE.ping) {
                    socket.write(encodeFrame(OPCODE.pong, frame.payload));
                } else if (frame.opcode === OPCODE.close) {
                    socket.write(encodeFrame(OPCODE.close, frame.payload.subarray(0, 2)));
                    socket.end();
                }
            }
        };
        socket.on("data", onData);
        socket.on("error", () => {});
        socket.on("close", () => {
            if (this.socket === socket) {
                this.socket = null;
            }
            this.emit("disconnect");
        });
        if (buffer.length > 0) {
            onData(Buffer.alloc(0));
        }
        this.emit("connection");
    }

    onText(text) {
        let message;
        try {
            message = JSON.parse(text);
        } catch {
            this.protocolErrors.push(`not JSON: ${text}`);
            return;
        }
        this.messages.push(message);
        this.emit("message", message);
    }
}

/** Parses one frame at the start of `buffer`, or returns null when more bytes are needed. */
export function decodeFrame(buffer) {
    if (buffer.length < 2) {
        return null;
    }
    const fin = (buffer[0] & 0x80) !== 0;
    const opcode = buffer[0] & 0x0f;
    const masked = (buffer[1] & 0x80) !== 0;
    let length = buffer[1] & 0x7f;
    let offset = 2;
    if (length === 126) {
        if (buffer.length < 4) {
            return null;
        }
        length = buffer.readUInt16BE(2);
        offset = 4;
    } else if (length === 127) {
        if (buffer.length < 10) {
            return null;
        }
        length = Number(buffer.readBigUInt64BE(2));
        offset = 10;
    }
    let mask = null;
    if (masked) {
        if (buffer.length < offset + 4) {
            return null;
        }
        mask = buffer.subarray(offset, offset + 4);
        offset += 4;
    }
    if (buffer.length < offset + length) {
        return null;
    }
    const payload = Buffer.from(buffer.subarray(offset, offset + length));
    if (mask) {
        for (let i = 0; i < payload.length; i += 1) {
            payload[i] ^= mask[i & 3];
        }
    }
    return { fin, opcode, masked, payload, size: offset + length };
}

/** Encodes one unmasked, final frame (server to client). */
export function encodeFrame(opcode, payload) {
    let header;
    if (payload.length < 126) {
        header = Buffer.from([0x80 | opcode, payload.length]);
    } else if (payload.length < 0x10000) {
        header = Buffer.alloc(4);
        header[0] = 0x80 | opcode;
        header[1] = 126;
        header.writeUInt16BE(payload.length, 2);
    } else {
        header = Buffer.alloc(10);
        header[0] = 0x80 | opcode;
        header[1] = 127;
        header.writeBigUInt64BE(BigInt(payload.length), 2);
    }
    return Buffer.concat([header, payload]);
}
