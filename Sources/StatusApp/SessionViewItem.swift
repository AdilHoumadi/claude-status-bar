import Foundation
import StatusCore

/// A single session as shown in the menu-bar dropdown.
public struct SessionViewItem: Equatable, Sendable, Identifiable {
    public let id: String          // sessionId
    public let state: SessionState
    public let cwd: String?
    public let elapsed: TimeInterval   // since the current state was entered

    public init(id: String, state: SessionState, cwd: String?, elapsed: TimeInterval) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.elapsed = elapsed
    }

    /// Last path component of `cwd`, for display. Falls back to the session id.
    public var displayName: String {
        guard let cwd, !cwd.isEmpty else { return String(id.prefix(8)) }
        return (cwd as NSString).lastPathComponent
    }
}
