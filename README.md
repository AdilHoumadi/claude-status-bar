# Claude Status Bar

An ambient status light for [Claude Code](https://claude.com/claude-code). A menu-bar
dot and an optional floating glass panel show, at a glance, whether each session is
**🔴 waiting for you**, **🟡 running**, or **🟢 done** — driven automatically by Claude
Code hooks, with desktop notifications on the transitions that matter.

No network, no telemetry. Everything is local files under `~/.claude/`.

## Requirements

- macOS 14 (Sonoma) or later
- Swift toolchain (Xcode **or** Command Line Tools: `xcode-select --install`)

## Install

```bash
./scripts/install.sh
```

That builds the app, bundles it (ad-hoc signed), wires the hooks into
`~/.claude/settings.json` (your existing hooks are preserved, a `.bak` is written), and
launches it. Re-running is safe — hooks merge without duplicating.

To keep it permanently, drag `ClaudeStatusBar.app` to `/Applications` (also recommended
for the **Start at login** option to register reliably).

## Using it

- **Menu bar dot** — aggregate state across all sessions (worst-state-wins).
- **Dropdown** — per-session list, plus toggles for **Floating lights** and **Settings**.
- **Floating lights** — an always-on-top glass panel with a road traffic-light per
  session (worst-first, max 5, `+N` overflow). Drag it anywhere; position is remembered.
- **Settings (⌘,)** — start at login, which transitions notify, sound, per-project mute,
  and Install/Uninstall hooks.

Open a **new** Claude Code session to see it move — a session loads its hooks at startup.

## State model

| Hook event | State |
|---|---|
| `Notification` (`permission_prompt` / `idle_prompt`) | 🔴 waiting for you |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`/`PostCompact` | 🟡 running |
| `Stop` | 🟢 done / idle |
| `SessionStart` / `SessionEnd` | create / remove the session |

## How it works

```
Claude Code ──hook (sync)──▶ claude-statusbar-hook ──▶ ~/.claude/statusbar/<id>.json
                                                              │ (polled every 0.5s)
                                              menu-bar app + floating panel
```

Hooks are synchronous, fail-open (always exit 0), and called by absolute path — they
never block or fail a Claude Code turn. The installed helper lives at a stable path
(`~/.claude/statusbar/bin/`) so app updates don't break the hooks.

## Manage hooks from the CLI

```bash
~/.claude/statusbar/bin/claude-statusbar-hook --install     # wire up (idempotent)
~/.claude/statusbar/bin/claude-statusbar-hook --uninstall   # remove ours; leaves others intact
```

## Uninstall

```bash
~/.claude/statusbar/bin/claude-statusbar-hook --uninstall
rm -rf ClaudeStatusBar.app ~/.claude/statusbar
```

## Troubleshooting

- **No notifications** — approve them in System Settings → Notifications → ClaudeStatusBar.
  Notifications only fire from the bundled `.app` (not bare `swift run`).
- **Dot doesn't move** — make sure you opened a *new* session after installing; check a
  state file appears: `ls ~/.claude/statusbar/`.
- **"Start at login" won't stick** — move the app to `/Applications` first.

## Development

```bash
swift run ClaudeStatusBarTests   # full test suite (dependency-free harness)
swift build                      # build all targets
./scripts/bundle.sh              # build the .app only
```

Source is a SwiftPM package: `StatusCore` (state model), `StatusStore` (hook helper +
state files), `StatusApp` (view-model, notifications, floating selection),
`StatusInstall` (settings.json installer), and the `ClaudeStatusBarApp` SwiftUI shell.

## Distribution

The bundle is **ad-hoc signed** — fine for your own machine. Sharing it with other Macs
requires a Developer ID certificate and notarization (an Apple Developer account).
