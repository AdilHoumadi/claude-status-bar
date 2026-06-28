import Foundation

/// Pure, structure-preserving merge of our status hooks into a Claude Code settings.json
/// object. Works on `[String: Any]` (JSONSerialization) rather than Codable so unknown
/// keys and other hooks (e.g. Mnemo's) are never dropped.
///
/// Our entries are identified by the marker substring in their command path, so merge is
/// idempotent and unmerge removes only what we added.
public enum SettingsJsonMerge {
    /// Substring that marks a hook entry as ours (the helper binary name).
    public static let marker = "claude-statusbar-hook"

    /// The hook events we register. Compaction maps to YELLOW; BLUE deferred (G9).
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse",
        "PostToolUse", "Notification", "Stop", "SessionEnd",
    ]

    public static func merge(into settings: [String: Any], hookCommand: String, timeout: Int = 5) -> [String: Any] {
        var result = settings
        var hooks = (result["hooks"] as? [String: Any]) ?? [:]
        for event in events {
            var groups = (hooks[event] as? [Any]) ?? []
            groups.removeAll { ($0 as? [String: Any]).map(isOurs) ?? false }  // idempotent
            groups.append(ourEntry(hookCommand: hookCommand, timeout: timeout))
            hooks[event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    public static func unmerge(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = result["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard var groups = value as? [Any] else { continue }
            groups.removeAll { ($0 as? [String: Any]).map(isOurs) ?? false }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)   // restore original cleanliness
            } else {
                hooks[event] = groups
            }
        }
        if hooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    /// True if a matcher-group dict is one of ours (its inner command contains the marker).
    public static func isOurs(_ group: [String: Any]) -> Bool {
        guard let inner = group["hooks"] as? [Any] else { return false }
        for handler in inner {
            if let command = (handler as? [String: Any])?["command"] as? String, command.contains(marker) {
                return true
            }
        }
        return false
    }

    static func ourEntry(hookCommand: String, timeout: Int) -> [String: Any] {
        // Synchronous (no `async`) with a short timeout: never block or fail a turn (Gap 6).
        ["matcher": "*", "hooks": [["type": "command", "command": hookCommand, "timeout": timeout]]]
    }
}
