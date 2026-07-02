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
@MainActor
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
    let notificationsOn = flag("notificationsEnabled", true)
    let sound = flag("soundEnabled", true)
    var states = Set<SessionState>()
    if notificationsOn { states.insert(.red); states.insert(.green) }  // notify on red + green
    return NotificationSettings(notifyStates: states, soundEnabled: sound)
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
        vm = StatusViewModel(
            store: StateStore(directory: StateStore.defaultDirectory()),
            desktop: DesktopSessionSource()   // Cowork / Desktop Code tab (from host transcripts)
        )
        refresh()
        // Poll-only (G8): one 0.5s timer drives state, notifications, and elapsed display.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if showFloating { floating.show(model: self) }
    }

    /// Re-apply the light/dark override to the floating window (dropdown handles itself).
    func applyAppearance() { floating.applyAppearance() }

    func refresh() {
        vm.refresh()
        aggregate = vm.aggregate
        sessions = vm.sessions

        // Keep the floating panel's width in step with the live session count + max-lights setting.
        if showFloating {
            let maxLights = min(5, max(1, Int(UserDefaults.standard.object(forKey: "floatingMaxLights") as? Double ?? 3)))
            let sel = FloatingSelection.select(vm.sessions, max: maxLights)
            floating.updateSize(shown: sel.shown.count, overflow: sel.overflow > 0)
        }

        let settings = currentNotificationSettings()
        let d = UserDefaults.standard
        func flag(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
        let notificationsOn = flag("notificationsEnabled", true)  // master switch
        let soundOn = flag("soundEnabled", true)                  // master switch

        // Always process (keeps transition tracking in sync); the switches gate output.
        for note in coordinator.process(sessions: vm.sessions, settings: settings, now: Date()) {
            switch note.kind {
            case .needsYou, .done:
                if notificationsOn { notifier.post(note, sound: soundOn) }
            case .started:
                break  // "running" notifications aren't exposed
            }
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
            Image(nsImage: menuBarIcon(for: model.aggregate))
        }
        .menuBarExtraStyle(.window)
    }
}

/// The helper binary sits next to the app executable (same dir in `.build` and inside a
/// bundle's Contents/MacOS), so this resolves correctly in both.
func helperSourceURL() -> URL {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return executable.deletingLastPathComponent().appendingPathComponent("claude-statusbar-hook")
}

struct DropdownView: View {
    @ObservedObject var model: AppModel
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("panelOpacity") private var panelOpacity: Double = 0.4
    @AppStorage("floatingMaxLights") private var floatingMaxLights: Double = 3
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var ignoredProjects = ""
    @State private var hookStatus = ""

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Sessions")
            if model.sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.sessions) { session in
                    let color = Color(nsColor: lampNSColor(session.state))
                    HStack(spacing: 9) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .shadow(color: color.opacity(0.7), radius: 3)
                        Text(session.displayName).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(formatElapsed(session.elapsed))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }

            divider
            header("Options")
            toggleRow("Notifications", isOn: $notificationsEnabled)
            toggleRow("Sound", isOn: $soundEnabled)
            // Force light/dark for both surfaces, or follow the system.
            HStack(spacing: 8) {
                Image(systemName: "circle.righthalf.filled")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            .padding(.vertical, 3)
            .onChange(of: appearanceMode) { _, _ in model.applyAppearance() }
            // Opacity dims both this menu and the floating window, so it's always available.
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $panelOpacity, in: 0...1).controlSize(.mini)
                Text("\(Int(panelOpacity * 100))%")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.vertical, 3)
            toggleRow("Floating lights", isOn: $model.showFloating)
            if model.showFloating {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.grid.1x2")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: $floatingMaxLights, in: 1...5, step: 1).controlSize(.mini)
                    Text("\(Int(floatingMaxLights)) max")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
            toggleRow("Start at login", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { startAtLogin = !on }
                }

            divider
            header("Ignored projects")
            TextEditor(text: $ignoredProjects)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 38)
                .padding(6)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: ignoredProjects) { _, new in
                    try? new.write(to: IgnoreList.defaultFileURL(), atomically: true, encoding: .utf8)
                }

            divider
            HStack(spacing: 8) {
                Button("Install hooks") { runInstall() }
                Button("Uninstall") { runUninstall() }
                Spacer()
                if !hookStatus.isEmpty {
                    Text(hookStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            divider
            HStack {
                Text("v\(version)").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 296)
        .background {
            ZStack {
                VisualEffectView(material: .menu)
                Color.panelTint.opacity(panelOpacity * 0.7)   // same slider as the floating window
            }
        }
        .background(WindowAppearance(appearance: appearanceMode.nsAppearance))   // force light/dark on this menu
        .onAppear {
            ignoredProjects = (try? String(contentsOf: IgnoreList.defaultFileURL(), encoding: .utf8)) ?? ""
        }
    }

    private var divider: some View { Divider().padding(.vertical, 6) }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold)).kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 2).padding(.bottom, 4)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private func runInstall() {
        do {
            try HookInstaller.defaultInstaller(helperSource: helperSourceURL()).install()
            hookStatus = "Installed."
        } catch { hookStatus = "Failed: \(error)" }
    }

    private func runUninstall() {
        do {
            try HookInstaller.defaultInstaller(helperSource: helperSourceURL()).uninstall()
            hookStatus = "Removed."
        } catch { hookStatus = "Failed: \(error)" }
    }
}
