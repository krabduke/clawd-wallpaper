#!/bin/zsh
# Builds v2/build/ClawdWallpaper.app. Pass --install to copy it to /Applications and launch it,
# replacing v1 if that's installed (same app, same login item).
set -euo pipefail
cd "$(dirname "$0")"

app=build/ClawdWallpaper.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -target "$(uname -m)-apple-macos14.0" main.swift -o "$app/Contents/MacOS/ClawdWallpaper"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ClawdWallpaper || true
  sleep 0.5
  rm -rf /Applications/ClawdWallpaper.app
  cp -R "$app" /Applications/ClawdWallpaper.app
  open /Applications/ClawdWallpaper.app
  echo "Installed and launched /Applications/ClawdWallpaper.app"
fi
