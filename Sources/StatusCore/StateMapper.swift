import Foundation

/// What a hook event means for the session's persisted state.
public enum MapOutcome: Equatable, Sendable {
    /// Set the session to this state (upsert: create the record if missing).
    case set(SessionState)
    /// A session began — create an idle record.
    case create
    /// A session ended — remove the record.
    case remove
    /// Irrelevant event — do nothing.
    case ignore
}

/// Pure mapping from a hook event to a state outcome. No I/O.
public enum StateMapper {
    public static func outcome(for event: HookEvent) -> MapOutcome {
        // Events fired inside a subagent don't represent the session's own lifecycle: a
        // subagent finishing (Stop) or ending must NOT mark the session done/removed —
        // the main agent is still working. Tool use still counts as "busy" (yellow).
        let inSubagent = event.agentId != nil
        switch event.hookEventName {
        case "SessionStart":
            return inSubagent ? .ignore : .create
        case "SessionEnd":
            return inSubagent ? .ignore : .remove
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "PostCompact":
            return .set(.yellow)
        case "Stop":
            return inSubagent ? .ignore : .set(.green)
        case "Notification":
            // Only permission/idle prompts mean "waiting for the user". Every other
            // notification type (auth_success, elicitation_*, …) is irrelevant — never
            // let an unrelated notification flip the light red.
            switch event.notificationType {
            case "permission_prompt", "idle_prompt":
                return .set(.red)
            default:
                return .ignore
            }
        default:
            return .ignore
        }
    }
}
