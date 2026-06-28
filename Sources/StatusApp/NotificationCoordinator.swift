import Foundation
import StatusCore

/// A notification the app should post when a session changes state.
public struct AppNotification: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case needsYou   // entered red
        case started    // entered yellow (running)
        case done       // entered green
    }
    public let kind: Kind
    public let sessionId: String
    public let projectName: String

    public init(kind: Kind, sessionId: String, projectName: String) {
        self.kind = kind
        self.sessionId = sessionId
        self.projectName = projectName
    }
}

/// User-configurable notification behaviour (a pure value so the coordinator is testable).
public struct NotificationSettings: Sendable, Equatable {
    public var notifyStates: Set<SessionState>   // which entered-states notify
    public var soundEnabled: Bool
    public var mutedProjects: Set<String>        // cwd paths to silence
    public var debounceInterval: TimeInterval

    public init(
        notifyStates: Set<SessionState> = [.red, .green],
        soundEnabled: Bool = true,
        mutedProjects: Set<String> = [],
        debounceInterval: TimeInterval = 5
    ) {
        self.notifyStates = notifyStates
        self.soundEnabled = soundEnabled
        self.mutedProjects = mutedProjects
        self.debounceInterval = debounceInterval
    }
}

/// Decides which notifications to fire as sessions change state. Tracks last-seen state
/// per session and the last fire time per (session, state) for debouncing. First sighting
/// of a session records only (no notification) so app launch never floods.
public final class NotificationCoordinator {
    private var lastSeen: [String: SessionState] = [:]
    private var lastFired: [String: Date] = [:]

    public init() {}

    public func process(
        sessions: [SessionViewItem],
        settings: NotificationSettings,
        now: Date
    ) -> [AppNotification] {
        var fired: [AppNotification] = []
        for session in sessions {
            let previous = lastSeen[session.id]
            lastSeen[session.id] = session.state

            guard let previous else { continue }            // first sighting: record only
            guard previous != session.state else { continue }  // no transition
            guard settings.notifyStates.contains(session.state) else { continue }
            guard let kind = kind(for: session.state) else { continue }
            if let cwd = session.cwd, settings.mutedProjects.contains(cwd) { continue }

            let key = "\(session.id)|\(session.state.rawValue)"
            if let last = lastFired[key], now.timeIntervalSince(last) < settings.debounceInterval {
                continue  // debounce repeats of the same target state
            }
            lastFired[key] = now
            fired.append(AppNotification(kind: kind, sessionId: session.id, projectName: session.displayName))
        }
        return fired
    }

    private func kind(for state: SessionState) -> AppNotification.Kind? {
        switch state {
        case .red: return .needsYou
        case .yellow: return .started
        case .green: return .done
        }
    }
}
