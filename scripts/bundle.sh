#!/bin/bash
# Build a runnable ClaudeStatusBar.app bundle from the SwiftPM executables.
# Notifications require this bundle (UNUserNotificationCenter needs a bundle identifier);
# running the bare `swift run ClaudeStatusBarApp` works for the GUI but won't notify.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="ClaudeStatusBar.app"
MACOS="${APP}/Contents/MacOS"
BIN=".build/${CONFIG}"

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${MACOS}" "${APP}/Contents/Resources"

cp "${BIN}/ClaudeStatusBarApp" "${MACOS}/ClaudeStatusBarApp"
# Helper must sit next to the app exe so the app can copy it to the stable hook path.
cp "${BIN}/claude-statusbar-hook" "${MACOS}/claude-statusbar-hook"
chmod +x "${MACOS}/ClaudeStatusBarApp" "${MACOS}/claude-statusbar-hook"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudeStatusBar</string>
    <key>CFBundleDisplayName</key><string>Claude Status Bar</string>
    <key>CFBundleIdentifier</key><string>com.adil.claudestatusbar</string>
    <key>CFBundleExecutable</key><string>ClaudeStatusBarApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "${APP}/Contents/Info.plist" >/dev/null
echo "Done: ${APP}"
echo "Run it with:  open ${APP}"
