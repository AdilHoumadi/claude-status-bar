import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement
import StatusApp
import StatusCore
import StatusStore
import StatusInstall

private func lampNSColor(_ s: SessionState) -> NSColor {
    switch s {
    case .red: return NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    case .yellow: return NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    case .green: return NSColor(srgbRed: 0.20, green: 0.82, blue: 0.35, alpha: 1)
    }
}

/// A traffic-light glyph for the menu bar: a solid housing silhouette (adapts to a light
/// or dark menu bar) with three cut-out lamps; the `active` lamp is filled in colour.
/// Non-template so the colour shows.
func menuBarIcon(for active: SessionState) -> NSImage {
    let w: CGFloat = 13, h: CGFloat = 18
    let image = NSImage(size: NSSize(width: w, height: h))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let foreground = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.92)

    // Solid housing silhouette.
    let rect = CGRect(x: 1, y: 0.5, width: w - 2, height: h - 1)
    let radius = (w - 2) / 2
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(foreground.cgColor)
    ctx.fillPath()

    // Three lamp positions.
    let d: CGFloat = 4.2
    let cx = w / 2
    let pad: CGFloat = 2.4
    let gap = (h - 2 * pad - 3 * d) / 2
    var lamps: [(SessionState, CGRect)] = []
    for (i, s) in [SessionState.red, .yellow, .green].enumerated() {
        let y = h - pad - CGFloat(i) * (d + gap) - d
        lamps.append((s, CGRect(x: cx - d / 2, y: y, width: d, height: d)))
    }

    // Cut the lamps out of the silhouette, then fill the active one in colour.
    ctx.setBlendMode(.clear)
    for (_, r) in lamps { ctx.fillEllipse(in: r) }
    ctx.setBlendMode(.normal)
    if let r = lamps.first(where: { $0.0 == active })?.1 {
        ctx.setFillColor(lampNSColor(active).cgColor)
        ctx.fillEllipse(in: r)
    }

    image.unlockFocus()
    image.isTemplate = false
    return image
}

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
    func flag(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
    let notifyRed = flag("notifyOnRed", true)
    let notifyYellow = flag("notifyOnYellow", false)
    let notifyGreen = flag("notifyOnGreen", true)
    let completion = flag("completionSound", true)
    let sound = flag("soundEnabled", true)
    let mutedCSV = d.string(forKey: "mutedProjects") ?? ""
    var states = Set<SessionState>()
    if notifyRed { states.insert(.red) }
    if notifyYellow { states.insert(.yellow) }
    if notifyGreen || completion { states.insert(.green) }  // detect green for banner and/or chime
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
        case .started:
            content.title = "Claude Code is working"
            content.body = "\(notification.projectName) started"
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
    @Published var showFloating: Bool {
        didSet {
            UserDefaults.standard.set(showFloating, forKey: "showFloating")
            showFloating ? floating.show(model: self) : floating.hide()
        }
    }
    private let vm: StatusViewModel
    private let coordinator = NotificationCoordinator()
    private let notifier: Notifier = UserNotifier()
    private let floating = FloatingPanelController()
    private var timer: Timer?

    init() {
        showFloating = UserDefaults.standard.bool(forKey: "showFloating")
        vm = StatusViewModel(store: StateStore(directory: StateStore.defaultDirectory()))
        refresh()
        // Poll-only (G8): one 0.5s timer drives state, notifications, and elapsed display.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if showFloating { floating.show(model: self) }
    }

    func refresh() {
        vm.refresh()
        aggregate = vm.aggregate
        sessions = vm.sessions

        let settings = currentNotificationSettings()
        let d = UserDefaults.standard
        let bannerGreen = d.object(forKey: "notifyOnGreen") as? Bool ?? true
        let completion = d.object(forKey: "completionSound") as? Bool ?? true

        for note in coordinator.process(sessions: vm.sessions, settings: settings, now: Date()) {
            switch note.kind {
            case .needsYou, .started:
                notifier.post(note, sound: settings.soundEnabled)
            case .done:
                // Completion chime is independent of the banner so you can have a sound
                // without a popup (or both).
                if completion { playCompletionSound() }
                if bannerGreen { notifier.post(note, sound: settings.soundEnabled && !completion) }
            }
        }
    }

    private func playCompletionSound() {
        (NSSound(named: "Glass") ?? NSSound(named: "Hero"))?.play()
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
            Image(nsImage: menuBarIcon(for: model.aggregate))
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
    @AppStorage("notifyOnYellow") private var notifyOnYellow = false
    @AppStorage("notifyOnGreen") private var notifyOnGreen = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("completionSound") private var completionSound = true
    @AppStorage("mutedProjects") private var mutedProjects = ""
    @AppStorage("panelOpacity") private var panelOpacity: Double = 0.4
    @State private var hookStatus = ""
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            startAtLogin = !on  // revert if the system refused
                        }
                    }
            }
            Section("Floating panel") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Background opacity")
                        Spacer()
                        Text("\(Int(panelOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 8) {
                        Text("Clear").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $panelOpacity, in: 0...1)
                        Text("Solid").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Notifications") {
                Toggle("Waiting for me (red)", isOn: $notifyOnRed)
                Toggle("Running (yellow)", isOn: $notifyOnYellow)
                Toggle("Finished (green)", isOn: $notifyOnGreen)
                Toggle("Play sound with notifications", isOn: $soundEnabled)
                Toggle("Completion sound", isOn: $completionSound)
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
    @AppStorage("panelOpacity") private var panelOpacity: Double = 0.4

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
            Toggle("Floating lights", isOn: $model.showFloating)
                .toggleStyle(.switch)
                .controlSize(.small)
            if model.showFloating {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary).font(.system(size: 11))
                    Slider(value: $panelOpacity, in: 0...1)
                    Text("\(Int(panelOpacity * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                .controlSize(.mini)
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
