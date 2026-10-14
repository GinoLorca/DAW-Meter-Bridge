// Starts DAW Meter Bridge in the background: `open -g -b com.ginolorca.DAWMeterBridge`.
// -g keeps the DAW in front. With DAWMB_NO_LAUNCH=1 nothing is run (tests).

import { execFile } from "node:child_process";

const OPEN = "/usr/bin/open";

/**
 * @param {object} options
 * @param {string} options.bundleId
 * @param {boolean} options.disabled when true, launch() only logs the command
 * @param {{info: Function}} options.log
 * @returns {{command: string[], launch: () => Promise<{skipped: boolean}>}}
 */
export function createLauncher({ bundleId, disabled, log }) {
    const args = ["-g", "-b", bundleId];
    const command = ["open", ...args];
    return {
        command,
        launch() {
            if (disabled) {
                log.info(`launch skipped (DAWMB_NO_LAUNCH=1): ${command.join(" ")}`);
                return Promise.resolve({ skipped: true });
            }
            log.info(`launching: ${command.join(" ")}`);
            return new Promise((resolve, reject) => {
                execFile(OPEN, args, { timeout: 10_000 }, (error, _stdout, stderr) => {
                    if (error) {
                        const detail = String(stderr ?? "").trim() || error.message;
                        reject(new Error(`${command.join(" ")} failed: ${detail}`));
                    } else {
                        resolve({ skipped: false });
                    }
                });
            });
        },
    };
}
