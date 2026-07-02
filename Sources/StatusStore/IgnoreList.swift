import Foundation

/// Decides whether a session should be ignored entirely (not captured) based on its cwd.
/// Used to keep automated/headless Claude runs (e.g. background jobs that shell out to
/// `claude -p`) out of the status bar. Prefixes are read from a plain file, one path per
/// line; blank lines and `#` comments are ignored.
public enum IgnoreList {
    public static func defaultFileURL() -> URL {
        StateStore.defaultDirectory().appendingPathComponent("ignore.txt")
    }

    public static func prefixes(from url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map(expandTilde)
    }

    public static func isIgnored(_ cwd: String?, prefixes: [String]) -> Bool {
        guard let cwd else { return false }
        return prefixes.contains { prefix in
            cwd == prefix || cwd.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
        }
    }

    public static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + path.dropFirst(1)
    }
}
