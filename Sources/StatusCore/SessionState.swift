import Foundation

/// The activity state of a single Claude Code session, mapped to a traffic-light colour.
public enum SessionState: String, Codable, Sendable, CaseIterable {
    /// Waiting for the user (permission prompt or idle prompt).
    case red
    /// Running (prompt submitted, tool use, compaction).
    case yellow
    /// Idle / turn finished, ready for the next task.
    case green

    /// Higher wins when aggregating across sessions (red > yellow > green).
    public var priority: Int {
        switch self {
        case .red: return 3
        case .yellow: return 2
        case .green: return 1
        }
    }

    /// Worst-state-wins aggregate across all sessions. Empty → `.green` (nothing active).
    public static func aggregate(_ states: [SessionState]) -> SessionState {
        states.max(by: { $0.priority < $1.priority }) ?? .green
    }
}
