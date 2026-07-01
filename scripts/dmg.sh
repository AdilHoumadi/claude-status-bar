#!/bin/bash
# Build a distributable ClaudeStatusBar.dmg (ad-hoc signed; not notarized).
# On first open the recipient right-clicks > Open, or runs:
#   xattr -dr com.apple.quarantine /Applications/ClaudeStatusBar.app
set -euo pipefail

cd "$(dirname "$0")/.."

APP="ClaudeStatusBar.app"
VOL="Claude Status Bar"
OUT="dist/ClaudeStatusBar.dmg"

echo "==> Building app"
./scripts/bundle.sh release

echo "==> Staging DMG contents"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "==> Creating $OUT"
mkdir -p dist
rm -f "$OUT"
hdiutil create \
  -volname "$VOL" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUT" >/dev/null

rm -rf "$STAGE"
SIZE="$(du -h "$OUT" | cut -f1)"
echo "Done: $OUT ($SIZE)"
echo "Share it. First open: right-click the app > Open (unsigned/ad-hoc)."
