import AppKit
import ServiceManagement
import StatusApp
import StatusCore
import StatusStore
import SwiftUI

/// The menu-bar dropdown, in KOR VPN's layout: header, status card, sessions, usage, and a
/// footer whose gear menu holds every option.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
            StatusCard(model: model)
                .padding(.horizontal, 10)
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.korAlert)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.korOn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.sessions.isEmpty {
                SectionLabel("Sessions").padding(.top, 14)
                // Only the elapsed labels tick, once a second while the panel is open.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        ForEach(model.sessions) { session in
                            SessionRow(model: model, session: session, now: context.date)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            if let usage = model.usage {
                SectionLabel("Usage").padding(.top, 12)
                VStack(spacing: 10) {
                    UsageRow(label: "5-hour", percent: usage.fiveHourPercent ?? 0,
                             resetsAt: usage.fiveHourResetsAt, updatedAt: usage.updatedAt)
                    if let weekly = usage.sevenDayPercent {
                        UsageRow(label: "Weekly", percent: weekly,
                                 resetsAt: usage.sevenDayResetsAt, updatedAt: usage.updatedAt)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 2)
            }
            Divider().padding(.vertical, 6).padding(.horizontal, 14).padding(.top, 6)
            Footer(model: model)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .frame(width: 320)
        // Solid, not the menu's translucent material: a busy wallpaper washed out the colours.
        .background(Color(nsColor: .windowBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            if !isSnapshot { TopEdgePin(height: proxy.size.height) }
        })
        .background(WindowAppearance(appearance: appearanceMode.nsAppearance))
        .onChange(of: appearanceMode) { _, _ in model.applyAppearance() }
        .onAppear { model.panelOpened() }
    }
}

// MARK: - Header

private struct Header: View {
    @ObservedObject var model: AppModel
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    private var subtitle: String {
        switch model.sessions.count {
        case 0: return "No sessions"
        case 1: return "1 session"
        case let n: return "\(n) sessions"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            KorMark().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude Status").font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                KorSwitch(isOn: $notificationsEnabled)
            }
            .help(notificationsEnabled ? "Notifications on" : "Notifications off")
        }
    }
}

// MARK: - Status

private struct StatusCard: View {
    @ObservedObject var model: AppModel

    private var counts: [SessionState: Int] {
        Dictionary(grouping: model.sessions, by: \.state).mapValues(\.count)
    }

    /// Off-grey when there is nothing to show, otherwise the aggregate's colour.
    private var tint: Color { model.sessions.isEmpty ? .secondary : model.aggregate.tint }

    private var headline: String {
        guard !model.sessions.isEmpty else { return "No active sessions" }
        let n = counts[model.aggregate] ?? 0
        switch model.aggregate {
        case .red: return n == 1 ? "1 session needs you" : "\(n) sessions need you"
        case .yellow: return n == 1 ? "Running" : "\(n) sessions running"
        case .green: return "All done"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .shadow(color: tint.opacity(model.sessions.isEmpty ? 0 : 0.6), radius: 4)
                Text(headline).font(.system(size: 17, weight: .semibold))
            }
            if model.sessions.isEmpty {
                Text(model.hooksInstalled
                     ? "Start Claude Code anywhere and it shows up here."
                     : "Hooks aren't installed. Open the gear menu below and choose Install Hooks.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 14) {
                    if let n = counts[.red] { Fact(symbol: "hand.raised.fill", text: "\(n) waiting", tint: .korAlert) }
                    if let n = counts[.yellow] { Fact(symbol: "bolt.fill", text: "\(n) running", tint: .korBusy) }
                    if let n = counts[.green] { Fact(symbol: "checkmark.circle.fill", text: "\(n) done", tint: .korOn) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(model.sessions.isEmpty ? 0.06 : 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(tint.opacity(model.sessions.isEmpty ? 0.12 : 0.25), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: model.aggregate)
    }
}

// MARK: - Sessions

private struct SessionRow: View {
    @ObservedObject var model: AppModel
    let session: SessionViewItem
    let now: Date
    @State private var hovering = false

    /// Waiting and running rows stand out; finished ones stay quiet.
    private var highlighted: Bool { session.state != .green }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(highlighted ? session.state.tint : Color.primary.opacity(0.08))
                    .frame(width: 24, height: 24)
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(highlighted ? Color.white : Color.primary.opacity(0.6))
            }
            Text(session.displayName)
                .font(.system(size: 13, weight: highlighted ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            StateTag(state: session.state)
            Spacer(minLength: 8)
            Text(formatElapsed(session.elapsed(at: now)))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(highlighted ? session.state.tint : .secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(session.cwd ?? session.id)
        .contextMenu {
            if let cwd = session.cwd {
                Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cwd, forType: .string)
                }
                Divider()
                Button("Ignore This Project") { model.ignore(cwd) }
            }
        }
    }
}

// MARK: - Usage

private struct UsageRow: View {
    let label: String
    let percent: Int
    let resetsAt: Date?
    let updatedAt: Date   // the row dims once the snapshot is older than 15 minutes

    var body: some View {
        // Reset countdown and staleness are minute-granular.
        TimelineView(.everyMinute) { context in
            let tint = usageTint(percent)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(label).font(.system(size: 12, weight: .medium))
                    Text("\(percent)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tint)
                    Spacer()
                    if let resetsAt {
                        Text(formatUsageReset(resetsAt, now: context.date))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(tint)
                            .frame(width: max(6, g.size.width * Double(min(100, max(0, percent))) / 100))
                    }
                }
                .frame(height: 6)
            }
            .opacity(context.date.timeIntervalSince(updatedAt) > 900 ? 0.45 : 1)
        }
    }
}

// MARK: - Footer

/// The panel's last row: a gear menu with every option, and Quit.
private struct Footer: View {
    @ObservedObject var model: AppModel
    @Environment(\.isSnapshot) private var isSnapshot
    /// The panel floats above ordinary windows and would hide the one an action opens.
    @Environment(\.closePanel) private var closePanel
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("floatingMaxLights") private var floatingMaxLights: Double = 3
    @AppStorage("floatingOpacity") private var floatingOpacity: Double = 1
    @AppStorage("showUsageBar") private var showUsageBar = false
    @State private var startAtLogin = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        HStack {
            if isSnapshot {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                Menu {
                    Text("Claude Status Bar \(version)")
                    Divider()
                    Toggle("Notifications", isOn: $notificationsEnabled)
                    Toggle("Sound", isOn: $soundEnabled).disabled(!notificationsEnabled)
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Divider()
                    Toggle("Floating Lights", isOn: $model.showFloating)
                    Picker("Lights Shown", selection: $floatingMaxLights) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag(Double($0)) }
                    }
                    .disabled(!model.showFloating)
                    Picker("Floating Opacity", selection: $floatingOpacity) {
                        ForEach([1.0, 0.85, 0.7, 0.5], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                    }
                    .disabled(!model.showFloating)
                    Toggle("Usage in Floating Lights", isOn: $showUsageBar)
                        .disabled(!model.showFloating)
                    Divider()
                    Button("Ignored Projects…") { closePanel(); model.editIgnoredProjects() }
                    Button("Install Hooks") { model.installHooks() }
                    Button("Uninstall Hooks") { model.uninstallHooks() }
                    Divider()
                    Toggle("Start at Login", isOn: Binding(get: { startAtLogin }, set: setStartAtLogin))
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Options")
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                HStack(spacing: 6) {
                    Text("Quit")
                    Text("⌘Q").foregroundStyle(.secondary)
                }
                .font(.system(size: 12.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .onAppear { startAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.show(error: "Couldn't change Start at Login: \(error.localizedDescription)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }
}
