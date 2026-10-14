#!/usr/bin/env bash
# Packages the Stream Deck plugin as "build/DAW Meter Bridge.streamDeckPlugin": a zip of
# StreamDeckPlugin/com.ginolorca.dawmeterbridge.sdPlugin (without logs/, tests and .DS_Store).
# Double-clicking that file (or `open`ing it) makes Stream Deck offer to install the plugin.
#
# Before zipping, StreamDeckPlugin/tools/check-manifest.mjs checks the manifest and that every
# image it names exists as a 1x and @2x PNG of the right size. It needs Node: $NODE, else node on
# PATH, else the newest Node bundled with Stream Deck.
#
# Usage: scripts/package-streamdeck-plugin.sh
#   OUTPUT=<file> scripts/package-streamdeck-plugin.sh   # write the package somewhere else
#   NODE=<path to node> scripts/package-streamdeck-plugin.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_parent="$repo_root/StreamDeckPlugin"
plugin_name="com.ginolorca.dawmeterbridge.sdPlugin"
plugin_dir="$plugin_parent/$plugin_name"

# A relative OUTPUT is relative to the directory the script was started from.
output="${OUTPUT:-$repo_root/build/DAW Meter Bridge.streamDeckPlugin}"
if [[ "$output" != /* ]]; then
    output="$PWD/$output"
fi
if [[ "$output" != *.streamDeckPlugin ]]; then
    echo "error: OUTPUT must end in .streamDeckPlugin, got '$output'" >&2
    exit 1
fi

if [[ ! -f "$plugin_dir/manifest.json" ]]; then
    echo "error: $plugin_dir/manifest.json not found" >&2
    exit 1
fi

find_node() {
    if [[ -n "${NODE:-}" ]]; then
        echo "$NODE"
        return
    fi
    if command -v node >/dev/null 2>&1; then
        command -v node
        return
    fi
    local bundled="$HOME/Library/Application Support/com.elgato.StreamDeck/NodeJS"
    local candidate
    candidate="$(find "$bundled" -mindepth 2 -maxdepth 2 -type f -name node 2>/dev/null | sort -V | tail -n 1)"
    if [[ -n "$candidate" ]]; then
        echo "$candidate"
    fi
}

node_bin="$(find_node)"
if [[ -z "$node_bin" || ! -x "$node_bin" ]]; then
    echo "error: Node is needed to check the manifest; set NODE=<path to node>" >&2
    exit 1
fi

echo "==> checking $plugin_name"
"$node_bin" "$plugin_parent/tools/check-manifest.mjs" "$plugin_dir"

echo "==> packaging $output"
mkdir -p "$(dirname "$output")"
staging="$(mktemp -d "${TMPDIR:-/tmp}/dawmb-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

# zip from the plugin's parent, so the archive holds the .sdPlugin folder at its root.
(
    cd "$plugin_parent"
    zip -r -X -q "$staging/plugin.zip" "$plugin_name" \
        -x "$plugin_name/logs/*" \
        -x "$plugin_name/tests/*" \
        -x "*.DS_Store" \
        -x "*/._*" \
        -x "*/.git*"
)
if ! unzip -l "$staging/plugin.zip" "$plugin_name/manifest.json" >/dev/null 2>&1; then
    echo "error: the package has no $plugin_name/manifest.json" >&2
    exit 1
fi
mv -f "$staging/plugin.zip" "$output"

count="$(zipinfo -1 "$output" | grep -cv '/$')"
size="$(du -h "$output" | cut -f1 | tr -d ' ')"
echo "Packaged $output ($count files, $size)"
