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

        // The app icon (traffic light) shows on the banner automatically — no attachment.
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
        func flag(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
        let notificationsOn = flag("notificationsEnabled", true)  // master switch
        let soundOn = flag("soundEnabled", true)                  // master switch
        let bannerGreen = flag("notifyOnGreen", true)
        let completion = flag("completionSound", true)

        // Always process (keeps transition tracking in sync); the master switches gate output.
        for note in coordinator.process(sessions: vm.sessions, settings: settings, now: Date()) {
            switch note.kind {
            case .needsYou, .started:
                if notificationsOn { notifier.post(note, sound: soundOn) }
            case .done:
                if soundOn && completion { playCompletionSound() }
                if notificationsOn && bannerGreen {
                    notifier.post(note, sound: soundOn && !completion)
                }
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
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
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

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Toggle("Waiting for me (red)", isOn: $notifyOnRed).disabled(!notificationsEnabled)
                Toggle("Running (yellow)", isOn: $notifyOnYellow).disabled(!notificationsEnabled)
                Toggle("Finished (green)", isOn: $notifyOnGreen).disabled(!notificationsEnabled)
            }

            Section("Sound") {
                Toggle("Enable sound", isOn: $soundEnabled)
                Toggle("Completion sound", isOn: $completionSound).disabled(!soundEnabled)
            }

            Section("Floating panel") {
                LabeledContent("Background opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $panelOpacity, in: 0...1).frame(width: 150)
                        Text("\(Int(panelOpacity * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            Section {
                TextEditor(text: $mutedProjects)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 72)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            } header: {
                Text("Muted projects")
            } footer: {
                Text("One project path (cwd) per line — muted projects never notify.")
            }

            Section {
                HStack {
                    Button("Install hooks") { runInstall() }
                    Button("Uninstall hooks") { runUninstall() }
                    Spacer()
                    if !hookStatus.isEmpty {
                        Text(hookStatus).font(.callout).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Claude Code hooks")
            } footer: {
                Text("Writes status hooks into ~/.claude/settings.json (backed up to settings.json.bak first). Your existing hooks are preserved.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 600)
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
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Code — \(model.aggregate.label)")
                .font(.headline)

            Divider()

            if model.sessions.isEmpty {
                Text("No active sessions")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 9) {
                    ForEach(model.sessions) { session in
                        HStack(spacing: 9) {
                            Text(session.state.emoji).font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.displayName).font(.callout).lineLimit(1)
                                Text(session.cwd ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Text(formatElapsed(session.elapsed))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            toggleRow("Notifications", isOn: $notificationsEnabled)
            toggleRow("Sound", isOn: $soundEnabled)

            Divider()

            toggleRow("Floating lights", isOn: $model.showFloating)
            if model.showFloating {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary).font(.system(size: 11))
                    Slider(value: $panelOpacity, in: 0...1).controlSize(.small)
                    Text("\(Int(panelOpacity * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            Divider()

            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    /// A row with the label on the left and the switch pinned to the right.
    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
