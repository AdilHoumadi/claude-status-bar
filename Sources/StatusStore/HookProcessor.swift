import Foundation
import StatusCore

/// Applies a hook event to the store: the testable core that the `claude-statusbar-hook`
/// executable's `main` calls.
public enum HookProcessor {
    public static func apply(_ event: HookEvent, store: StateStore, now: Date) {
        switch StateMapper.outcome(for: event) {
        case .ignore:
            return
        case .remove:
            store.delete(event.sessionId)
        case .create:
            // A session began. Create it idle (green); on resume, keep the existing
            // record and just refresh its liveness timestamp.
            if var existing = store.read(event.sessionId) {
                existing.updatedAt = now
                if existing.cwd == nil { existing.cwd = event.cwd }
                try? store.write(existing)
            } else {
                try? store.write(SessionRecord(
                    sessionId: event.sessionId, state: .green, cwd: event.cwd,
                    updatedAt: now, stateSince: now
                ))
            }
        case .set(let state):
            // Upsert (Gap 4): a session that predates install / never saw SessionStart
            // still appears. stateSince only moves on a real state change (Gap 2).
            if var record = store.read(event.sessionId) {
                if record.state != state {
                    record.state = state
                    record.stateSince = now
                }
                record.updatedAt = now
                if let cwd = event.cwd { record.cwd = cwd }
                try? store.write(record)
            } else {
                try? store.write(SessionRecord(
                    sessionId: event.sessionId, state: state, cwd: event.cwd,
                    updatedAt: now, stateSince: now
                ))
            }
        }
    }
}
