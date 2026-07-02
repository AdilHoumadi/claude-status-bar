import Foundation
import StatusCore

/// The persisted state of one Claude Code session, one JSON file per session under
/// `~/.claude/statusbar/<session_id>.json`.
///
/// `stateSince` (when the current state was entered) is deliberately distinct from
/// `updatedAt` (last write of any kind). The menu-bar elapsed timer reads `stateSince`
/// so it doesn't reset on every tool call; reaping reads `updatedAt`.
public struct SessionRecord: Codable, Sendable, Equatable {
    public var sessionId: String
    public var state: SessionState
    public var cwd: String?
    public var updatedAt: Date
    public var stateSince: Date

    public init(
        sessionId: String,
        state: SessionState,
        cwd: String?,
        updatedAt: Date,
        stateSince: Date
    ) {
        self.sessionId = sessionId
        self.state = state
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.stateSince = stateSince
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state
        case cwd
        case updatedAt = "updated_at"
        case stateSince = "state_since"
    }
}
