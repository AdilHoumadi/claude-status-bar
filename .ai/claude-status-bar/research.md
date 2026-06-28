# Research: macOS menu-bar status light + notifications for Claude Code

**Slug:** claude-status-bar
**Triage:** complex
**Date:** 2026-06-28

## Problem statement
When Claude Code is working, you switch to another window or your phone, then keep
switching back just to check whether it's still running, waiting for you, or done.
There's no ambient signal. The goal is a native macOS menu-bar app that shows a
traffic-light status — **red** = waiting for your confirmation/input, **yellow** =
running, **green** = idle/done — driven automatically by Claude Code hooks, plus
**desktop notifications** (with sound) when a session needs you or finishes. It must
aggregate **multiple concurrent sessions** (you run several terminals at once). This is
about *agent activity state*, not usage/quota — see the CodexBar note below.

## Reframing (important)
The referenced **CodexBar** (`steipete/CodexBar`) is a **usage-limits monitor** — it
tracks quota/credit/reset countdowns across 50+ AI providers. That is **not** what this
project is. The actual model is the DIY traffic light from the Reddit/LinkedIn post:
*agent state* signalling. Usage tracking is explicitly **out of scope**.

The form-factor we admire from CodexBar (polished native macOS menu-bar app, Swift) is
what we're adopting — not its function.

## Decisions (locked via interview, 2026-06-28)
- **Build our own** (not adopt an existing tool — see prior art below).
- **Swift / SwiftUI** stack (native, matches CodexBar/gmr polish; new language for Adil).
- **Full scope**: traffic light + per-session dropdown detail (cwd, state, elapsed
  timer) + notification **sound** + **per-project mute** + configurable which transitions
  notify + optional **compacting (blue)** state.
- **Multi-session aggregation**: per-session state, menu bar shows worst-state-wins.

## Mnemo context
No prior work on a status-bar/notification tool in L3. Two relevant verified facts:
- **`async: true` hooks lose stdin.** Claude Code drops stdin for async hooks — the
  Mnemo Stop hook was broken this way (SID always empty); fixed by removing `async:true`.
  This project's hooks **must be synchronous** because they read `session_id` and
  `notification_type` from stdin.
- **Hooks run with a minimal PATH.** The caveman hooks broke calling bare `node`,
  needing a Homebrew symlink or interactive PATH resolution. Implication: hook scripts
  must use **absolute paths** or, better, a **bundled helper binary** — do not assume
  `jq`/`python3`/`node` are on PATH inside a hook. (`jq` at `/opt/homebrew/bin/jq` and
  `python3` exist on this machine but Homebrew is typically absent from hook PATH.)

## Prior art (verified via web search, 2026-06-28)
This problem is already solved by several open-source tools. The architecture below is
the **convergent pattern** every one of them uses, which validates the design:
- **gmr/claude-status** — Swift, macOS 26.2+. Plugin hooks into session lifecycle;
  writes a `.cstatus` file + posts a Darwin notification on start/stop/state-change.
  4 states (active/waiting/compacting/idle), 3 detection layers (Darwin notification →
  FS watch → 5s poll fallback), **multi-session aggregation**, process-tree validation
  (terminal/IDE/tmux). This is the closest match to what we're building.
- **m1ckc3s/claude-status-bar** — simpler; hooks write `~/.claude/statusbar/state.json`,
  app **polls every 0.4s**. (Note: same name as this repo.)
- Others (cc-status-bar, claudewatch, ClaudeBar, ClaudeUsageBar) are mostly
  CodexBar-style usage monitors, not activity-state lights.
- **SwiftBar** — generic menu-bar tool that renders shell-script output on an interval;
  a fallback if we wanted zero native code.

We are deliberately building our own for ownership/customization, knowing gmr/claude-status
already does ~this. If the build stalls, gmr/claude-status is the drop-in fallback.

## Verified mechanics — Claude Code hooks → traffic-light state
Source: official hooks reference (`code.claude.com/docs/en/hooks`). The state mapping is
the core of the design:

| Hook event | stdin signal | Light state |
|---|---|---|
| `Notification` | `notification_type: "permission_prompt"` | **RED** (needs approval) |
| `Notification` | `notification_type: "idle_prompt"` | **RED** (waiting for input) |
| `UserPromptSubmit` | — | **YELLOW** (work started) |
| `PreToolUse` / `PostToolUse` | — | **YELLOW** (running) |
| `PreCompact` / `PostCompact` | — | **BLUE** (compacting, optional) |
| `Stop` | — | **GREEN** (turn done / idle) |
| `SessionStart` | `source: startup/resume/clear/compact` | create session entry |
| `SessionEnd` | — | remove session entry |

**Common stdin fields** (all events): `session_id`, `transcript_path`, `cwd`,
`permission_mode`, `hook_event_name`. **Notification** adds `notification_type` and
`message`. **Stop** fires on every end-of-turn (no matcher). Hooks are configured in
`settings.json` under `hooks` → event → matcher group → handler (`type: "command"`).

> Caveat to verify during implement: the docs page enumerated ~28 events and the exact
> `notification_type` matcher values (`permission_prompt`, `idle_prompt`, `auth_success`,
> `elicitation_*`). Confirm the live values empirically by logging raw stdin from a real
> session before hard-coding the matchers. Only the core 7 events above are needed.

## Architecture (proposed)
Convergent file-state pattern, aggregation built in:

```
Claude Code session ──hooks (sync)──▶ helper writes ~/.claude/statusbar/<session_id>.json
                                                              │
                              ┌───────────────────────────────┘
                              ▼
   Swift menu-bar app: watch dir (DispatchSource/kqueue) + 0.5s Timer poll fallback
        ├─ aggregate worst-state-wins across all session files  → menu-bar icon
        ├─ dropdown: per-session cwd / state / elapsed timer
        ├─ on state transition → UNUserNotificationCenter notification (+ sound)
        └─ reap stale files (SessionEnd removes; also age-out by updated_at)
```

- **Transport**: one JSON file per session in `~/.claude/statusbar/`, e.g.
  `{ "session_id", "state", "cwd", "updated_at", "title?" }`. File-per-session (not a
  single shared file) avoids write races between concurrent sessions and makes reaping
  trivial. Matches gmr/m1ckc3s.
- **Hook → file writer**: ship a **bundled Swift CLI helper** (`claude-statusbar-hook`)
  inside the `.app`. Hooks call it with the event name; it reads stdin JSON and writes
  the session file. Avoids the `jq`/PATH fragility from Mnemo context. Hooks stay tiny,
  synchronous, fail-open (always `exit 0`, short timeout) so they never block Claude Code.
- **App shell**: `MenuBarExtra` (SwiftUI, macOS 13+) is simplest. Risk: colored/templated
  menu-bar icon control in `MenuBarExtra` is finicky — if a crisp colored dot isn't
  achievable, fall back to **AppKit `NSStatusItem`** (what mature apps use) for full
  rendering control. Decide early in implement with a spike.
- **Notifications**: `UNUserNotificationCenter` (requires real `.app` bundle + permission
  prompt). Fire only on **state transitions** (track previous state per session), not
  every poll. Respect per-project mute and configurable transition set. Sound via
  `UNNotificationSound`.
- **Aggregation**: priority RED > YELLOW > BLUE > GREEN > idle. Menu bar = worst state;
  dropdown = per-session list with elapsed-since-current-state timer.
- **App config**: `LSUIElement = true` (agent app, no Dock icon).
- **First-launch installer**: merge hook entries into `~/.claude/settings.json` and
  install the helper. **Must merge, never clobber** — Adil already has hooks (Mnemo
  recall, SessionEnd autolearn, Stop autolearn). Provide clean uninstall.

## Constraints (must NOT change / must hold)
- **Never break existing hooks.** Adil's `~/.claude/settings.json` has live Mnemo
  hooks (SessionStart recall, Stop/SessionEnd autolearn). The installer must merge into
  existing event arrays idempotently, not overwrite them.
- **Hooks must be synchronous** (not `async:true`) — else stdin is empty (verified).
- **Hooks must be non-blocking & fail-open** — short timeout, always `exit 0`; a broken
  status hook must never stall or fail a Claude Code turn.
- **No PATH assumptions in hooks** — absolute paths or bundled helper only.
- **Local-only, no network** — read/write under `~/.claude/` only.
- macOS only (Swift). Baseline target TBD (MenuBarExtra → macOS 13+; gmr targets 26.2+).

## Failure modes (watch during implement)
- **Clobbering Adil's Mnemo hooks** on install → silent loss of recall/autolearn. Highest
  risk. Merge-test against the real settings.json; back it up first.
- **Stuck state**: if `Stop` never fires (crash, `kill -9`, terminal closed), a session
  stays YELLOW/RED forever. Need staleness reaping by `updated_at` and/or PID liveness.
- **Wrong `notification_type` values** → red never triggers. Verify empirically.
- **Notification spam** on rapid PreToolUse/PostToolUse churn → only notify on
  transitions, and debounce yellow re-entry.
- **MenuBarExtra colored-icon limitation** → may force AppKit `NSStatusItem` rewrite.
  De-risk with an early spike.
- **Permission prompt for notifications** not granted → notifications silently fail;
  surface a setup check.
- **Race on concurrent writes** → mitigated by file-per-session + atomic write
  (write temp, rename).

## Out of scope
- Usage/quota/credit tracking (that's CodexBar's job — explicitly not this).
- Physical traffic-light hardware (the original Reddit inspiration). The same state
  files could later drive a USB/smart light, but not in v1.
- Windows/Linux (Swift macOS-only).
- Monitoring non-Claude-Code agents (Codex, Cursor, etc.).
- Auto-publishing/distribution (Sparkle updates, Homebrew cask) — later if it graduates.

## Open questions (resolved)
- **Build vs adopt?** → Build our own (gmr/claude-status is the fallback).
- **Stack?** → Swift / SwiftUI.
- **Scope?** → Full: detail dropdown + sound + per-project mute + transition filters +
  optional compacting state.
- **Single vs multi-session?** → Multi-session, worst-state-wins aggregation.

Still to settle in `adil:plan` (design-level, not blocking research):
- Min macOS target (drives MenuBarExtra vs NSStatusItem and WidgetKit availability).
- MenuBarExtra vs NSStatusItem for the icon (spike result decides).
- Helper-binary vs shell+absolute-jq for the hook writer (lean: bundled Swift helper).

## Acceptance criteria
1. Menu-bar icon reflects **aggregate** state across all running Claude Code sessions,
   updating within ~0.5s of a real state change.
2. Icon is **RED** when any session needs permission/input, **YELLOW** when any session
   is running (and none red), **GREEN** when all sessions are idle/done; optional **BLUE**
   while compacting.
3. A **desktop notification with sound** fires on the RED (needs you) and GREEN (done)
   **transitions**, respecting per-project mute and the configured transition set; no
   notification storms on rapid tool churn.
4. Dropdown lists each active session with **cwd**, **current state**, and **elapsed
   time** in that state.
5. First launch installs hooks + helper **without breaking** Adil's existing Mnemo hooks;
   uninstall removes only what it added. Verified against a backed-up real settings.json.
6. Stuck/stale sessions (no `Stop`, terminal killed) are reaped so the light doesn't lie.
7. All hooks are synchronous, fail-open, PATH-independent, and never block a CC turn.
