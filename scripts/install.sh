#!/bin/bash
# One-shot setup: build the app, bundle it, wire the Claude Code hooks, and launch.
# Safe to re-run (idempotent): hooks merge without duplicating, settings.json is backed up.
set -euo pipefail

cd "$(dirname "$0")/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
DEST="$HOME/Applications/ClaudeStatusBar.app"

echo "==> 1/4  Building + bundling ClaudeStatusBar.app (release)"
./scripts/bundle.sh release

echo "==> 2/4  Installing Claude Code hooks (existing hooks are preserved, settings backed up)"
.build/release/claude-statusbar-hook --install
# Seed the ignore list (skip automated/headless runs like the Mnemo server) if absent.
IGNORE="$HOME/.claude/statusbar/ignore.txt"
mkdir -p "$HOME/.claude/statusbar"
[ -f "$IGNORE" ] || printf '%s\n' "$HOME/.mnemo" > "$IGNORE"

echo "==> 3/4  Installing app to ~/Applications (so its icon resolves in notifications)"
pkill -f "ClaudeStatusBarApp" 2>/dev/null || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R ClaudeStatusBar.app "$DEST"
"$LSREGISTER" -f "$DEST" 2>/dev/null || true   # register so Launch Services knows the icon
killall usernoted 2>/dev/null || true          # refresh the notification icon cache

echo "==> 4/4  Launching"
open "$DEST"

echo
echo "Done. Installed to ~/Applications; a status dot is now in your menu bar."
echo "Open a NEW Claude Code session to see it move (this session already loaded its hooks)."
