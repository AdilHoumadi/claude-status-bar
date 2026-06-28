import SwiftUI
import UserNotifications
import StatusApp
import StatusCore
import StatusStore
import StatusInstall

extension SessionState {
    var emoji: String {
        switch self {
        case .red: return "🔴"
        case .yellow: return "🟡"
        case .green: return "🟢"
        }
    }

    var label: String {
        switch self {
        case .red: return "Waiting for you"
        case .yellow: return "Running"
        case .green: return "Idle"
        }
    }
}

func formatElapsed(_ t: TimeInterval) -> String {
    let s = Int(t)
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

/// Reads notification preferences from UserDefaults (defaults: notify on red + green,
/// sound on). The Settings UI writes the same keys via `@AppStorage`.
func currentNotificationSettings() -> NotificationSettings {
    let d = UserDefaults.standard
    let notifyRed = d.object(forKey: "notifyOnRed") as? Bool ?? true
    let notifyGreen = d.object(forKey: "notifyOnGreen") as? Bool ?? true
    let sound = d.object(forKey: "soundEnabled") as? Bool ?? true
    let mutedCSV = d.string(forKey: "mutedProjects") ?? ""
    var states = Set<SessionState>()
    if notifyRed { states.insert(.red) }
    if notifyGreen { states.insert(.green) }
    let muted = Set(mutedCSV.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    return NotificationSettings(notifyStates: states, soundEnabled: sound, mutedProjects: muted)
}

/// Posts desktop notifications via UNUserNotificationCenter, which requires a bundled
/// `.app` (a bare `swift run` binary has no bundle identifier and calling
/// `UNUserNotificationCenter.current()` would crash). When unbundled we degrade to a
/// no-op so the menu-bar GUI still runs; build the `.app` (scripts/bundle.sh) for
/// notifications to fire.
final class UserNotifier: Notifier {
    private let enabled: Bool

    init() {
        enabled = Bundle.main.bundleIdentifier != nil
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ notification: AppNotification, sound: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        switch notification.kind {
        case .needsYou:
            content.title = "Claude Code needs you"
            content.body = "\(notification.projectName) is waiting for your input"
        case .done:
            content.title = "Claude Code finished"
            content.body = "\(notification.projectName) is idle"
        }
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var aggregate: SessionState = .green
    @Published var sessions: [SessionViewItem] = []
    private let vm: StatusViewModel
    private let coordinator = NotificationCoordinator()
    private let notifier: Notifier = UserNotifier()
    private var timer: Timer?

    init() {
        vm = StatusViewModel(store: StateStore(directory: StateStore.defaultDirectory()))
        refresh()
        // Poll-only (G8): one 0.5s timer drives state, notifications, and elapsed display.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        vm.refresh()
        aggregate = vm.aggregate
        sessions = vm.sessions

        let settings = currentNotificationSettings()
        for note in coordinator.process(sessions: vm.sessions, settings: settings, now: Date()) {
            notifier.post(note, sound: settings.soundEnabled)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar agent, no Dock icon
    }
}

@main
struct ClaudeStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            Text(model.aggregate.emoji)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// The helper binary sits next to the app executable (same dir in `.build` and inside a
/// bundle's Contents/MacOS), so this resolves correctly in both.
func helperSourceURL() -> URL {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return executable.deletingLastPathComponent().appendingPathComponent("claude-statusbar-hook")
}

struct SettingsView: View {
    @AppStorage("notifyOnRed") private var notifyOnRed = true
    @AppStorage("notifyOnGreen") private var notifyOnGreen = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("mutedProjects") private var mutedProjects = ""
    @State private var hookStatus = ""

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Notify when waiting for me (red)", isOn: $notifyOnRed)
                Toggle("Notify when finished (green)", isOn: $notifyOnGreen)
                Toggle("Play sound", isOn: $soundEnabled)
            }
            Section("Muted projects (one cwd per line)") {
                TextEditor(text: $mutedProjects).frame(height: 100)
            }
            Section("Claude Code hooks") {
                HStack {
                    Button("Install hooks") { runInstall() }
                    Button("Uninstall hooks") { runUninstall() }
                }
                if !hookStatus.isEmpty {
                    Text(hookStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("Writes status hooks into ~/.claude/settings.json (backed up to settings.json.bak first).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440, height: 420)
    }

    private func runInstall() {
        do {
            try HookInstaller.defaultInstaller(helperSource: helperSourceURL()).install()
            hookStatus = "Hooks installed."
        } catch {
            hookStatus = "Install failed: \(error)"
        }
    }

    private func runUninstall() {
        do {
            try HookInstaller.defaultInstaller(helperSource: helperSourceURL()).uninstall()
            hookStatus = "Hooks removed."
        } catch {
            hookStatus = "Uninstall failed: \(error)"
        }
    }
}

struct DropdownView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code — \(model.aggregate.label)")
                .font(.headline)
            Divider()
            if model.sessions.isEmpty {
                Text("No active sessions").foregroundStyle(.secondary)
            } else {
                ForEach(model.sessions) { session in
                    HStack(spacing: 8) {
                        Text(session.state.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.displayName)
                            Text(session.cwd ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatElapsed(session.elapsed))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
    }
}
