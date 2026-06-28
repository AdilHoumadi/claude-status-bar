import Foundation
import StatusCore
import StatusStore

/// Polls the state store, reaps stale sessions, and exposes the aggregate light plus a
/// per-session list for the menu bar. Clock is injected so the elapsed timer is testable.
public final class StatusViewModel {
    private let store: StateStore
    private let ttl: TimeInterval
    private let clock: () -> Date

    public private(set) var aggregate: SessionState = .green
    public private(set) var sessions: [SessionViewItem] = []

    public init(store: StateStore, ttl: TimeInterval = 1800, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.ttl = ttl
        self.clock = clock
    }

    public func refresh() {
        let now = clock()
        store.reap(ttl: ttl, now: now)
        let records = store.readAll()
        aggregate = SessionState.aggregate(records.map(\.state))
        sessions = records
            .sorted { $0.state.priority > $1.state.priority }   // worst-first
            .map { record in
                SessionViewItem(
                    id: record.sessionId,
                    state: record.state,
                    cwd: record.cwd,
                    elapsed: max(0, now.timeIntervalSince(record.stateSince))
                )
            }
    }
}
