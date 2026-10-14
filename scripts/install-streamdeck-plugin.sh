#!/usr/bin/env bash
# Installs the DAW Meter Bridge Stream Deck plugin: builds "build/DAW Meter Bridge.streamDeckPlugin"
# with scripts/package-streamdeck-plugin.sh, then opens it. Stream Deck shows its install prompt;
# click Install. Installing again replaces the previous version (Stream Deck asks first).
#
# Usage: scripts/install-streamdeck-plugin.sh
#   OUTPUT=<file> scripts/install-streamdeck-plugin.sh   # build the package somewhere else
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${OUTPUT:-$repo_root/build/DAW Meter Bridge.streamDeckPlugin}"
if [[ "$output" != /* ]]; then
    output="$PWD/$output"
fi

OUTPUT="$output" "$repo_root/scripts/package-streamdeck-plugin.sh"

if [[ ! -d "/Applications/Elgato Stream Deck.app" ]]; then
    echo "warning: Elgato Stream Deck.app is not in /Applications; install Stream Deck 7.1 or later." >&2
fi

echo "==> opening $output"
if ! open "$output"; then
    echo "error: could not open the package. Double-click it in Finder instead:" >&2
    echo "  $output" >&2
    exit 1
fi

echo
echo "Next steps:"
echo "  1. Click Install in the Stream Deck window."
echo "  2. Drag 'Show/Hide Bridge' and 'Show/Hide Main Meter' from the 'DAW Meter Bridge'"
echo "     category onto keys."
echo "  3. The keys light up while the bridge / Main meter is shown. Pressing 'Show/Hide Bridge'"
echo "     while the app is not running starts it in the background and shows the bridge."
echo "  4. Logs: ~/Library/Application Support/com.elgato.StreamDeck/Plugins/"
echo "     com.ginolorca.dawmeterbridge.sdPlugin/logs/"
