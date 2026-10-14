// Command line and environment parsing.
//
// Stream Deck starts the plugin as:
//   node bin/plugin.js -port 28196 -pluginUUID <uuid> -registerEvent registerPlugin -info '{...}'

import { DEFAULT_CONTROL_PORT } from "./constants.js";

const REGISTRATION_ARGS = ["port", "pluginUUID", "registerEvent", "info"];

/**
 * Parses Stream Deck's registration arguments.
 * @param {string[]} argv the arguments after the script path
 * @returns {{port: number, pluginUUID: string, registerEvent: string, info: object | null}}
 * @throws {Error} when an argument is missing or the port is not a port number
 */
export function parseRegistrationArgs(argv) {
    const values = {};
    for (let i = 0; i < argv.length; i += 1) {
        const name = argv[i].replace(/^-+/, "");
        if (argv[i].startsWith("-") && REGISTRATION_ARGS.includes(name) && i + 1 < argv.length) {
            values[name] = argv[i + 1];
            i += 1;
        }
    }

    const missing = REGISTRATION_ARGS.filter((name) => values[name] === undefined);
    if (missing.length > 0) {
        throw new Error(`missing command line arguments: ${missing.map((name) => `-${name}`).join(", ")}`);
    }

    const port = parsePort(values.port);
    if (port === null) {
        throw new Error(`-port must be a port number, got "${values.port}"`);
    }

    let info = null;
    try {
        info = JSON.parse(values.info);
    } catch {
        info = null; // Only used for logging.
    }

    return { port, pluginUUID: values.pluginUUID, registerEvent: values.registerEvent, info };
}

/**
 * The app's control port: DAWMB_CONTROL_PORT, or 47802.
 * @param {Record<string, string | undefined>} env
 * @throws {Error} when DAWMB_CONTROL_PORT is set but is not a port number
 */
export function controlPortFromEnv(env) {
    const raw = env.DAWMB_CONTROL_PORT;
    if (raw === undefined || raw === "") {
        return DEFAULT_CONTROL_PORT;
    }
    const port = parsePort(raw);
    if (port === null) {
        throw new Error(`DAWMB_CONTROL_PORT must be a port number, got "${raw}"`);
    }
    return port;
}

/** True when DAWMB_NO_LAUNCH=1: never run `open`, only log what would have been launched. */
export function launchDisabledFromEnv(env) {
    return env.DAWMB_NO_LAUNCH === "1";
}

function parsePort(text) {
    if (!/^\d{1,5}$/.test(String(text).trim())) {
        return null;
    }
    const port = Number(text);
    return port >= 1 && port <= 65535 ? port : null;
}
