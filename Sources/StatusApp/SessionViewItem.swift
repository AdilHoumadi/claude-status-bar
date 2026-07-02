import Foundation
import StatusCore

/// Where a session comes from — drives the small badge in the dropdown.
public enum SessionSource: String, Sendable, Equatable {
    case claudeCode  // hook-driven: CLI or IDE extension
    case desktop     // Claude Desktop Cowork / Code tab (read from transcripts)

    public var badge: String { self == .desktop ? "APP" : "CLI" }
}

/// A single session as shown in the menu-bar dropdown.
public struct SessionViewItem: Equatable, Sendable, Identifiable {
    public let id: String          // sessionId
    public let state: SessionState
    public let cwd: String?
    public let elapsed: TimeInterval   // since the current state was entered
    public let source: SessionSource

    public init(id: String, state: SessionState, cwd: String?, elapsed: TimeInterval,
                source: SessionSource = .claudeCode) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.elapsed = elapsed
        self.source = source
    }

    /// Last path component of `cwd`, for display. Falls back to the session id.
    public var displayName: String {
        guard let cwd, !cwd.isEmpty else { return String(id.prefix(8)) }
        return (cwd as NSString).lastPathComponent
    }
}
