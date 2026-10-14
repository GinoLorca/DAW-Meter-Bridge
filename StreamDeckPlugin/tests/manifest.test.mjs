// The manifest, its images, and the package script.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { SOURCE_PLUGIN_DIR } from "./helpers/harness.mjs";
import { checkPlugin } from "../tools/check-manifest.mjs";
import { ACTION_SWITCHES, APP_BUNDLE_ID, PLUGIN_UUID, PLUGIN_VERSION } from "../com.ginolorca.dawmeterbridge.sdPlugin/bin/lib/constants.js";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const manifest = JSON.parse(fs.readFileSync(path.join(SOURCE_PLUGIN_DIR, "manifest.json"), "utf8"));

test("the manifest matches the plugin code", () => {
    assert.equal(manifest.UUID, PLUGIN_UUID);
    assert.equal(manifest.Version, PLUGIN_VERSION, "bump Version and PLUGIN_VERSION together");
    assert.equal(manifest.CodePath, "bin/plugin.js");
    assert.deepEqual(manifest.Nodejs, { Version: "24" });
    assert.equal(manifest.Software.MinimumVersion, "7.1", "Node 24 plugins need Stream Deck 7.1 or later");
    assert.equal(manifest.SDKVersion, 2);
    assert.deepEqual(manifest.OS.map((os) => os.Platform), ["mac"]);
    assert.deepEqual(manifest.ApplicationsToMonitor, { mac: [APP_BUNDLE_ID] });
    assert.deepEqual(manifest.Actions.map((action) => action.UUID).sort(), Object.keys(ACTION_SWITCHES).sort());
});

test("both actions have two states that only the plugin changes", () => {
    for (const action of manifest.Actions) {
        assert.equal(action.States.length, 2, action.UUID);
        assert.equal(action.DisableAutomaticStates, true, action.UUID);
        assert.equal(action.SupportedInMultiActions, true, action.UUID);
        assert.deepEqual(action.Controllers, ["Keypad"], action.UUID);
        assert.ok(action.States.every((state) => typeof state.Name === "string"), `${action.UUID}: states are named for multi-actions`);
        assert.match(action.States[0].Image, /\/off$/, `${action.UUID}: state 0 is the off image`);
        assert.match(action.States[1].Image, /\/on$/, `${action.UUID}: state 1 is the on image`);
    }
});

test("every image the manifest names exists at the right size", () => {
    const { errors, warnings, images } = checkPlugin(SOURCE_PLUGIN_DIR);
    for (const warning of warnings) {
        console.warn(`warning: ${warning}`);
    }
    assert.ok(errors.length === 0, `${errors.length} problem(s):\n${errors.join("\n")}`);
    assert.equal(images.length, 16);
});

test("the checker rejects Node 24 with a Stream Deck minimum older than 7.1", (t) => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dawmb-manifest-"));
    t.after(() => fs.rmSync(tempRoot, { recursive: true, force: true }));
    const pluginCopy = path.join(tempRoot, path.basename(SOURCE_PLUGIN_DIR));
    fs.cpSync(SOURCE_PLUGIN_DIR, pluginCopy, {
        recursive: true,
        filter: (source) => path.basename(source) !== "logs",
    });
    const write = (minimum) => fs.writeFileSync(
        path.join(pluginCopy, "manifest.json"),
        JSON.stringify({ ...manifest, Software: { MinimumVersion: minimum } }, null, 2),
    );
    const message = "\"Nodejs.Version\" 24 needs \"Software.MinimumVersion\" 7.1 or later";
    for (const minimum of ["6.9", "7.0"]) {
        write(minimum);
        assert.ok(checkPlugin(pluginCopy).errors.some((error) => error.includes(message)), minimum);
    }
    for (const minimum of ["7.1", "7.4", "8.0"]) {
        write(minimum);
        assert.deepEqual(checkPlugin(pluginCopy).errors, [], minimum);
    }
});

test("the package script zips the plugin folder without logs and junk", (t) => {
    // Run a copy of the script against a copy of the plugin, so nothing is written to the repository.
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dawmb-package-"));
    t.after(() => fs.rmSync(tempRoot, { recursive: true, force: true }));
    fs.mkdirSync(path.join(tempRoot, "scripts"));
    fs.copyFileSync(
        path.join(REPO_ROOT, "scripts", "package-streamdeck-plugin.sh"),
        path.join(tempRoot, "scripts", "package-streamdeck-plugin.sh"),
    );
    fs.cpSync(path.join(REPO_ROOT, "StreamDeckPlugin"), path.join(tempRoot, "StreamDeckPlugin"), {
        recursive: true,
        filter: (source) => path.basename(source) !== "logs" && path.basename(source) !== ".DS_Store",
    });
    const pluginCopy = path.join(tempRoot, "StreamDeckPlugin", path.basename(SOURCE_PLUGIN_DIR));
    fs.mkdirSync(path.join(pluginCopy, "logs"));
    fs.writeFileSync(path.join(pluginCopy, "logs", `${PLUGIN_UUID}.0.log`), "old log\n");
    fs.writeFileSync(path.join(pluginCopy, ".DS_Store"), "junk");
    fs.writeFileSync(path.join(pluginCopy, "bin", ".DS_Store"), "junk");

    const output = path.join(tempRoot, "out", "Test.streamDeckPlugin");
    execFileSync("/bin/bash", [path.join(tempRoot, "scripts", "package-streamdeck-plugin.sh")], {
        env: { ...process.env, OUTPUT: output, NODE: process.execPath },
        stdio: "pipe",
    });

    const entries = execFileSync("/usr/bin/zipinfo", ["-1", output], { encoding: "utf8" }).trim().split("\n");
    const folder = `${PLUGIN_UUID}.sdPlugin/`;
    assert.ok(entries.every((entry) => entry.startsWith(folder)), "everything is inside the .sdPlugin folder");
    for (const required of ["manifest.json", "bin/plugin.js", "bin/package.json", "bin/lib/app-link.js",
        "bin/lib/bridge-plugin.js", "imgs/actions/bridge/on@2x.png", "imgs/plugin/icon.png"]) {
        assert.ok(entries.includes(`${folder}${required}`), `missing ${required}`);
    }
    assert.deepEqual(entries.filter((entry) => /\/logs\/|\.DS_Store|\/tests\//.test(entry)), []);
});
