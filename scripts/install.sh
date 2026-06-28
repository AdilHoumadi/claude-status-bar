#!/bin/bash
# One-shot setup: build the app, bundle it, wire the Claude Code hooks, and launch.
# Safe to re-run (idempotent): hooks merge without duplicating, settings.json is backed up.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 1/3  Building + bundling ClaudeStatusBar.app (release)"
./scripts/bundle.sh release

echo "==> 2/3  Installing Claude Code hooks (existing hooks are preserved, settings backed up)"
.build/release/claude-statusbar-hook --install

echo "==> 3/3  (Re)launching the app"
pkill -f "ClaudeStatusBar.app/Contents/MacOS/ClaudeStatusBarApp" 2>/dev/null || true
sleep 1
open ClaudeStatusBar.app

echo
echo "Done. A status dot is now in your menu bar."
echo "Open a NEW Claude Code session to see it move (this session already loaded its hooks)."
echo "Optional: copy ClaudeStatusBar.app to /Applications to keep it permanently."
