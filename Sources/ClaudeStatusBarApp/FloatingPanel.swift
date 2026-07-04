import SwiftUI
import AppKit
import StatusApp
import StatusCore

/// Bridges an `NSVisualEffectView` into SwiftUI so the panel is real macOS vibrancy
/// glass (translucent, follows the system light/dark appearance).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover   // adapts to light/dark (unlike .hudWindow)

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension Color {
    /// Tints toward black in Dark Mode and white in Light Mode, so the opacity slider
    /// *darkens* the glass in dark and *frosts* it in light — always readable, always native.
    static let panelTint = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    })
}

/// User's appearance override for the app's panels. Applied per-window (not to NSApp) so the
/// menu-bar icon keeps following the real menu bar.
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    /// nil = follow the system appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system
    }
}

/// Applies an explicit `NSAppearance` to the hosting window so a surface can be forced light or
/// dark independent of the system (nil follows the system). Flipping the window appearance flips
/// its vibrancy material, the adaptive `panelTint`, and SwiftUI's `.primary`/`.secondary` colors.
struct WindowAppearance: NSViewRepresentable {
    let appearance: NSAppearance?
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.appearance = appearance }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.appearance = appearance }
    }
}

private func lampColor(_ s: SessionState) -> Color {
    switch s {
    case .red: return Color(red: 1.0, green: 0.23, blue: 0.19)
    case .yellow: return Color(red: 1.0, green: 0.62, blue: 0.04)
    case .green: return Color(red: 0.19, green: 0.82, blue: 0.35)
    }
}

private func compactElapsed(_ t: TimeInterval) -> String {
    let s = Int(t)
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h\((s % 3600) / 60)m"
}

/// A small road traffic-light: three lamps, only the current state lit and glowing.
/// Off-lamps are neutral dark (recessed) so the cell reads clean; the caption shows the
/// project name + elapsed time.
struct MiniTrafficLight: View {
    let session: SessionViewItem

    private var name: String {
        let n = session.displayName
        return n.hasPrefix(".") ? String(n.dropFirst()) : n   // ".config" -> "config"
    }

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 3) {
                lamp(.red)
                lamp(.yellow)
                lamp(.green)
            }
            .padding(4)
            .background(
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.05)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))

            VStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(.primary.opacity(0.92))
                Text(compactElapsed(session.elapsed))
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 46)
        }
    }

    @ViewBuilder private func lamp(_ state: SessionState) -> some View {
        let lit = session.state == state
        Circle()
            .fill(lit ? lampColor(state) : Color.white.opacity(0.07))
            .frame(width: 13, height: 13)
            .shadow(color: lit ? lampColor(state).opacity(0.95) : .clear, radius: 4.5)
    }
}

/// Human reset countdown, e.g. "resets 3d23h" (weekly) / "resets 4h57m" / "resets 42m".
func formatUsageReset(_ resetsAt: Date, now: Date = Date()) -> String {
    let s = Int(resetsAt.timeIntervalSince(now))
    if s <= 0 { return "resetting" }
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "resets \(d)d\(h)h" }
    if h > 0 { return "resets \(h)h\(m)m" }
    return "resets \(m)m"
}

/// A colorful 5-hour usage loader: the full green→yellow→red gradient revealed up to `percent`,
/// so both fill length and color convey how close to the limit you are.
struct UsageBar: View {
    let label: String
    let percent: Int
    let resetsAt: Date?
    let stale: Bool

    private let gradient = LinearGradient(colors: [
        Color(red: 0.19, green: 0.82, blue: 0.35),  // green
        Color(red: 0.55, green: 0.85, blue: 0.20),
        Color(red: 1.0,  green: 0.80, blue: 0.10),  // yellow
        Color(red: 1.0,  green: 0.55, blue: 0.10),  // orange
        Color(red: 1.0,  green: 0.23, blue: 0.19),  // red
    ], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        let pct = Double(min(100, max(0, percent))) / 100
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 8, weight: .semibold)).kerning(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%").font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                if let r = resetsAt {
                    Text("· \(formatUsageReset(r))").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    gradient
                        .frame(width: g.size.width)
                        .mask(Capsule().frame(width: max(6, g.size.width * pct))
                                       .frame(maxWidth: .infinity, alignment: .leading))
                }
            }
            .frame(height: 7)
        }
        .opacity(stale ? 0.45 : 1)   // dim when the snapshot is old
    }
}

/// A subtle close control for the panel header: hides the floating panel (same effect as
/// flipping the dropdown's "Floating lights" switch off). Dim by default, brightens on hover
/// so it stays quiet until you reach for it.
struct PanelCloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.primary.opacity(hovering ? 0.9 : 0.5))
                .frame(width: 15, height: 15)
                .background(.primary.opacity(hovering ? 0.16 : 0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Hide floating panel")
    }
}

/// The floating panel's content: up to five traffic-lights worst-first, then a +N chip.
struct FloatingLightsView: View {
    @ObservedObject var model: AppModel
    // Shared with the Settings slider; updates the glass live as it's dragged.
    @AppStorage("panelOpacity") private var panelOpacity: Double = 0.4
    // How many lights to show before collapsing the rest into the +N chip (1–5).
    @AppStorage("floatingMaxLights") private var floatingMaxLights: Double = 3
    // Show the 5-hour usage bar at the bottom (only when a usage snapshot exists).
    @AppStorage("showUsageBar") private var showUsageBar = false

    var body: some View {
        let selection = FloatingSelection.select(model.sessions, max: Int(floatingMaxLights))
        let usageVisible = showUsageBar && model.usage != nil
        let contentWidth = FloatingLayout.contentWidth(
            shown: selection.shown.count, overflow: selection.overflow > 0, showUsage: usageVisible)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)
                Spacer()
                if !model.sessions.isEmpty {
                    Text("\(model.sessions.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                PanelCloseButton { model.showFloating = false }
            }

            if selection.shown.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(selection.shown) { MiniTrafficLight(session: $0) }
                    if selection.overflow > 0 {
                        VStack(spacing: 4) {
                            Text("+\(selection.overflow)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.75))
                                .frame(width: 26, height: 53)
                                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
                            Text("more")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if showUsageBar, let u = model.usage {
                let stale = u.isStale(now: Date(), maxAge: 900)
                Rectangle().fill(.primary.opacity(0.10)).frame(height: 1).padding(.top, 1)
                UsageBar(label: "5H USAGE", percent: u.fiveHourPercent ?? 0,
                         resetsAt: u.fiveHourResetsAt, stale: stale)
                if let weekly = u.sevenDayPercent {
                    UsageBar(label: "WEEKLY", percent: weekly,
                             resetsAt: u.sevenDayResetsAt, stale: stale)
                }
            }
        }
        // Width fits the lights actually shown (+ chip); floored so the header never clips.
        .frame(width: contentWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            ZStack {
                VisualEffectView()
                Color.panelTint.opacity(panelOpacity * 0.7)   // user-controlled glass depth, adapts to appearance
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 1))
    }
}

/// Owns the borderless, always-on-top, draggable panel and toggles its visibility.
/// The window size tracks the SwiftUI content (so it stays snug for 1–3 lights); only
/// the drag position is persisted.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func show(model: AppModel) {
        if panel == nil {
            let hosting = NSHostingView(rootView: FloatingLightsView(model: model))
            let sel = FloatingSelection.select(model.sessions, max: floatingMaxLights())
            let bars = usageBars(model)
            let w = FloatingLayout.windowWidth(shown: sel.shown.count, overflow: sel.overflow > 0, showUsage: bars > 0)
            let h = FloatingLayout.windowHeight(usageBars: bars)
            // Window is sized to the content and resized on demand (see updateSize) so it stays
            // snug for the lights actually shown while never clipping.
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered, defer: false
            )
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = hosting
            p.delegate = self
            panel = p
            reposition(p)
        }
        applyAppearance()
        panel?.orderFrontRegardless()
    }

    /// Force the floating window light/dark per the user's setting (nil = follow system).
    func applyAppearance() {
        panel?.appearance = AppearanceMode.current.nsAppearance
    }

    /// Resize the panel to fit `shown` lights (+ chip) and the optional usage bar, keeping the
    /// top-right anchor. Called each refresh so it tracks the live count / settings.
    func updateSize(shown: Int, overflow: Bool, usageBars: Int) {
        guard let p = panel else { return }
        let w = FloatingLayout.windowWidth(shown: shown, overflow: overflow, showUsage: usageBars > 0)
        let h = FloatingLayout.windowHeight(usageBars: usageBars)
        if abs(p.frame.width - w) > 0.5 || abs(p.frame.height - h) > 0.5 {
            p.setContentSize(NSSize(width: w, height: h))
            reposition(p)   // setContentSize also fires windowDidResize -> reposition; belt & braces
        }
    }

    private func floatingMaxLights() -> Int {
        let raw = UserDefaults.standard.object(forKey: "floatingMaxLights") as? Double ?? 3
        return min(5, max(1, Int(raw)))
    }

    /// How many usage bars to show: 0 (off/none), 1 (5h), or 2 (5h + weekly).
    private func usageBars(_ model: AppModel) -> Int {
        guard UserDefaults.standard.bool(forKey: "showUsageBar"), let u = model.usage else { return 0 }
        return 1 + (u.sevenDayPercent != nil ? 1 : 0)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // Anchor by the TOP-RIGHT corner so the panel grows left/down from a fixed point and
    // never runs off the edge; persist that corner so drags stick.
    private var repositioning = false

    func windowDidMove(_ notification: Notification) {
        guard !repositioning, let w = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(["x": w.frame.maxX, "y": w.frame.maxY], forKey: "floatingAnchor")
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        reposition(w)
    }

    private func anchor(for window: NSWindow) -> NSPoint {
        if let a = UserDefaults.standard.dictionary(forKey: "floatingAnchor"),
           let x = a["x"] as? Double, let y = a["y"] as? Double {
            return NSPoint(x: x, y: y)
        }
        let vf = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return NSPoint(x: vf.maxX - 14, y: vf.maxY - 8)   // default: top-right
    }

    private func reposition(_ window: NSWindow) {
        let a = anchor(for: window)
        var origin = NSPoint(x: a.x - window.frame.width, y: a.y - window.frame.height)
        if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - window.frame.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - window.frame.height)
        }
        repositioning = true
        window.setFrameOrigin(origin)
        repositioning = false
    }
}
