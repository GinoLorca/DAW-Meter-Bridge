#!/usr/bin/env bash
# Copies the MeterBridge Remote Script into Ableton Live's User Library:
#   AbletonRemoteScript/MeterBridge -> ~/Music/Ableton/User Library/Remote Scripts/MeterBridge
# Replaces any previous copy (so renamed or deleted modules don't linger) and skips __pycache__.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/AbletonRemoteScript/MeterBridge"
scripts_dir="$HOME/Music/Ableton/User Library/Remote Scripts"
dest_dir="$scripts_dir/MeterBridge"

if [[ ! -f "$source_dir/__init__.py" ]]; then
    echo "error: $source_dir/__init__.py not found" >&2
    exit 1
fi
if [[ -z "${HOME:-}" || "$dest_dir" != */"Remote Scripts/MeterBridge" ]]; then
    echo "error: unexpected destination '$dest_dir'" >&2
    exit 1
fi

mkdir -p "$scripts_dir"
if [[ -d "$dest_dir" ]]; then
    rm -rf "$dest_dir"
fi
mkdir -p "$dest_dir"

count=0
while IFS= read -r -d '' file; do
    relative="${file#"$source_dir"/}"
    mkdir -p "$dest_dir/$(dirname "$relative")"
    cp "$file" "$dest_dir/$relative"
    count=$((count + 1))
done < <(find "$source_dir" -name __pycache__ -prune -o -type f -name '*.py' -print0)

echo "Installed $count files to:"
echo "  $dest_dir"
echo
echo "Next steps:"
echo "  1. Quit and restart Ableton Live (it only scans Remote Scripts at startup)."
echo "  2. Settings > Link, Tempo & MIDI > Control Surface: pick 'MeterBridge' in a free slot,"
echo "     with Input and Output set to None."
echo "  3. Start DAW Meter Bridge and choose Source > Ableton Live."
echo "  4. Live's Log.txt (~/Library/Preferences/Ableton/Live <version>/Log.txt) shows lines"
echo "     starting with '(MeterBridgeSurface)'."
echo
echo "Note: leftover MackieControlXT entries in other slots (even with no ports) become"
echo "extensions of MackieControl, so the UF8 banks by 8 x (1 + number of XTs) tracks."
echo "Remove them if the UF8 should bank by 8."
