#!/usr/bin/env node
// Checks a .sdPlugin folder before it is packaged or tested:
// - manifest.json parses and has the keys Stream Deck needs,
// - CodePath exists,
// - every image the manifest names exists as <name>.png and <name>@2x.png at the right size,
// - the category and action-list icons are white on transparent (warning only).
//
// Usage: node StreamDeckPlugin/tools/check-manifest.mjs [path/to/plugin.sdPlugin]
// Exit status 1 when there are errors.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** Expected point sizes per image role (the @2x file is twice as large). */
export const IMAGE_SIZES = Object.freeze({
    pluginIcon: 256,
    categoryIcon: 28,
    actionIcon: 20,
    keyImage: 72,
});

/** Roles that Stream Deck tints, so they must be white on transparent. */
const MONOCHROME_ROLES = new Set(["categoryIcon", "actionIcon"]);

/**
 * @param {string} pluginDir path to the .sdPlugin folder
 * @returns {{errors: string[], warnings: string[], manifest: object | null, images: {role: string, file: string}[]}}
 */
export function checkPlugin(pluginDir) {
    const errors = [];
    const warnings = [];
    const images = [];
    const manifestPath = path.join(pluginDir, "manifest.json");

    let manifest;
    try {
        manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    } catch (error) {
        errors.push(`manifest.json: ${error.code === "ENOENT" ? "not found" : error.message}`);
        return { errors, warnings, manifest: null, images };
    }

    const check = (condition, message) => {
        if (!condition) {
            errors.push(`manifest.json: ${message}`);
        }
    };
    const isText = (value) => typeof value === "string" && value.trim() !== "";

    const folderUUID = path.basename(pluginDir).replace(/\.sdPlugin$/, "");
    check(manifest.UUID === folderUUID, `UUID "${manifest.UUID}" must match the folder name "${folderUUID}.sdPlugin"`);
    for (const key of ["Name", "Author", "Description", "Category", "Icon", "CategoryIcon", "CodePath"]) {
        check(isText(manifest[key]), `"${key}" is missing`);
    }
    check(/^\d+\.\d+\.\d+\.\d+$/.test(manifest.Version ?? ""), `"Version" must look like 1.2.3.4, got "${manifest.Version}"`);
    check(manifest.SDKVersion === 2, `"SDKVersion" must be 2`);
    check(isText(manifest.Nodejs?.Version), `"Nodejs.Version" is missing`);
    check(isText(manifest.Software?.MinimumVersion), `"Software.MinimumVersion" is missing`);
    if (manifest.Nodejs?.Version === "24" && isText(manifest.Software?.MinimumVersion)) {
        // Stream Deck runs plugins on Node 24 from 7.1 on; earlier versions only have Node 20 (no built-in
        // WebSocket), and Elgato's manifest schema rejects Node 24 with an older minimum.
        const [major = 0, minor = 0] = manifest.Software.MinimumVersion.split(".").map(Number);
        check(major > 7 || (major === 7 && minor >= 1), `"Nodejs.Version" 24 needs "Software.MinimumVersion" 7.1 or later`);
    }
    check(Array.isArray(manifest.OS) && manifest.OS.some((os) => os.Platform === "mac"), `"OS" must list mac`);
    if (isText(manifest.CodePath)) {
        check(fs.existsSync(path.join(pluginDir, manifest.CodePath)), `CodePath "${manifest.CodePath}" does not exist`);
    }

    const imageRefs = [
        { role: "pluginIcon", ref: manifest.Icon, where: "Icon" },
        { role: "categoryIcon", ref: manifest.CategoryIcon, where: "CategoryIcon" },
    ];

    const actions = Array.isArray(manifest.Actions) ? manifest.Actions : [];
    check(actions.length > 0, `"Actions" is empty`);
    const seen = new Set();
    for (const [index, action] of actions.entries()) {
        const label = `Actions[${index}] (${action.UUID ?? "no UUID"})`;
        check(isText(action.UUID) && action.UUID.startsWith(`${manifest.UUID}.`), `${label}: UUID must start with "${manifest.UUID}."`);
        check(!seen.has(action.UUID), `${label}: duplicate UUID`);
        seen.add(action.UUID);
        for (const key of ["Name", "Icon", "Tooltip"]) {
            check(isText(action[key]), `${label}: "${key}" is missing`);
        }
        const states = Array.isArray(action.States) ? action.States : [];
        check(states.length >= 1 && states.length <= 2, `${label}: needs one or two States`);
        imageRefs.push({ role: "actionIcon", ref: action.Icon, where: `${label} Icon` });
        for (const [stateIndex, state] of states.entries()) {
            check(isText(state.Image), `${label}: States[${stateIndex}] has no Image`);
            imageRefs.push({ role: "keyImage", ref: state.Image, where: `${label} States[${stateIndex}]` });
        }
    }

    for (const { role, ref, where } of imageRefs) {
        if (!isText(ref)) {
            continue;
        }
        const points = IMAGE_SIZES[role];
        for (const [suffix, scale] of [["", 1], ["@2x", 2]]) {
            const relative = `${ref}${suffix}.png`;
            const file = path.join(pluginDir, relative);
            const size = points * scale;
            images.push({ role, file: relative });
            if (!fs.existsSync(file)) {
                errors.push(`missing image ${relative} (${size}x${size}, ${where})`);
                continue;
            }
            let png;
            try {
                png = readPng(fs.readFileSync(file));
            } catch (error) {
                errors.push(`${relative}: ${error.message}`);
                continue;
            }
            if (png.width !== size || png.height !== size) {
                errors.push(`${relative} is ${png.width}x${png.height}, expected ${size}x${size} (${where})`);
            }
            if (MONOCHROME_ROLES.has(role)) {
                const problem = monochromeProblem(png);
                if (problem) {
                    warnings.push(`${relative} should be white on transparent: ${problem}`);
                }
            }
        }
    }

    return { errors, warnings, manifest, images };
}

/**
 * Reads a PNG's size and, for 8-bit non-interlaced images, its pixels.
 * @returns {{width: number, height: number, rgba: Buffer | null}}
 */
export function readPng(data) {
    if (data.length < 33 || !data.subarray(0, 8).equals(PNG_SIGNATURE)) {
        throw new Error("not a PNG file");
    }
    let offset = 8;
    let header = null;
    let palette = null;
    let transparency = null;
    const idat = [];
    while (offset + 8 <= data.length) {
        const length = data.readUInt32BE(offset);
        const type = data.toString("latin1", offset + 4, offset + 8);
        const body = data.subarray(offset + 8, offset + 8 + length);
        offset += 12 + length;
        if (type === "IHDR") {
            header = {
                width: body.readUInt32BE(0),
                height: body.readUInt32BE(4),
                bitDepth: body[8],
                colorType: body[9],
                interlace: body[12],
            };
        } else if (type === "PLTE") {
            palette = body;
        } else if (type === "tRNS") {
            transparency = body;
        } else if (type === "IDAT") {
            idat.push(body);
        } else if (type === "IEND") {
            break;
        }
    }
    if (header === null) {
        throw new Error("PNG has no IHDR chunk");
    }
    const { width, height, bitDepth, colorType, interlace } = header;
    const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
    if (bitDepth !== 8 || interlace !== 0 || channels === undefined) {
        return { width, height, rgba: null };
    }

    const raw = zlib.inflateSync(Buffer.concat(idat));
    const stride = width * channels;
    const pixels = Buffer.alloc(stride * height);
    for (let y = 0; y < height; y += 1) {
        const filter = raw[y * (stride + 1)];
        const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        const out = pixels.subarray(y * stride, (y + 1) * stride);
        const previous = y > 0 ? pixels.subarray((y - 1) * stride, y * stride) : null;
        for (let x = 0; x < stride; x += 1) {
            const a = x >= channels ? out[x - channels] : 0;
            const b = previous ? previous[x] : 0;
            const c = previous && x >= channels ? previous[x - channels] : 0;
            let predictor = 0;
            if (filter === 1) {
                predictor = a;
            } else if (filter === 2) {
                predictor = b;
            } else if (filter === 3) {
                predictor = (a + b) >> 1;
            } else if (filter === 4) {
                const p = a + b - c;
                const pa = Math.abs(p - a);
                const pb = Math.abs(p - b);
                const pc = Math.abs(p - c);
                predictor = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
            }
            out[x] = (line[x] + predictor) & 0xff;
        }
    }

    const rgba = Buffer.alloc(width * height * 4);
    for (let i = 0; i < width * height; i += 1) {
        const source = i * channels;
        let r;
        let g;
        let b;
        let alpha = 255;
        if (colorType === 6) {
            [r, g, b, alpha] = [pixels[source], pixels[source + 1], pixels[source + 2], pixels[source + 3]];
        } else if (colorType === 2) {
            [r, g, b] = [pixels[source], pixels[source + 1], pixels[source + 2]];
        } else if (colorType === 4) {
            r = g = b = pixels[source];
            alpha = pixels[source + 1];
        } else if (colorType === 0) {
            r = g = b = pixels[source];
        } else {
            const index = pixels[source];
            [r, g, b] = palette ? [palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2]] : [0, 0, 0];
            alpha = transparency && index < transparency.length ? transparency[index] : 255;
        }
        rgba.set([r, g, b, alpha], i * 4);
    }
    return { width, height, rgba };
}

function monochromeProblem({ width, height, rgba }) {
    if (rgba === null) {
        return null; // Not decodable here; nothing to report.
    }
    let visible = 0;
    let colored = 0;
    for (let i = 0; i < width * height; i += 1) {
        const [r, g, b, alpha] = rgba.subarray(i * 4, i * 4 + 4);
        if (alpha < 16) {
            continue;
        }
        visible += 1;
        if (Math.min(r, g, b) < 0xe0) {
            colored += 1;
        }
    }
    if (visible === 0) {
        return "it is fully transparent";
    }
    if (visible === width * height) {
        return "it has no transparent pixels";
    }
    if (colored > 0) {
        return `${colored} of ${visible} visible pixels are not white`;
    }
    return null;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
    const defaultDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "com.ginolorca.dawmeterbridge.sdPlugin");
    const pluginDir = path.resolve(process.argv[2] ?? defaultDir);
    const { errors, warnings, images } = checkPlugin(pluginDir);
    for (const warning of warnings) {
        console.warn(`warning: ${warning}`);
    }
    for (const error of errors) {
        console.error(`error: ${error}`);
    }
    if (errors.length > 0) {
        console.error(`${path.basename(pluginDir)}: ${errors.length} error(s)`);
        process.exit(1);
    }
    console.log(`${path.basename(pluginDir)}: manifest OK, ${images.length} images checked`);
}
