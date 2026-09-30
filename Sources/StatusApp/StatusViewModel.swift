import Foundation
import StatusCore
import StatusStore

/// Polls the hook-driven state store (CLI / IDE / Claude Desktop Cowork all fire the hooks),
/// reaps stale sessions, applies the ignore list, and exposes the aggregate light plus the
/// per-session list. Clock is injected for testable reaping.
///
/// Note: Desktop Cowork sessions run the Claude Code engine, so they fire the same hooks
/// (including SessionEnd on close) — no separate transcript source is needed, and closed
/// sessions drop off promptly instead of lingering.
public final class StatusViewModel {
    private let store: StateStore
    private let ignoreFileURL: URL
    private let ttl: TimeInterval
    private let clock: () -> Date

    public private(set) var aggregate: SessionState = .green
    public private(set) var sessions: [SessionViewItem] = []

    public init(
        store: StateStore,
        ignoreFileURL: URL = IgnoreList.defaultFileURL(),
        ttl: TimeInterval = 1800,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.ignoreFileURL = ignoreFileURL
        self.ttl = ttl
        self.clock = clock
    }

    /// Re-reads the store. Returns true when the aggregate or the session list changed, so
    /// callers only republish (and re-render) on a real change.
    @discardableResult
    public func refresh() -> Bool {
        let now = clock()

        // One directory read per refresh: reap stale records from it instead of re-reading.
        var all: [SessionViewItem] = []
        for record in store.readAll() {
            if now.timeIntervalSince(record.updatedAt) > ttl {
                store.delete(record.sessionId)
                continue
            }
            all.append(SessionViewItem(
                id: record.sessionId,
                state: record.state,
                cwd: record.cwd,
                stateSince: record.stateSince
            ))
        }

        // The hook helper already skips ignored cwds at write time; re-filter here so a
        // newly-added ignore hides matching sessions on the next poll.
        if !all.isEmpty {
            let prefixes = IgnoreList.prefixes(from: ignoreFileURL)
            if !prefixes.isEmpty {
                all = all.filter { !IgnoreList.isIgnored($0.cwd, prefixes: prefixes) }
            }
        }

        let newAggregate = SessionState.aggregate(all.map(\.state))
        // Worst-first; ties by id so the order is stable and equal lists compare equal.
        let newSessions = all.sorted {
            $0.state.priority != $1.state.priority ? $0.state.priority > $1.state.priority : $0.id < $1.id
        }
        guard newAggregate != aggregate || newSessions != sessions else { return false }
        aggregate = newAggregate
        sessions = newSessions
        return true
    }
}
