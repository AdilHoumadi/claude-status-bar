import Foundation
import StatusCore
import StatusStore
import StatusInstall

// Dual-purpose binary:
//   --install / --uninstall : wire (or remove) the status hooks in ~/.claude/settings.json
//   (no args)               : Claude Code hook — read stdin JSON and update the state file
let args = CommandLine.arguments

/// Path to this running binary, used as the source to copy into the stable hook location.
private func selfPath() -> URL {
    URL(fileURLWithPath: args[0]).resolvingSymlinksInPath()
}

if args.contains("--install") {
    let installer = HookInstaller.defaultInstaller(helperSource: selfPath())
    do {
        try installer.install()
        print("Installed claude-status-bar hooks.")
        print("  helper:   \(installer.stableHelperPath.path)")
        print("  settings: \(installer.settingsURL.path)")
        print("  backup:   \(installer.settingsURL.appendingPathExtension("bak").path)")
        print("  events:   \(SettingsJsonMerge.events.joined(separator: ", "))")
        print("Restart any running Claude Code sessions to pick up the hooks.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Install failed: \(error)\n".utf8))
        exit(1)
    }
}

if args.contains("--uninstall") {
    let installer = HookInstaller.defaultInstaller(helperSource: selfPath())
    do {
        try installer.uninstall()
        print("Removed claude-status-bar hooks from \(installer.settingsURL.path).")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Uninstall failed: \(error)\n".utf8))
        exit(1)
    }
}

// Statusline snapshot: read the JSON Claude Code pipes to a statusline command on stdin and
// persist the rate-limit windows to usage.json for the menu-bar app. Write-only and fail-open
// (prints nothing, always exits 0), so it's safe as a standalone statusline or fed by a wrapper.
if args.contains("--usage-snapshot") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let snapshot = UsageStore.fromStatuslineStdin(data, now: Date()) {
        try? UsageStore.write(snapshot)
    }
    exit(0)
}

// Default: Claude Code hook entry point. Reads stdin JSON and updates the session state
// file. ALWAYS exits 0 (fail-open) and runs synchronously so it never blocks a turn.
let data = FileHandle.standardInput.readDataToEndOfFile()
if let event = try? JSONDecoder().decode(HookEvent.self, from: data) {
    // Skip ignored projects (e.g. automated/headless `claude -p` runs).
    let prefixes = IgnoreList.prefixes(from: IgnoreList.defaultFileURL())
    if !IgnoreList.isIgnored(event.cwd, prefixes: prefixes) {
        let store = StateStore(directory: StateStore.defaultDirectory())
        HookProcessor.apply(event, store: store, now: Date())
    }
}
exit(0)
