// Waiting for a recorded message that matches a predicate, with a timeout that names what was missing.

/**
 * @param {import("node:events").EventEmitter} emitter emits "message" for each new entry of `list`
 * @param {unknown[]} list the recorded messages
 * @param {(message: any) => boolean} predicate
 * @param {{from?: number, timeoutMs?: number, label?: string}} options
 * @returns {Promise<any>} the first matching message at index >= from
 */
export function waitForMessage(emitter, list, predicate, { from = 0, timeoutMs = 3000, label = "message" } = {}) {
    const found = list.slice(from).find(predicate);
    if (found !== undefined) {
        return Promise.resolve(found);
    }
    return new Promise((resolve, reject) => {
        const onMessage = (message) => {
            if (predicate(message)) {
                clearTimeout(timer);
                emitter.off("message", onMessage);
                resolve(message);
            }
        };
        const timer = setTimeout(() => {
            emitter.off("message", onMessage);
            const recent = list.slice(Math.max(from, list.length - 8)).map((entry) => JSON.stringify(entry));
            reject(new Error(`timed out after ${timeoutMs} ms waiting for ${label}; recent:\n  ${recent.join("\n  ")}`));
        }, timeoutMs);
        emitter.on("message", onMessage);
    });
}

export const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
