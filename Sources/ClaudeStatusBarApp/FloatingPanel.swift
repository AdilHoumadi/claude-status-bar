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
    case .red: return .red
    case .yellow: return .orange
    case .green: return .green
    }
}

private func lampWord(_ s: SessionState) -> String {
    switch s {
    case .red: return "waiting"
    case .yellow: return "running"
    case .green: return "idle"
    }
}

/// A small road traffic-light: three lamps, the current state lit and glowing.
struct MiniTrafficLight: View {
    let session: SessionViewItem

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 5) {
                lamp(.red)
                lamp(.yellow)
                lamp(.green)
            }
            .padding(.vertical, 6)
            .frame(width: 38)
            .background(
                LinearGradient(colors: [Color(white: 0.20), Color(white: 0.07)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(spacing: 1) {
                Text(session.displayName)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1).truncationMode(.tail)
                Text(lampWord(session.state))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66)
        }
    }

    @ViewBuilder private func lamp(_ state: SessionState) -> some View {
        let lit = session.state == state
        Circle()
            .fill(lit ? lampColor(state) : lampColor(state).opacity(0.16))
            .frame(width: 16, height: 16)
            .shadow(color: lit ? lampColor(state).opacity(0.75) : .clear, radius: 5)
    }
}

/// The floating panel's content: up to five traffic-lights worst-first, then a +N chip.
struct FloatingLightsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let selection = FloatingSelection.select(model.sessions, max: 5)
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Status").font(.system(size: 14, weight: .bold))
            if selection.shown.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(selection.shown) { MiniTrafficLight(session: $0) }
                    if selection.overflow > 0 {
                        Text("+\(selection.overflow)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20).padding(.horizontal, 9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(.secondary.opacity(0.35),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3]))
                            )
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 160)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.22), lineWidth: 1))
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
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 170),
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
