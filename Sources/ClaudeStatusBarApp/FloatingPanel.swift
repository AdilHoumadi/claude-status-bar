import SwiftUI
import AppKit
import StatusApp
import StatusCore

/// Bridges an `NSVisualEffectView` into SwiftUI so the panel is real macOS vibrancy
/// glass (translucent, follows light/dark).
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow   // dark, premium frosted glass
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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

/// The floating panel's content: up to five traffic-lights worst-first, then a +N chip.
struct FloatingLightsView: View {
    @ObservedObject var model: AppModel
    // Shared with the Settings slider; updates the glass live as it's dragged.
    @AppStorage("panelOpacity") private var panelOpacity: Double = 0.4

    var body: some View {
        let selection = FloatingSelection.select(model.sessions, max: 3)
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
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                            Text("more")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        // Fixed width sized for 3 lights + the overflow chip; stays this size for fewer.
        .frame(width: 178, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            ZStack {
                VisualEffectView()
                Color.black.opacity(panelOpacity * 0.7)   // user-controlled glass depth
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)   // consistent dark panel, light text & glowing lamps
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
            // Fixed window sized for 3 lights + chip (matches the content frame). No dynamic
            // resizing — keeps it stable, rounded, and never clips the content.
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 202, height: 120),
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
        panel?.orderFrontRegardless()
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
