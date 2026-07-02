import Foundation

/// The subset of a Claude Code hook's stdin JSON payload that the status bar cares about.
///
/// Field names follow the hook contract: `session_id`, `hook_event_name`,
/// `notification_type`, `cwd`, `agent_id`. Unknown keys in the payload are ignored.
public struct HookEvent: Codable, Sendable, Equatable {
    public let sessionId: String
    public let hookEventName: String
    public let notificationType: String?
    public let cwd: String?
    /// Present when the hook fires inside a subagent — the session is still working.
    public let agentId: String?

    public init(
        sessionId: String,
        hookEventName: String,
        notificationType: String? = nil,
        cwd: String? = nil,
        agentId: String? = nil
    ) {
        self.sessionId = sessionId
        self.hookEventName = hookEventName
        self.notificationType = notificationType
        self.cwd = cwd
        self.agentId = agentId
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case cwd
        case agentId = "agent_id"
    }
}
