import Foundation
import StatusInstall
import TestSupport

// --- helpers for reading the [String: Any] settings shape ---
private func groups(_ s: [String: Any], _ event: String) -> [[String: Any]] {
    ((s["hooks"] as? [String: Any])?[event] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
}
private func countOurs(_ s: [String: Any], _ event: String) -> Int {
    groups(s, event).filter { SettingsJsonMerge.isOurs($0) }.count
}
private func hasCommand(_ s: [String: Any], _ event: String, _ command: String) -> Bool {
    groups(s, event).contains { group in
        ((group["hooks"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? [])
            .contains { ($0["command"] as? String) == command }
    }
}

func settingsJsonMergeTests() -> TestSuite { ("SettingsJsonMergeTests", { t in
    // Existing third-party hooks on SessionStart and Stop, plus an unrelated top-level key.
    let existingStart: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "/other-tool/on-start.sh"]]]
    let existingStop: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "/other-tool/on-stop.sh"]]]
    let settings: [String: Any] = [
        "hooks": ["SessionStart": [existingStart], "Stop": [existingStop]],
        "model": "opus",
    ]
    let cmd = "/Users/x/.claude/statusbar/bin/claude-statusbar-hook"

    let merged = SettingsJsonMerge.merge(into: settings, hookCommand: cmd, timeout: 5)

    // existing third-party hooks preserved
    t.expect(hasCommand(merged, "SessionStart", "/other-tool/on-start.sh"), "existing SessionStart preserved")
    t.expect(hasCommand(merged, "Stop", "/other-tool/on-stop.sh"), "existing Stop preserved")
    // our entry added to every event
    for e in SettingsJsonMerge.events { t.expectEqual(countOurs(merged, e), 1) }
    // SessionStart now holds both existing + ours
    t.expectEqual(groups(merged, "SessionStart").count, 2)
    // unrelated top-level key untouched
    t.expectEqual(merged["model"] as? String, "opus")
    // synchronous + timeout (Gap 6)
    let ourGroup = groups(merged, "Stop").first { SettingsJsonMerge.isOurs($0) }
    t.expect(ourGroup != nil, "our entry present on Stop")
    let inner = (ourGroup?["hooks"] as? [Any])?.first as? [String: Any]
    t.expectEqual(inner?["timeout"] as? Int, 5)
    t.expect((inner?.keys.contains("async") ?? false) == false, "no async key (must stay synchronous)")

    // idempotent — merging again does not duplicate
    let twice = SettingsJsonMerge.merge(into: merged, hookCommand: cmd, timeout: 5)
    for e in SettingsJsonMerge.events { t.expectEqual(countOurs(twice, e), 1) }
    t.expectEqual(groups(twice, "SessionStart").count, 2)

    // unmerge removes only ours; existing survives; events we created are cleaned up
    let un = SettingsJsonMerge.unmerge(from: twice)
    for e in SettingsJsonMerge.events { t.expectEqual(countOurs(un, e), 0) }
    t.expect(hasCommand(un, "SessionStart", "/other-tool/on-start.sh"), "existing survives unmerge")
    t.expect(hasCommand(un, "Stop", "/other-tool/on-stop.sh"), "existing Stop survives unmerge")
    t.expect((un["hooks"] as? [String: Any])?["Notification"] == nil, "empty Notification key removed on unmerge")

    // fresh user (no settings) — merge into empty
    let fresh = SettingsJsonMerge.merge(into: [:], hookCommand: cmd)
    for e in SettingsJsonMerge.events { t.expectEqual(countOurs(fresh, e), 1) }
}) }

func hookInstallerTests() -> TestSuite { ("HookInstallerTests", { t in
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("csb-inst-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    let settingsURL = base.appendingPathComponent("settings.json")
    let binDir = base.appendingPathComponent("bin", isDirectory: true)
    let src = base.appendingPathComponent("helper-src")
    try? Data("#!/bin/sh\n".utf8).write(to: src)

    let installer = HookInstaller(settingsURL: settingsURL, binDir: binDir, helperSource: src, timeout: 5)

    // Gap 5 — malformed settings: install aborts and does NOT clobber the file
    try? Data("{ not json".utf8).write(to: settingsURL)
    var threw = false
    do { try installer.install() } catch { threw = true }
    t.expect(threw, "install aborts on malformed settings")
    t.expectEqual(try? String(contentsOf: settingsURL, encoding: .utf8), "{ not json")

    // Gap 5 — missing settings: fresh install creates valid settings + copies helper (Gap 3)
    try? fm.removeItem(at: settingsURL)
    try? installer.install()
    t.expect(fm.fileExists(atPath: settingsURL.path), "fresh settings created")
    t.expect(fm.fileExists(atPath: binDir.appendingPathComponent("claude-statusbar-hook").path),
             "helper copied to stable path")
    let parsed = (try? JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))) as? [String: Any]
    t.expect(parsed != nil, "fresh settings is valid json")
    t.expectEqual(countOurs(parsed ?? [:], "Stop"), 1)

    // backup written when settings already present
    try? installer.install()
    t.expect(fm.fileExists(atPath: settingsURL.appendingPathExtension("bak").path),
             "backup written when settings present")
}) }
