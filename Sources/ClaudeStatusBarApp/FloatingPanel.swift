import SwiftUI
import AppKit
import StatusApp
import StatusCore

/// Bridges an `NSVisualEffectView` into SwiftUI so the panel is real macOS vibrancy
/// glass (translucent, follows light/dark).
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
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

/// A small road traffic-light: three lamps, the current state lit and glowing. The lit
/// lamp carries the state, so the caption shows the project + elapsed time instead.
struct MiniTrafficLight: View {
    let session: SessionViewItem

    var body: some View {
        VStack(spacing: 5) {
            VStack(spacing: 4) {
                lamp(.red)
                lamp(.yellow)
                lamp(.green)
            }
            .padding(.vertical, 5)
            .frame(width: 28)
            .background(
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.06)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.45), lineWidth: 0.5))

            VStack(spacing: 0) {
                Text(session.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(compactElapsed(session.elapsed))
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 54)
        }
    }

    @ViewBuilder private func lamp(_ state: SessionState) -> some View {
        let lit = session.state == state
        Circle()
            .fill(lit ? lampColor(state) : lampColor(state).opacity(0.14))
            .frame(width: 13, height: 13)
            .shadow(color: lit ? lampColor(state).opacity(0.8) : .clear, radius: 4)
    }
}

/// The floating panel's content: up to five traffic-lights worst-first, then a +N chip.
struct FloatingLightsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let selection = FloatingSelection.select(model.sessions, max: 5)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Claude Code").font(.system(size: 12, weight: .semibold))
                Spacer()
                if !model.sessions.isEmpty {
                    Text("\(model.sessions.count)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 1)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5).offset(y: 5)
            }

            if selection.shown.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(selection.shown) { MiniTrafficLight(session: $0) }
                    if selection.overflow > 0 {
                        Text("+\(selection.overflow)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                            .padding(.vertical, 18)
                            .background(.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minWidth: 140)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }
}

/// Owns the borderless, always-on-top, draggable panel and toggles its visibility.
@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?

    func show(model: AppModel) {
        if panel == nil {
            let hosting = NSHostingView(rootView: FloatingLightsView(model: model))
            hosting.sizingOptions = [.standardBounds]
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
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
            p.setFrameAutosaveName("ClaudeStatusBarFloating")
            if p.frame.origin == .zero { p.center() }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
