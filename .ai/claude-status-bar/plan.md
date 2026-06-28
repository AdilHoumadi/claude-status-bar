# Plan: macOS menu-bar status light + notifications for Claude Code

**Slug:** claude-status-bar
**Date:** 2026-06-28
**Research:** .ai/claude-status-bar/research.md
**Innovate:** .ai/claude-status-bar/innovate.md

## Architecture decision (plan-level)
All testable logic lives in a **SwiftPM package** (`swift test`-able, fast, no Xcode
GUI in the loop). The macOS app is a **thin Xcode SwiftUI target** that depends on the
package and contains only views + wiring. This keeps every phase anchored on a real
behavioral test, since `MenuBarExtra`/Settings UI cannot be unit-tested but mappers,
stores, view-models, coordinators, and the installer can.

```
claude-status-bar/
  Package.swift                         # macOS 14; libs + CLI executable + test targets
  Sources/
    StatusCore/                         # P1: SessionState, HookEvent, StateMapper, aggregate
    StatusStore/                        # P2: SessionRecord, StateStore, HookProcessor, paths
    claude-statusbar-hook/              # P2: CLI executable (thin main → HookProcessor)
    StatusApp/                          # P3: StatusViewModel, SessionViewItem (logic only)
    StatusNotify/                       # P4: Settings, NotificationCoordinator, Notifier
    StatusInstall/                      # P5: SettingsJsonMerge, HookInstaller
  Tests/
    StatusCoreTests/ StatusStoreTests/ StatusAppTests/ StatusNotifyTests/ StatusInstallTests/
  App/                                  # Xcode app target (MenuBarExtra shell)
    ClaudeStatusBar.xcodeproj
    ClaudeStatusBarApp.swift  SettingsView.swift  Info.plist (LSUIElement=true)
```

State-file contract (written by P2, read by P3/P4):
`~/.claude/statusbar/<session_id>.json` → `{session_id, state, cwd, updated_at, title?}`.
One file per session (avoids concurrent-write races; trivial reaping).

Hook design (all phases depend on these invariants from research):
- Synchronous (never `async:true` — stdin is dropped for async hooks).
- Always `exit 0` (fail-open; a broken status hook must never block a Claude Code turn).
- Invoked by **absolute path** to the bundled binary (no PATH/jq/python assumptions).
- One `settings.json` entry per event, all pointing at the same binary; the binary
  branches on `hook_event_name` read from stdin.

## Phases

### P1 — Domain core: state model, event→state mapping, aggregation
- **Test:** `StateMapperTests` — asserts `Notification`+`notification_type:"permission_prompt"`→`.red`, `"idle_prompt"`→`.red`; `UserPromptSubmit`/`PreToolUse`/`PostToolUse`/`PreCompact`/`PostCompact`→`.yellow`; `Stop`→`.green`; `SessionStart`→`.create`; `SessionEnd`→`.remove`. `AggregationTests` — `aggregate([.yellow,.red,.green])==.red`; all-green→`.green`; empty→idle/green (worst-state-wins: red>yellow>green).
- **Files:** `Package.swift`, `Sources/StatusCore/SessionState.swift`, `Sources/StatusCore/HookEvent.swift`, `Sources/StatusCore/StateMapper.swift`, `Tests/StatusCoreTests/StateMapperTests.swift`, `Tests/StatusCoreTests/AggregationTests.swift`.
- **Delta:** Create the SwiftPM package (platform macOS 14). `SessionState` enum with priority ordering + `static func aggregate(_:)`. `HookEvent` Codable payload (`session_id`, `hook_event_name`, `notification_type?`, `cwd`, `transcript_path?`). `StateMapper.outcome(for: HookEvent) -> MapOutcome` (`.set(SessionState)` / `.create` / `.remove`). Compaction maps to `.yellow` (G9: BLUE deferred to v1.1).
- **AC:** `swift test` green for `StatusCoreTests`; mapping table matches research's hook→state table (research AC#2); aggregation is worst-state-wins (research AC#1 logic half).
- **Dependencies:** none.

### P2 — Hook helper CLI + state-file store (atomic I/O + reaping)
- **Test:** `HookProcessorTests` — given a decoded `HookEvent`, `HookProcessor.apply(_:store:)` writes/updates the correct session file for a `.set`, creates on `.create`, deletes the file on `.remove`. `StateStoreTests` — `write`→`readAll` round-trips a `SessionRecord`; write is atomic (temp file + rename, no partial reads); `reap(ttl, now)` drops records whose `updated_at` is older than TTL and keeps fresh ones; `delete(sessionId)` removes the file.
- **Files:** `Sources/StatusStore/StatusPaths.swift`, `Sources/StatusStore/SessionRecord.swift`, `Sources/StatusStore/StateStore.swift`, `Sources/StatusStore/HookProcessor.swift`, `Sources/claude-statusbar-hook/main.swift`, `Tests/StatusStoreTests/StateStoreTests.swift`, `Tests/StatusStoreTests/HookProcessorTests.swift`, `Package.swift` (add `StatusStore` lib, `claude-statusbar-hook` executable, tests).
- **Delta:** `StateStore` resolves `~/.claude/statusbar/`, creates it if missing, does atomic writes (write temp → `rename`), `readAll()` parsing each JSON (skipping corrupt files), `reap(ttl:now:)` (G5 age-out only), `delete()`. `HookProcessor` = the testable function `main.swift` calls. `main.swift` reads all of stdin, decodes `HookEvent`, calls `HookProcessor`, and **always exits 0** (catches/ignores all errors → fail-open).
- **AC:** `swift test` green for `StatusStoreTests`; piping a sample `Notification` payload to the built binary creates `~/.claude/statusbar/<id>.json` with `state:"red"` (research AC#2, #6, #7); stale records reaped by TTL (research AC#6); binary exits 0 even on malformed input (research AC#7).
- **Dependencies:** P1.

### P3 — Menu-bar app shell: poll, aggregate, icon + session dropdown
- **Test:** `StatusViewModelTests` — seed a `StateStore` (temp dir) with files in mixed states; after `viewModel.refresh()`, `viewModel.aggregate == .red` (worst); `viewModel.sessions` lists each with correct `cwd`, `state`, and `elapsed` computed from `updated_at` against an **injected clock**; reaping runs on refresh so stale files drop out of the list.
- **Files:** `Sources/StatusApp/StatusViewModel.swift`, `Sources/StatusApp/SessionViewItem.swift`, `Tests/StatusAppTests/StatusViewModelTests.swift`, `App/ClaudeStatusBar.xcodeproj`, `App/ClaudeStatusBarApp.swift`, `App/Info.plist`, `Package.swift` (add `StatusApp` lib + tests).
- **Delta:** `StatusViewModel` (`ObservableObject`): a 0.5s timer (G8 poll-only) triggers `refresh()` → `reap` + `readAll` + `aggregate`, publishing icon color + `[SessionViewItem]`. Clock injected for testability. Xcode app target: `MenuBarExtra` whose label is a colored dot derived from `aggregate` (G2 MenuBarExtra-only — **keep the icon/dot rendering in one small isolated view** so a later `NSStatusItem` swap is cheap if color control disappoints); dropdown renders `viewModel.sessions` (cwd, state, elapsed). `Info.plist` sets `LSUIElement=true` (no Dock icon).
- **AC:** `swift test` green for `StatusAppTests`; app builds and launches; menu-bar dot reflects the aggregate state and updates within ~0.5s of a state file changing (research AC#1); dropdown shows each active session's cwd/state/elapsed (research AC#4).
- **Dependencies:** P1, P2.

### P4 — Notifications + settings (transitions, debounce, sound, mute, filters)
- **Test:** `NotificationCoordinatorTests` — `decide(previous:.yellow,current:.red,...)` emits one "needs you" notification; `→.green` emits one "done"; a project in `settings.mutedProjects` emits nothing; a transition not in `settings.enabledTransitions` emits nothing; a rapid `.red→.yellow→.red` within the debounce window emits the red once; identical consecutive states emit nothing. A fake `Notifier` captures emissions; coordinator persists last-seen state so a restart with unchanged files emits nothing.
- **Files:** `Sources/StatusNotify/Settings.swift`, `Sources/StatusNotify/NotificationCoordinator.swift`, `Sources/StatusNotify/Notifier.swift`, `Tests/StatusNotifyTests/NotificationCoordinatorTests.swift`, `App/SettingsView.swift`, `App/ClaudeStatusBarApp.swift` (wire coordinator into refresh; add Settings scene), `Package.swift` (add `StatusNotify` lib + tests).
- **Delta:** `Settings` reads UserDefaults (`enabledTransitions`, `soundEnabled`, `mutedProjects`) with sane defaults (notify on RED + GREEN). `NotificationCoordinator` (G6 app-side transition tracking): pure `decide(previous,current,settings,now)` returning notifications, with debounce + last-seen persistence. `Notifier` protocol; production impl wraps `UNUserNotificationCenter` (requests permission, plays `UNNotificationSound` when `soundEnabled`). `StatusViewModel.refresh()` feeds prev/next per-session states into the coordinator. SwiftUI `Settings` scene (⌘,) (G7) with toggles + per-project mute list.
- **AC:** `swift test` green for `StatusNotifyTests`; a real session hitting a permission prompt produces a desktop notification with sound; muting a project silences it; no notification storm under rapid tool churn (research AC#3).
- **Dependencies:** P1, P3.

### P5 — Installer: idempotent settings.json merge + backup + uninstall
- **Test:** `SettingsJsonMergeTests` — given a `settings.json` object that already contains existing Mnemo hooks (`SessionStart` recall, `Stop`/`SessionEnd` autolearn), `merge(into:hooks:marker:)` leaves every Mnemo hook intact and adds our marker-tagged entries; calling `merge` twice produces no duplicates (idempotent); `unmerge(marker:)` removes only our entries and leaves the Mnemo hooks; the operation works on an in-memory/temp object, never the real `~/.claude`.
- **Files:** `Sources/StatusInstall/SettingsJsonMerge.swift`, `Sources/StatusInstall/HookInstaller.swift`, `Tests/StatusInstallTests/SettingsJsonMergeTests.swift`, `App/SettingsView.swift` (Install/Uninstall buttons), `App/ClaudeStatusBarApp.swift` (first-launch install prompt), `Package.swift` (add `StatusInstall` lib + tests).
- **Delta:** `SettingsJsonMerge` (pure, structure-preserving): merge our per-event command entries (each tagged via a marker — command path contains `claude-statusbar`) into the existing `hooks` arrays; `unmerge` filters them out. `HookInstaller`: before writing, copy `settings.json`→`settings.json.bak`; resolve the absolute path of the bundled `claude-statusbar-hook` binary; write merged result atomically. First-launch flow offers install; Settings exposes Install/Uninstall. Covers the 7 events from research (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop, SessionEnd).
- **AC:** `swift test` green for `StatusInstallTests`; installing against a **backed-up copy of the real settings.json** preserves Mnemo hooks and adds ours; uninstall restores the original set; `settings.json.bak` exists after install (research AC#5).
- **Dependencies:** P1, P2 (needs the helper binary path to reference in the hook command).

## Out of scope
- **Usage/quota/credit tracking** (CodexBar's domain) — not this tool.
- **BLUE "compacting" state** — deferred to v1.1 (innovate G9); compaction = YELLOW in v1.
- **`NSStatusItem` icon path / spike** — only if MenuBarExtra colored-dot control fails (innovate G2 accepted that risk); not built now, kept cheap via isolated rendering.
- **Physical traffic-light hardware** — the same state files could drive it later; not v1.
- **kqueue/FSEvents file watching** — poll-only in v1 (innovate G8); add later only if 0.5s feels slow.
- **PID-liveness reaping** — age-out only in v1 (innovate G5).
- **Plugin packaging / Sparkle auto-update / Homebrew cask** — distribution is later.
- **Windows/Linux; non-Claude-Code agents (Codex, Cursor)** — macOS + Claude Code only.
- **Empirical verification of exact `notification_type` matcher values** — a P1/P2 implementation task (log raw stdin from a real session before hard-coding), not a separate phase.

## Rollback
| Phase | Rollback |
|---|---|
| P1 | Revert commit. Pure new package code; nothing depends on it yet. Nothing to undo. |
| P2 | Revert commit. Helper only writes to the new `~/.claude/statusbar/` dir — `rm -rf` it. Real settings.json untouched. |
| P3 | Revert commit. App not installed/distributed; deleting the build is sufficient. No external state. |
| P4 | Revert commit, or disable at runtime (Settings → clear `enabledTransitions`). Notifications are additive; no persisted external state beyond UserDefaults (resettable). |
| P5 | **The only phase that mutates `~/.claude/settings.json`.** Undo = run Uninstall (removes marker-tagged entries) **and/or** restore `settings.json.bak` written before the merge. Verify Mnemo hooks present after restore. |

## Next step
Run `/adil:verify claude-status-bar` to quality-gate this plan before writing any code.
