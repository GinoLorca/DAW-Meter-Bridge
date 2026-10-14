#!/usr/bin/env bash
# Builds "build/DAW Meter Bridge.app": a release build of the MeterBridge executable, an Info.plist
# (menu-bar app: LSUIElement; the dawmeterbridge:// URL scheme, docs/CONTROL.md), the app icon
# (Resources/AppIcon.icns, when it exists), the Live Remote Script as a resource (for "Install Live
# Script…"), and an ad-hoc code signature.
#
# Usage: scripts/build-app.sh
#   SCRATCH_PATH=<dir> scripts/build-app.sh   # build in <dir> instead of .build (parallel builds)
#   OUTPUT_DIR=<dir> scripts/build-app.sh     # put the .app in <dir> instead of build/ (verification
#                                             # builds, so they never replace the copy you are running)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# A relative OUTPUT_DIR is relative to the directory the script was started from.
output_dir="${OUTPUT_DIR:-$repo_root/build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
cd "$repo_root"

app_name="DAW Meter Bridge"
executable="MeterBridge"
bundle_id="com.ginolorca.DAWMeterBridge"
version="0.2.0"   # keep in step with AppInfo.fallbackVersion (Sources/MeterBridgeApp)
app="$output_dir/$app_name.app"

swift_args=(-c release)
if [[ -n "${SCRATCH_PATH:-}" ]]; then
    swift_args+=(--scratch-path "$SCRATCH_PATH")
fi

echo "==> swift build ${swift_args[*]} --product $executable"
swift build "${swift_args[@]}" --product "$executable"
bin_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
if [[ ! -x "$bin_dir/$executable" ]]; then
    echo "error: $bin_dir/$executable was not built" >&2
    exit 1
fi

echo "==> assembling $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/$executable" "$app/Contents/MacOS/$executable"
printf 'APPL????' > "$app/Contents/PkgInfo"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$app_name</string>
    <key>CFBundleExecutable</key>
    <string>$executable</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$bundle_id.control</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>dawmeterbridge</string>
            </array>
        </dict>
    </array>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

# The app icon (Finder, the Stream Deck plugin's "launch" key, alerts). Optional: without it macOS shows
# the generic app icon.
if [[ -f "$repo_root/Resources/AppIcon.icns" ]]; then
    cp "$repo_root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
else
    echo "note: Resources/AppIcon.icns not found; the app gets the generic icon"
fi

# The Remote Script, so "Install Live Script…" can reveal it wherever the app lives (.py files only).
script_source="$repo_root/AbletonRemoteScript/MeterBridge"
script_dest="$app/Contents/Resources/AbletonRemoteScript/MeterBridge"
mkdir -p "$script_dest"
while IFS= read -r -d '' file; do
    relative="${file#"$script_source"/}"
    mkdir -p "$script_dest/$(dirname "$relative")"
    cp "$file" "$script_dest/$relative"
done < <(find "$script_source" -name __pycache__ -prune -o -type f -name '*.py' -print0)
if [[ -f "$repo_root/AbletonRemoteScript/README.md" ]]; then
    cp "$repo_root/AbletonRemoteScript/README.md" "$app/Contents/Resources/AbletonRemoteScript/README.md"
fi

echo "==> ad-hoc signing"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

echo "Built $app ($version, $bundle_id)"
