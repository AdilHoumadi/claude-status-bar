import SwiftUI
import StatusApp
import StatusCore
import StatusStore

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

@MainActor
final class AppModel: ObservableObject {
    @Published var aggregate: SessionState = .green
    @Published var sessions: [SessionViewItem] = []
    private let vm: StatusViewModel
    private var timer: Timer?

    init() {
        vm = StatusViewModel(store: StateStore(directory: StateStore.defaultDirectory()))
        refresh()
        // Poll-only (G8): one 0.5s timer drives both state and the elapsed display.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        vm.refresh()
        aggregate = vm.aggregate
        sessions = vm.sessions
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
