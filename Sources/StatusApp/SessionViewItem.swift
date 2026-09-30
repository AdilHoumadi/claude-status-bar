import Foundation
import StatusCore

/// A single session as shown in the menu-bar dropdown.
public struct SessionViewItem: Equatable, Sendable, Identifiable {
    public let id: String          // sessionId
    public let state: SessionState
    public let cwd: String?
    public let stateSince: Date        // when the current state was entered

    public init(id: String, state: SessionState, cwd: String?, stateSince: Date) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.stateSince = stateSince
    }

    /// Time spent in the current state. Derived at render time (not stored) so an unchanged
    /// session compares equal between refreshes and doesn't republish the UI every tick.
    public func elapsed(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(stateSince))
    }

    /// Last path component of `cwd`, for display. Falls back to the session id.
    public var displayName: String {
        guard let cwd, !cwd.isEmpty else { return String(id.prefix(8)) }
        return (cwd as NSString).lastPathComponent
    }
}
