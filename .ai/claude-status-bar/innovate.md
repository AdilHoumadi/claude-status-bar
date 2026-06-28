# Innovate: macOS menu-bar status light + notifications for Claude Code

**Slug:** claude-status-bar
**Date:** 2026-06-28
**Overall confidence:** 9.2 / 10  (High)
**Gaps assessed:** 9  |  Decided: 9  |  Deferred: 0

---

## Decisions

Listed in score order (highest first) — this is the order `adil:plan` should sequence them.

### G1 — What minimum macOS version should we target?
- **Chosen:** Option A — macOS 14 (Sonoma)
- **Score:** 9.5 / 10  (impact 4, fit 5, effort 1, risk 1)
- **Consequence:** Deployment target = macOS 14; mature `MenuBarExtra` and modern SwiftUI/UserNotifications are available; no back-compat shims needed.

### G3 — How should hooks write state files?
- **Chosen:** Option A — Bundled Swift CLI helper (`claude-statusbar-hook`)
- **Score:** 9.5 / 10  (impact 5, fit 5, effort 2, risk 1)
- **Consequence:** The app bundle ships a tiny Swift binary; hooks invoke it by absolute path to read stdin JSON and write the session file atomically. No `jq`/`python3`/PATH dependency. Build is multi-target (app + CLI). Must handle the in-bundle binary path moving across app updates.

### G6 — How do we avoid notification storms / notify only on real transitions?
- **Chosen:** Option A — App-side transition tracking
- **Score:** 9.5 / 10  (impact 5, fit 5, effort 2, risk 1)
- **Consequence:** All notification logic lives in the app: it holds previous state per session, fires only on notify-worthy transitions with a short debounce, and persists last-seen state across its own restarts to avoid a launch burst. Hooks stay dumb/fast. Enables the configurable transition filters required by full scope.

### G7 — Where should app settings live (per-project mute, transition filters)?
- **Chosen:** Option A — UserDefaults + SwiftUI Settings window
- **Score:** 9.5 / 10  (impact 5, fit 5, effort 2, risk 1)
- **Consequence:** Preferences stored in UserDefaults; a Settings scene (⌘,) exposes which transitions notify, sound on/off, and a per-project mute list. Need to build the per-project mute list UI.

### G8 — How should the app detect state-file changes?
- **Chosen:** Option A — Timer poll only (~0.5s)
- **Score:** 9.5 / 10  (impact 4, fit 5, effort 1, risk 1)
- **Consequence:** A single ~0.5s timer re-reads the state directory and also ticks the elapsed-time UI. No file-watcher complexity in v1. (Supersedes research's "watch + poll" instinct; add kqueue/FSEvents later only if 0.5s feels slow.)

### G9 — Should the BLUE "compacting" state ship in v1?
- **Chosen:** Option A — Defer BLUE to v1.1 (compaction = YELLOW)
- **Score:** 9.5 / 10  (impact 4, fit 5, effort 1, risk 1)
- **Consequence:** v1 ships RED/YELLOW/GREEN only; `PreCompact`/`PostCompact` map to YELLOW (busy). BLUE is a v1.1 add-on, not in scope now.

### G4 — How should the installer modify settings.json without breaking existing Mnemo hooks?
- **Chosen:** Option A — Idempotent merge + backup
- **Score:** 9.0 / 10  (impact 5, fit 5, effort 2, risk 2)
- **Consequence:** Installer backs up `~/.claude/settings.json`, merges our hook entries into existing event arrays keyed by a unique marker (command path contains `claude-statusbar`), is re-runnable without duplication, and uninstall removes only marked entries. Existing Mnemo hooks (recall/autolearn) are left untouched. Requires a structure-preserving JSON merge in Swift and a real-file merge test.

### G5 — How do we reap stale/stuck sessions when Stop never fires?
- **Chosen:** Option A — `updated_at` age-out only
- **Score:** 9.0 / 10  (impact 4, fit 5, effort 1, risk 2)
- **Consequence:** Each session file carries `updated_at`; the app drops any file past a TTL, while `SessionEnd` deletes on clean exit. No PID plumbing. Accepted risk: a very long single tool call (no hooks firing) may be wrongly reaped — a yellow session would just disappear from the bar (minor). TTL value is a tunable.

### G2 — How should we render the menu-bar icon?
- **Chosen:** Option B — MenuBarExtra only  *(rejected the higher-scored Option A)*
- **Score:** 8.0 / 10  (impact 4, fit 5, effort 2, risk 3)
- **Consequence:** All-SwiftUI `MenuBarExtra` for both the icon and the dropdown. Simplest path; **knowingly accepts the risk** that colored/template menu-bar icon control is finicky and may force an `NSStatusItem` rewrite of the icon layer later. Plan should keep the icon-rendering code isolated so that swap stays cheap if it's needed.

---

## Full option detail

### G1 — What minimum macOS version should we target?
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | macOS 14 (Sonoma) | 4 | 5 | 1 | 1 | 9.5 |
| B | macOS 13 (Ventura) | 4 | 4 | 1 | 1 | 9.0 |
| C | macOS 15 (Sequoia) | 4 | 5 | 1 | 2 | 9.0 |

- **A — macOS 14**: Target 14+. Mature `MenuBarExtra`, modern SwiftUI + UserNotifications; user's machine is macOS 15 so nothing lost. + Newest stable APIs + Trivial setting − Excludes Ventura (irrelevant for personal tool).
- **B — macOS 13**: Widest reach; `MenuBarExtra` first shipped here. + Broadest compat − A few 14+ conveniences unavailable.
- **C — macOS 15**: Matches the machine exactly. + Newest APIs − Breaks on older Macs.

### G2 — How should we render the menu-bar icon?
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | MenuBarExtra + NSStatusItem fallback (spike) | 5 | 5 | 2 | 1 | 9.5 |
| B | MenuBarExtra only | 4 | 5 | 2 | 3 | 8.0 |
| C | NSStatusItem (AppKit) | 5 | 4 | 3 | 2 | 8.0 |

- **A — Spike then decide**: Start SwiftUI `MenuBarExtra`; spike a crisp colored dot; fall back to `NSStatusItem` for just the icon layer if needed. + De-risks the known issue + Escape hatch − Possible throwaway spike work.
- **B — MenuBarExtra only** *(chosen)*: All-SwiftUI, least code. + Simplest + Pure SwiftUI − Colored-icon control finicky → rework risk.
- **C — NSStatusItem**: Full control (gmr's approach). + Any visual − More AppKit boilerplate for a Swift newcomer.

### G3 — How should hooks write state files?
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | Bundled Swift CLI helper | 5 | 5 | 2 | 1 | 9.5 |
| B | Shell + absolute-path jq | 4 | 3 | 1 | 3 | 7.5 |
| C | python3 inline script | 4 | 3 | 2 | 3 | 7.0 |

- **A — Bundled Swift helper** *(chosen)*: Binary in the `.app`, called by absolute path; reads stdin JSON, maps event→state, atomic write. + Kills jq/PATH fragility + One language − In-bundle path can move on update.
- **B — shell + jq**: + Simple/transparent − jq path varies per machine (caveman-hooks trap); clunky atomic writes.
- **C — python3**: + Easy JSON + known language − python3 not guaranteed on hook PATH / stock macOS.

### G4 — Installer settings.json merge
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | Idempotent merge + backup | 5 | 5 | 2 | 2 | 9.0 |
| B | Plugin / separate hooks file | 4 | 4 | 3 | 1 | 8.0 |
| C | Manual paste instructions | 3 | 3 | 1 | 2 | 7.5 |

- **A — Idempotent merge + backup** *(chosen)*: Backup, marker-keyed merge into existing arrays, clean uninstall. + Closes top failure mode + Reversible − Careful JSON merge in Swift.
- **B — Plugin/separate file**: Never touch settings.json. + Lowest clobber risk − Needs manual enable + packaging; depends on plugin hook maturity.
- **C — Manual instructions**: + Zero auto-write risk − Error-prone UX, defeats "wires it up for you".

### G5 — Reap stale/stuck sessions
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | updated_at age-out only | 4 | 5 | 1 | 2 | 9.0 |
| B | age-out + PID liveness | 5 | 4 | 3 | 2 | 8.0 |
| C | PID liveness only | 4 | 4 | 2 | 2 | 8.0 |

- **A — Age-out only** *(chosen)*: TTL drop + SessionEnd delete. + Dead simple − Long single tool call could be wrongly reaped (minor).
- **B — Age-out + PID**: + Definitive liveness − Fiddly PID capture from hooks.
- **C — PID only**: + No false reaping of long tasks − Needs reliable PID capture; PID-reuse edge.

### G6 — Notification storm prevention
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | App-side transition tracking | 5 | 5 | 2 | 1 | 9.5 |
| B | Structural: only RED/GREEN notify | 4 | 5 | 1 | 2 | 9.0 |
| C | Hook emits transition event | 4 | 3 | 3 | 3 | 6.5 |

- **A — App-side transition tracking** *(chosen)*: Previous-state-per-session in app, debounced, configurable. + Single source of truth + Hooks stay fast − Must persist last-seen across app restarts.
- **B — Structural**: Yellow never notifies. + No storm by construction − Can't ever notify on yellow.
- **C — Hook emits transition**: + Transition known at source − Fragile, file races, hard to configure.

### G7 — App settings storage
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | UserDefaults + Settings window | 5 | 5 | 2 | 1 | 9.5 |
| B | Menu-only toggles (UserDefaults) | 4 | 5 | 1 | 1 | 9.5 |
| C | JSON config file | 4 | 3 | 3 | 2 | 7.0 |

- **A — UserDefaults + Settings window** *(chosen)*: Prefs in UserDefaults, full Settings scene (⌘,). + Idiomatic, room to grow − Per-project list UI to build.
- **B — Menu-only toggles**: Same backing, toggles in dropdown. + Leanest, contextual − Clutters dropdown as options grow. (Can ship inside A.)
- **C — JSON config file**: + Human-editable − Reinvents UserDefaults; validation/watch work.

### G8 — State-file change detection
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | Timer poll only (~0.5s) | 4 | 5 | 1 | 1 | 9.5 |
| B | kqueue watch + poll fallback | 5 | 5 | 3 | 2 | 8.5 |
| C | FSEvents stream | 4 | 4 | 2 | 2 | 8.0 |

- **A — Poll only** *(chosen)*: ~0.5s timer re-reads dir + ticks elapsed UI. + Simple, robust, meets criterion − Not "instant"; tiny constant wakeups (negligible).
- **B — kqueue + poll**: + Instant + safety net − kqueue quirks, more code.
- **C — FSEvents**: + Native watcher − Default coalescing latency; still need a timer.

### G9 — Ship BLUE compacting state in v1?
| Option | Name | Impact | Fit | Effort | Risk | Score |
|---|---|---|---|---|---|---|
| A | Defer BLUE to v1.1 (compaction = yellow) | 4 | 5 | 1 | 1 | 9.5 |
| B | Include BLUE now | 4 | 4 | 2 | 2 | 8.0 |

- **A — Defer BLUE** *(chosen)*: RED/YELLOW/GREEN only; compaction = YELLOW. + Simpler v1 + Honest (compaction is busy) − Loses a minor signal.
- **B — Include BLUE now**: + Richer signal (gmr-like) − Extra state/tests for a brief, low-value moment; verify PostCompact.

---

## Deferred gaps
None. All 9 gaps decided.

(Note: G9 chose to *scope-defer the BLUE feature* to v1.1 — that is a made decision, not a deferred gap, so it does not penalise confidence.)

---

## Next step
Run `/adil:plan claude-status-bar` — `innovate.md` is the input.

Plan phases should implement the chosen options in score order (highest first):
**G1, G3, G6, G7, G8, G9 (9.5/9.5) → G4, G5 (9.0) → G2 (8.0)**.
Practical build sequence will interleave these (e.g. state schema + bundled helper first,
then app shell, then notifications, then installer), but where order is free, prefer the
higher-scored decision. Keep the icon-rendering code (G2) isolated so a later NSStatusItem
swap stays cheap. No deferred gaps to carry to out-of-scope; BLUE compacting is the only
explicit v1.1 item.
