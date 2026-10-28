import SwiftUI
import AppKit
import StatusApp
import StatusCore

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
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))

            VStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                // Only this label ticks; the lamps re-render only on a state change.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(compactElapsed(session.elapsed(at: context.date)))
                        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(session.state == .green ? Color.secondary : session.state.tint)
                }
            }
            .frame(width: FloatingLayout.cell)
        }
    }

    @ViewBuilder private func lamp(_ state: SessionState) -> some View {
        let lit = session.state == state
        let color = Color(nsColor: state.lampNSColor)
        Circle()
            .fill(lit ? color : Color.white.opacity(0.07))
            .frame(width: 13, height: 13)
            .shadow(color: lit ? color.opacity(0.8) : .clear, radius: 4)
    }
}

/// A compact usage line for the floating panel: label, percent and reset, over a thin bar
/// in the threshold colour.
struct UsageBar: View {
    let label: String
    let percent: Int
    let resetsAt: Date?
    let updatedAt: Date   // snapshot time; the bar dims once it's older than 15 minutes

    var body: some View {
        // Reset countdown and staleness are minute-granular: re-render once a minute, not per tick.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let tint = usageTint(percent)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 9.5, weight: .medium))
                Text("\(percent)%").font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                Spacer()
                if let r = resetsAt {
                    Text(formatUsageReset(r, now: now)).font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint)
                        .frame(width: max(5, g.size.width * Double(min(100, max(0, percent))) / 100))
                }
            }
            .frame(height: 5)
        }
        .opacity(now.timeIntervalSince(updatedAt) > 900 ? 0.45 : 1)
    }
}

/// A subtle close control for the panel header: hides the floating panel (same effect as
/// turning Floating Lights off). Dim by default, brightens on hover.
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
        .help("Hide floating lights")
    }
}

/// The floating panel's content: up to five traffic-lights worst-first, then a +N chip.
struct FloatingLightsView: View {
    @ObservedObject var model: AppModel
    /// The panel this view sits in; nil when rendered for screenshots.
    var window: @MainActor () -> NSWindow? = { nil }
    /// Mouse and window origin when the current drag began, in screen coordinates.
    @State private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    // How many lights to show before collapsing the rest into the +N chip (1–5).
    @AppStorage("floatingMaxLights") private var floatingMaxLights: Double = 3
    // Show the usage bars at the bottom (only when a usage snapshot exists).
    @AppStorage("showUsageBar") private var showUsageBar = false

    var body: some View {
        let selection = FloatingSelection.select(model.sessions, max: Int(floatingMaxLights))
        let usageVisible = showUsageBar && model.usage != nil
        let contentWidth = FloatingLayout.contentWidth(
            shown: selection.shown.count, overflow: selection.overflow > 0, showUsage: usageVisible)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                AppMark().frame(width: 15, height: 15)
                Text("Claude Code").font(.system(size: 11, weight: .semibold))
                Spacer()
                if !model.sessions.isEmpty {
                    Text("\(model.sessions.count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.korMain)
                                .frame(width: 26, height: 53)
                                .background(Color.korMain.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            Text("more")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if showUsageBar, let u = model.usage {
                Divider().padding(.top, 1)
                UsageBar(label: "5-hour", percent: u.fiveHourPercent ?? 0,
                         resetsAt: u.fiveHourResetsAt, updatedAt: u.updatedAt)
                if let weekly = u.sevenDayPercent {
                    UsageBar(label: "Weekly", percent: weekly,
                             resetsAt: u.sevenDayResetsAt, updatedAt: u.updatedAt)
                }
            }
        }
        // Width fits the lights actually shown (+ chip); floored so the header never clips.
        .frame(width: contentWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        // Solid like the dropdown; Floating Opacity fades the whole window instead.
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 1))
        // isMovableByWindowBackground ignores SwiftUI content, so drags move the window here.
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { moveWindowWithMouse(movedSoFar: $0.translation) }
            .onEnded { _ in dragStart = nil })
    }

    /// The gesture reports late, so `movedSoFar` backdates the start to the mouse-down point.
    private func moveWindowWithMouse(movedSoFar: CGSize) {
        guard let window = window() else { return }
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (NSPoint(x: mouse.x - movedSoFar.width, y: mouse.y + movedSoFar.height),
                                  window.frame.origin)
        dragStart = start
        window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                      y: start.origin.y + mouse.y - start.mouse.y))
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
            let hosting = NSHostingView(rootView: FloatingLightsView(model: model, window: { [weak self] in self?.panel }))
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

    func applyOpacity() {
        let raw = UserDefaults.standard.object(forKey: "floatingOpacity") as? Double ?? 1
        let alpha = CGFloat(min(1, max(0.3, raw)))
        if let p = panel, abs(p.alphaValue - alpha) > 0.01 { p.alphaValue = alpha }
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

    /// Drops the window, not just hides it: a hidden view kept ticking its elapsed timers.
    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
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
