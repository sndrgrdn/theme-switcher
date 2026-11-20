#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="$HOME/Applications/Theme Switcher.app"
pkill -x ThemeSwitcher 2>/dev/null && sleep 0.5 || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ThemeSwitcher" "$APP/Contents/MacOS/ThemeSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/templates "$APP/Contents/Resources/templates"
IDENTITY="${CODESIGN_IDENTITY:-Sander Local Signing}"
security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\"" || IDENTITY=-
codesign --force --options runtime --entitlements Resources/ThemeSwitcher.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
open "$APP"
printf 'Installed: %s\nSigned with: %s\n' "$APP" "$IDENTITY"
