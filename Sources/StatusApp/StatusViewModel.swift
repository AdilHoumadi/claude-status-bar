import Foundation
import StatusCore
import StatusStore

/// Polls the hook-driven state store (CLI / IDE / Claude Desktop Cowork all fire the hooks),
/// reaps stale sessions, applies the ignore list, and exposes the aggregate light plus the
/// per-session list. Clock is injected for testable elapsed.
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

    public func refresh() {
        let now = clock()

        store.reap(ttl: ttl, now: now)
        var all = store.readAll().map { record in
            SessionViewItem(
                id: record.sessionId,
                state: record.state,
                cwd: record.cwd,
                elapsed: max(0, now.timeIntervalSince(record.stateSince))
            )
        }

        // The hook helper already skips ignored cwds at write time; re-filter here so a
        // newly-added ignore hides matching sessions on the next poll.
        if !all.isEmpty {
            let prefixes = IgnoreList.prefixes(from: ignoreFileURL)
            if !prefixes.isEmpty {
                all = all.filter { !IgnoreList.isIgnored($0.cwd, prefixes: prefixes) }
            }
        }

        aggregate = SessionState.aggregate(all.map(\.state))
        sessions = all.sorted { $0.state.priority > $1.state.priority }  // worst-first
    }
}
