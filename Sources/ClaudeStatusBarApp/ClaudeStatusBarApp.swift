import SwiftUI
import AppKit
import UserNotifications
import StatusApp
import StatusCore
import StatusStore
import StatusInstall

/// A traffic-light glyph for the menu bar: a solid housing silhouette (adapts to a light
/// or dark menu bar) with three cut-out lamps; the `active` lamp is filled in colour.
/// Non-template so the colour shows.
@MainActor
func menuBarIcon(for active: SessionState, dark: Bool) -> NSImage {
    let w: CGFloat = 13, h: CGFloat = 18
    let image = NSImage(size: NSSize(width: w, height: h))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

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
        ctx.setFillColor(active.lampNSColor.cgColor)
        ctx.fillEllipse(in: r)
    }

    image.unlockFocus()
    image.isTemplate = false
    return image
}

/// Reads notification preferences from UserDefaults (defaults: notify on red + green,
/// sound on). The gear menu writes the same keys via `@AppStorage`.
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

/// The three menu-bar glyphs per appearance, drawn once instead of on every body evaluation.
@MainActor
private var menuBarIconCache: [String: NSImage] = [:]

@MainActor
func cachedMenuBarIcon(for active: SessionState, dark: Bool) -> NSImage {
    let key = "\(active.rawValue)-\(dark)"
    if let image = menuBarIconCache[key] { return image }
    let image = menuBarIcon(for: active, dark: dark)
    menuBarIconCache[key] = image
    return image
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var aggregate: SessionState = .green
    @Published private(set) var sessions: [SessionViewItem] = []
    @Published private(set) var usage: UsageSnapshot?   // 5h/weekly rate-limit snapshot (from a statusline)
    @Published private(set) var menuBarDark = false     // re-tints the icon when the menu bar flips
    @Published private(set) var hooksInstalled = true
    @Published private(set) var notice: String?
    @Published private(set) var lastError: String?
    @Published var showFloating: Bool {
        didSet {
            UserDefaults.standard.set(showFloating, forKey: "showFloating")
            showFloating ? floating.show(model: self) : floating.hide()
        }
    }
    private let vm: StatusViewModel
    private let coordinator = NotificationCoordinator()
    private lazy var notifier: Notifier = UserNotifier()
    private let floating = FloatingPanelController()
    private var watcher: DirectoryWatcher?
    private var reapTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?
    private var defaultsObserver: NSObjectProtocol?

    init() {
        showFloating = UserDefaults.standard.bool(forKey: "showFloating")
        // Cowork / Desktop Code sessions run the Claude Code engine, so they fire the hooks
        // like CLI/IDE — one store covers them all, and closed sessions drop off via SessionEnd.
        let directory = StateStore.defaultDirectory()
        vm = StatusViewModel(store: StateStore(directory: directory))
        _ = notifier
        refresh()
        hooksInstalled = Self.checkHooksInstalled()

        // Event-driven: every hook write, usage.json snapshot and ignore.txt edit lands in this
        // directory, so the app sleeps until one happens instead of polling.
        watcher = DirectoryWatcher(directory: directory) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        watcher?.start()
        // Slow safety net for what no write announces: reaping sessions that went silent
        // (TTL 30 min) and the usage bar's staleness dim. Tolerance lets macOS coalesce wakeups.
        reapTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        reapTimer?.tolerance = 15

        menuBarDark = Self.isDark(NSApplication.shared.effectiveAppearance)
        // effectiveAppearance changes on the main thread.
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] app, _ in
            MainActor.assumeIsolated {
                let dark = Self.isDark(app.effectiveAppearance)
                if let self, self.menuBarDark != dark { self.menuBarDark = dark }
            }
        }
        // Floating-panel size and opacity depend on settings edited in the gear menu.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFloatingSize() }
        }
        if showFloating { floating.show(model: self) }
    }

    /// Fixed data and no watcher, notifier or floating window: for rendering screenshots.
    init(preview sessions: [SessionViewItem], usage: UsageSnapshot?) {
        showFloating = false
        vm = StatusViewModel(store: StateStore(directory: FileManager.default.temporaryDirectory))
        self.sessions = sessions
        self.aggregate = SessionState.aggregate(sessions.map(\.state))
        self.usage = usage
    }

    private nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func checkHooksInstalled() -> Bool {
        let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let text = try? String(contentsOf: settings, encoding: .utf8) else { return false }
        return text.contains(SettingsJsonMerge.marker)
    }

    /// Re-apply the light/dark override to the floating window (the dropdown handles itself).
    func applyAppearance() { floating.applyAppearance() }

    /// Notices belong to the action that raised them; a fresh open starts clean.
    func panelOpened() {
        notice = nil
        lastError = nil
        hooksInstalled = Self.checkHooksInstalled()
    }

    func show(error: String) {
        notice = nil
        lastError = error
    }

    private func show(notice text: String) {
        lastError = nil
        notice = text
    }

    func installHooks() {
        do {
            try HookInstaller.defaultInstaller(helperSource: helperSourceURL()).install()
            hooksInstalled = true
            show(notice: "Hooks installed. New Claude Code sessions will show up here.")
        } catch {
            show(error: "Couldn't install hooks: \(error)")
        }
    }

    func uninstallHooks() {
        do {
            try HookInstaller.defaultInstaller(helperSource: helperSourceURL()).uninstall()
            hooksInstalled = false
            show(notice: "Hooks removed from ~/.claude/settings.json.")
        } catch {
            show(error: "Couldn't remove hooks: \(error)")
        }
    }

    /// Adds `cwd` to the ignore list; the directory watcher then hides the session.
    func ignore(_ cwd: String) {
        let url = IgnoreList.defaultFileURL()
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += cwd + "\n"
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            show(notice: "Ignoring \((cwd as NSString).lastPathComponent). Undo in Ignored Projects….")
        } catch {
            show(error: "Couldn't update the ignore list: \(error.localizedDescription)")
        }
    }

    func editIgnoredProjects() {
        IgnoredProjectsEditor.show { [weak self] in self?.refresh() }
    }

    /// Keep the floating panel's size in step with the live session count + settings.
    func updateFloatingSize() {
        guard showFloating else { return }
        let maxLights = min(5, max(1, Int(UserDefaults.standard.object(forKey: "floatingMaxLights") as? Double ?? 3)))
        let sel = FloatingSelection.select(sessions, max: maxLights)
        let usageBars = (UserDefaults.standard.bool(forKey: "showUsageBar") && usage != nil)
            ? 1 + ((usage?.sevenDayPercent != nil) ? 1 : 0) : 0
        floating.updateSize(shown: sel.shown.count, overflow: sel.overflow > 0, usageBars: usageBars)
        floating.applyOpacity()
    }

    func refresh() {
        // Assign only on a real change: @Published fires on every set, and each publish
        // re-renders and re-sizes the dropdown and the floating panel.
        if vm.refresh() {
            if aggregate != vm.aggregate { aggregate = vm.aggregate }
            if sessions != vm.sessions { sessions = vm.sessions }
        }
        let newUsage = UsageStore.read()   // nil until a statusline writes usage.json
        if newUsage != usage { usage = newUsage }

        updateFloatingSize()

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

// MARK: - Screenshots

extension AppModel {
    /// Development aid (CSB_RENDER=<path prefix>): writes the dropdown and the floating panel,
    /// light and dark, with sample sessions to PNGs, then quits.
    static func renderScreenshots(to prefix: String) {
        let now = Date()
        let sessions = [
            SessionViewItem(id: "a", state: .red, cwd: "/Users/me/Projects/claude-status-bar", stateSince: now - 252),
            SessionViewItem(id: "b", state: .yellow, cwd: "/Users/me/Projects/api-server", stateSince: now - 74),
            SessionViewItem(id: "c", state: .yellow, cwd: "/Users/me/Projects/worker", stateSince: now - 9),
            SessionViewItem(id: "d", state: .green, cwd: "/Users/me/Projects/web", stateSince: now - 760),
        ]
        let usage = UsageSnapshot(updatedAt: now, fiveHourPercent: 38, fiveHourResetsAt: now + 17_820,
                                  sevenDayPercent: 81, sevenDayResetsAt: now + 344_000)
        let model = AppModel(preview: sessions, usage: usage)
        let empty = AppModel(preview: [], usage: nil)
        let defaults = UserDefaults(suiteName: "claude-status-bar-render")!
        defaults.set(true, forKey: "showUsageBar")
        defaults.set(3.0, forKey: "floatingMaxLights")

        func write<V: View>(_ view: V, _ name: String, _ scheme: ColorScheme) {
            let content = view
                .environment(\.colorScheme, scheme)
                .environment(\.isSnapshot, true)
                .defaultAppStorage(defaults)
                .padding(20)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.86))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(prefix)-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            write(PanelView(model: model), "panel", scheme)
            write(PanelView(model: empty), "panel-empty", scheme)
            write(FloatingLightsView(model: model), "floating", scheme)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar agent, no Dock icon
        if let prefix = ProcessInfo.processInfo.environment["CSB_RENDER"] {
            AppModel.renderScreenshots(to: prefix)
            NSApp.terminate(nil)
            return
        }
        let model = AppModel()
        self.model = model
        statusItem = StatusItemController(model: model)
    }
}

@main
struct ClaudeStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item and its panel are AppKit's (StatusItemController). The SwiftUI app
    // stays for its main menu: without the Edit menu, ⌘C and ⌘V fail in the editor. Not a
    // Settings scene: on macOS 27 it opened an empty Settings window at every launch.
    var body: some Scene {
        MenuBarExtra("Claude Status", isInserted: .constant(false)) { EmptyView() }
    }
}

/// The helper binary sits next to the app executable (same dir in `.build` and inside a
/// bundle's Contents/MacOS), so this resolves correctly in both.
func helperSourceURL() -> URL {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return executable.deletingLastPathComponent().appendingPathComponent("claude-statusbar-hook")
}
