# Verify: macOS menu-bar status light + notifications for Claude Code

**Slug:** claude-status-bar
**Date:** 2026-06-28
**Verdict:** GO

The plan is structurally sound and executable as written. All 7 research ACs map to
phases; every phase test asserts behaviour and can fail RED before code; blast radius
matches the research architecture; no scope creep; no over-engineering. No Blockers.

However, adversarial review found **7 correctness Gaps** that will produce wrong behaviour
if not closed *inside their owning phase*. Two are high-priority (elapsed timer; helper
path stability). All have a specific fix and a home phase — none need a new phase or a
structural change, which is why this is GO rather than NO-GO.

## Findings

| Check | Severity | Finding | Fix |
|---|---|---|---|
| Problem match | — | ✓ All 7 research ACs map to phases (AC1→P1/P3, AC2→P1, AC3→P4, AC4→P3, AC5→P5, AC6→P2, AC7→P2). No orphan phases; nothing addressed outside the problem statement. | — |
| Missing cases | **Gap (P1)** | `StateMapper` behaviour is undefined for unknown `hook_event_name` and for `Notification` with a **non-red** `notification_type` (`auth_success`, `elicitation_dialog`, `elicitation_complete`, …). As written, any notification could be read as red → **false reds**, the core feature broken. | Default rule: `StateMapper` returns no-op (`.ignore`) for unknown events and for any `notification_type` other than `permission_prompt`/`idle_prompt`. Add test cases: `auth_success`→ignore, unknown event→ignore. |
| Missing cases | **Gap (P1+P2+P3, high)** | Elapsed timer (AC4) is wrong: `updated_at` is rewritten on every `PreToolUse`/`PostToolUse`, so "elapsed in current state" **resets on every tool call** during a long yellow run. The dropdown timer never climbs. | Add a `state_since` field to `SessionRecord`, distinct from `updated_at` (last-write, used for reaping). Helper preserves `state_since` when the state is unchanged (read-before-write upsert); elapsed = `now − state_since`. |
| Missing cases | **Gap (P2)** | `HookProcessor.apply` for a `.set` when **no file exists** (session started before install, or `SessionStart` hook absent) would no-op → that session never appears in the bar. | Make `.set` an **upsert** — create the session file if absent (default `cwd` from payload). |
| Missing cases | **Gap (P5, high)** | Helper-binary **path instability**: hooks pointing at the in-bundle binary break silently when the app is moved or auto-updated (research flagged this; plan names the risk but P5 has no fix). After the first update the whole mechanism dies quietly. | Install the helper to a **stable path** (`~/.claude/statusbar/bin/claude-statusbar-hook`), copy/refresh it on every app launch, and reference *that* path in the hook commands — not the bundle-internal path. |
| Missing cases | **Gap (P5)** | Installer assumes an existing `settings.json`. A fresh user (no file) and a **malformed** existing file are unhandled — the latter risks clobbering. | Missing file → create fresh with only our hooks (no backup needed). Malformed JSON → **abort without writing**, leave the file untouched, surface an error. Also handle missing `hooks` key / missing per-event arrays. |
| Missing cases | **Gap (P5)** | Installed hook entries must be **synchronous with a short timeout**. If `async:true` is ever set, stdin is dropped (the verified failure mode) and `session_id`/`notification_type` are empty; with no timeout a hung helper could stall a turn. | Register entries with no `async:true` and a small `timeout` (e.g. 5s). Add a test asserting generated entries are synchronous. |
| Missing cases | Nit (P1/P2) | `SessionStart` initial state undefined. | Default a newly created session to green/idle (it isn't working until `UserPromptSubmit`). |
| Missing cases | Nit (P4) | Notification-permission-denied UX unspecified. | Degrade silently; optional one-time setup hint in Settings. |
| Missing cases | Nit (P2/P4) | Reap TTL and debounce window values unspecified. | Pick concrete defaults in implement (e.g. TTL ~30 min, debounce ~2 s). |
| Test validity | — | ✓ Every phase test asserts a behaviour (output / file side-effect / published state / captured notification / merged object) and can fail RED before code. No structure-only tests. UI is correctly verified by running, with the ViewModel as the RED-able anchor. | — |
| Blast radius | — | ✓ Greenfield repo. All files are consistent with research's architecture section. The only external mutations — `~/.claude/settings.json` (P5) and `~/.claude/statusbar/` (P2) — are research-sanctioned, quarantined, backed up, and tested against a simulated file before touching the real one. | — |
| Simplicity | Nit | 6 source modules is on the granular side for a personal tool. | Acceptable — it's what makes `swift test` targeting clean. Collapse `StatusStore`→`StatusCore` / `StatusNotify`→`StatusApp` only if the boundaries feel heavy during implement. |
| Scope creep | — | ✓ Phases stay within research + innovate scope. `NSStatusItem`, BLUE state, usage tracking, kqueue/FSEvents, PID reaping are all out-of-scope and **not** built (P3 only *isolates* the icon code; it doesn't build the fallback). | — |

## Blockers (NO-GO reason)
None.

## Gaps (non-blocking — must be closed inside the owning phase)
1. **P1** — Define `StateMapper` no-op default for unknown events / non-red `notification_type` (prevents false reds). *Highest semantic risk; trivial fix.*
2. **P1+P2+P3** — Add `state_since` separate from `updated_at` so the elapsed timer (AC4) doesn't reset on every tool call. *High.*
3. **P5** — Install the helper to a stable path and reference it from hooks, so app updates/moves don't silently kill the mechanism. *High.*
4. **P2** — `.set` must upsert (create-if-missing) so pre-install sessions still appear.
5. **P5** — Handle missing settings.json (create fresh) and malformed settings.json (abort without clobber); handle missing `hooks`/event arrays.
6. **P5** — Ensure installed entries are synchronous (`async` off) with a short `timeout`.

## Nits
- `SessionStart` → default new session to green/idle.
- Notification permission denied → degrade silently + optional setup hint.
- Pick concrete TTL (~30 min) and debounce (~2 s) defaults.
- Consider fewer modules only if boundaries feel heavy.

## Next step
GO. Address the 6 Gaps within their owning phases during implementation (Gaps 1–3 are
must-fix for correctness). Run `/adil:implement claude-status-bar`.
