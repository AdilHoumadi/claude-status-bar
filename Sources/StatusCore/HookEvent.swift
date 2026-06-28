import Foundation

/// The subset of a Claude Code hook's stdin JSON payload that the status bar cares about.
///
/// Field names follow the hook contract: `session_id`, `hook_event_name`,
/// `notification_type`, `cwd`, `transcript_path`.
public struct HookEvent: Codable, Sendable, Equatable {
    public let sessionId: String
    public let hookEventName: String
    public let notificationType: String?
    public let cwd: String?
    public let transcriptPath: String?

    public init(
        sessionId: String,
        hookEventName: String,
        notificationType: String? = nil,
        cwd: String? = nil,
        transcriptPath: String? = nil
    ) {
        self.sessionId = sessionId
        self.hookEventName = hookEventName
        self.notificationType = notificationType
        self.cwd = cwd
        self.transcriptPath = transcriptPath
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case cwd
        case transcriptPath = "transcript_path"
    }
}
