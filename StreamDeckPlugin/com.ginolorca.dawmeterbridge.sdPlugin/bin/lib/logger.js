// A small rotating file log: <dir>/<name>.0.log is the current run, .1 the one before, and so on.
// Every start begins a new file, and a file that grows past maxBytes is rotated too, so the
// folder never holds more than maxFiles * maxBytes.

import fs from "node:fs";
import path from "node:path";
import { inspect } from "node:util";

export const LOG_LEVELS = Object.freeze({ debug: 10, info: 20, warn: 30, error: 40 });

export class FileLogger {
    /**
     * @param {object} options
     * @param {string} options.dir folder for the log files (created if needed)
     * @param {string} options.name file name prefix
     * @param {number} [options.maxBytes] rotate when the current file would grow past this
     * @param {number} [options.maxFiles] files kept, including the current one
     * @param {"debug" | "info" | "warn" | "error"} [options.level] lowest level written
     */
    constructor({ dir, name, maxBytes = 256 * 1024, maxFiles = 5, level = "info" }) {
        this.dir = dir;
        this.name = name;
        this.maxBytes = maxBytes;
        this.maxFiles = Math.max(1, maxFiles);
        this.threshold = LOG_LEVELS[level] ?? LOG_LEVELS.info;
        this.size = 0;
        this.enabled = true;
        /** Called with (level, message) for every line written at warn or above. */
        this.onWarning = null;

        try {
            fs.mkdirSync(dir, { recursive: true });
            if (fileSize(this.pathFor(0)) > 0) {
                this.rotate();
            }
            this.size = fileSize(this.pathFor(0));
        } catch (error) {
            this.enabled = false;
            process.stderr.write(`logging disabled: cannot use ${dir}: ${error.message}\n`);
        }
    }

    /** The path of log file number `index` (0 = current). */
    pathFor(index) {
        return path.join(this.dir, `${this.name}.${index}.log`);
    }

    debug(...parts) {
        this.write("debug", parts);
    }

    info(...parts) {
        this.write("info", parts);
    }

    warn(...parts) {
        this.write("warn", parts);
    }

    error(...parts) {
        this.write("error", parts);
    }

    write(level, parts) {
        const rank = LOG_LEVELS[level];
        if (rank < this.threshold) {
            return;
        }
        const message = parts.map(formatPart).join(" ");
        if (this.enabled) {
            const line = `${new Date().toISOString()} ${level.toUpperCase().padEnd(5)} ${message}\n`;
            const bytes = Buffer.byteLength(line);
            try {
                if (this.size > 0 && this.size + bytes > this.maxBytes) {
                    this.rotate();
                }
                fs.appendFileSync(this.pathFor(0), line);
                this.size += bytes;
            } catch (error) {
                this.enabled = false;
                process.stderr.write(`logging disabled: ${error.message}\n`);
            }
        }
        if (rank >= LOG_LEVELS.warn && typeof this.onWarning === "function") {
            try {
                this.onWarning(level, message);
            } catch {
                // A failing sink must not break logging.
            }
        }
    }

    /** Shifts .0 -> .1 -> ... and drops the oldest file. */
    rotate() {
        for (let index = this.maxFiles - 1; index >= 1; index -= 1) {
            const from = this.pathFor(index - 1);
            if (fs.existsSync(from)) {
                fs.renameSync(from, this.pathFor(index));
            }
        }
        if (this.maxFiles === 1) {
            fs.rmSync(this.pathFor(0), { force: true });
        }
        this.size = 0;
    }
}

function fileSize(file) {
    try {
        return fs.statSync(file).size;
    } catch {
        return 0;
    }
}

function formatPart(part) {
    if (part instanceof Error) {
        return part.stack ?? `${part.name}: ${part.message}`;
    }
    if (typeof part === "string") {
        return part;
    }
    return inspect(part, { depth: 4, breakLength: Infinity });
}
