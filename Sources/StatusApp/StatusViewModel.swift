import Foundation
import StatusCore
import StatusStore

/// Polls the state store (hook-driven CLI/IDE sessions) plus the optional Desktop source
/// (Cowork / Code tab), reaps stale sessions, applies the ignore list, and exposes the
/// aggregate light plus a merged per-session list. Clock is injected for testable elapsed.
public final class StatusViewModel {
    private let store: StateStore
    private let desktop: DesktopSessionSource?
    private let ignoreFileURL: URL
    private let ttl: TimeInterval
    private let clock: () -> Date

    public private(set) var aggregate: SessionState = .green
    public private(set) var sessions: [SessionViewItem] = []

    public init(
        store: StateStore,
        desktop: DesktopSessionSource? = nil,
        ignoreFileURL: URL = IgnoreList.defaultFileURL(),
        ttl: TimeInterval = 1800,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.desktop = desktop
        self.ignoreFileURL = ignoreFileURL
        self.ttl = ttl
        self.clock = clock
    }

    public func refresh() {
        let now = clock()

        store.reap(ttl: ttl, now: now)
        let hookItems = store.readAll().map { record in
            SessionViewItem(
                id: record.sessionId,
                state: record.state,
                cwd: record.cwd,
                elapsed: max(0, now.timeIntervalSince(record.stateSince))
            )
        }

        // Claude Desktop's Cowork / Code-tab sessions run the Claude Code engine, so they
        // ALSO fire the hooks — with a *different* session id but the same folder. Drop any
        // Desktop session whose cwd already has a hook session so the same work isn't shown
        // twice (CLI + APP). Desktop items survive only for folders with no hook coverage.
        let hookCwds = Set(hookItems.compactMap { $0.cwd.map(Self.normalizePath) })
        let desktopItems = (desktop?.sessions(now: now, ttl: ttl) ?? []).filter { item in
            guard let cwd = item.cwd.map(Self.normalizePath) else { return true }
            return !hookCwds.contains(cwd)
        }

        // The hook helper already skips ignored cwds; Desktop sessions have no hook, so
        // filter them here (and re-filter hook items so a newly-added ignore hides them fast).
        var all = hookItems + desktopItems
        if !all.isEmpty {
            let prefixes = IgnoreList.prefixes(from: ignoreFileURL)
            if !prefixes.isEmpty {
                all = all.filter { !IgnoreList.isIgnored($0.cwd, prefixes: prefixes) }
            }
        }

        aggregate = SessionState.aggregate(all.map(\.state))
        sessions = all.sorted { $0.state.priority > $1.state.priority }  // worst-first
    }

    /// Normalize a cwd for cross-source matching: drop a trailing slash so "/a" and "/a/"
    /// compare equal.
    static func normalizePath(_ path: String) -> String {
        var s = path
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
