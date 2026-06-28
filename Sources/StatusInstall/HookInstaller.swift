import Foundation

/// Installs/uninstalls the status hooks into a Claude Code settings.json. All paths are
/// injectable so tests run against temp dirs, never the real `~/.claude`.
public struct HookInstaller {
    public let settingsURL: URL
    public let binDir: URL
    public let helperSource: URL
    public let timeout: Int

    public init(settingsURL: URL, binDir: URL, helperSource: URL, timeout: Int = 5) {
        self.settingsURL = settingsURL
        self.binDir = binDir
        self.helperSource = helperSource
        self.timeout = timeout
    }

    public static func defaultInstaller(helperSource: URL, timeout: Int = 5) -> HookInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return HookInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            binDir: home.appendingPathComponent(".claude/statusbar/bin", isDirectory: true),
            helperSource: helperSource,
            timeout: timeout
        )
    }

    /// Stable path the hooks point at, so app moves/updates don't break them (Gap 3).
    public var stableHelperPath: URL { binDir.appendingPathComponent("claude-statusbar-hook") }

    public enum InstallError: Error { case malformedSettings }

    public func install() throws {
        try installHelperBinary()
        let settings = try loadSettingsForWrite()   // missing → empty; malformed → throws (no clobber)
        try backupIfPresent()
        let merged = SettingsJsonMerge.merge(into: settings, hookCommand: stableHelperPath.path, timeout: timeout)
        try writeSettings(merged)
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let settings = try loadSettingsStrict()
        try writeSettings(SettingsJsonMerge.unmerge(from: settings))
    }

    // MARK: - Internals

    private func installHelperBinary() throws {
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: stableHelperPath)
        try FileManager.default.copyItem(at: helperSource, to: stableHelperPath)
    }

    private func loadSettingsForWrite() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        return try loadSettingsStrict()
    }

    private func loadSettingsStrict() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw InstallError.malformedSettings   // abort — never overwrite an unparseable file
        }
        return dict
    }

    private func backupIfPresent() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let backup = settingsURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: settingsURL, to: backup)
    }

    private func writeSettings(_ dict: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: [.atomic])
    }
}
