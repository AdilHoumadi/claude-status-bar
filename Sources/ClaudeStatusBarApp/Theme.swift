import AppKit
import StatusCore
import SwiftUI

// KOR palette, adapted for dark menus (same tokens as KOR VPN).
extension Color {
    static let korMain = Color(light: 0x015176, dark: 0x2AB9E5)
    static let korDeep = Color(light: 0x00293D, dark: 0x015176)
    // Light values are dark enough for small text on the panel (at least 4.5:1).
    static let korOn = Color(light: 0x137A44, dark: 0x3FCB84)
    static let korBusy = Color(light: 0x9A5B00, dark: 0xF2B544)
    static let korAlert = Color(light: 0xD1193E, dark: 0xFF6680)

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension SessionState {
    var tint: Color {
        switch self {
        case .red: return .korAlert
        case .yellow: return .korBusy
        case .green: return .korOn
        }
    }

    /// The bright (dark-appearance) value, for lamps drawn on an always-dark housing.
    var lampNSColor: NSColor {
        switch self {
        case .red: return NSColor(hex: 0xFF6680)
        case .yellow: return NSColor(hex: 0xF2B544)
        case .green: return NSColor(hex: 0x3FCB84)
        }
    }

    var tag: String {
        switch self {
        case .red: return "Waiting"
        case .yellow: return "Running"
        case .green: return "Done"
        }
    }
}

/// True while a view is drawn by ImageRenderer, which cannot draw AppKit-backed controls
/// (switch, menu); those views then draw SwiftUI stand-ins.
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

/// The app's mark: its icon in miniature, a lit traffic light on a dark squircle.
struct AppMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let lamp = s * 0.2
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.2237, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.19, blue: 0.23),
                                                  Color(red: 0.06, green: 0.07, blue: 0.09)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                    .fill(Color(red: 0.02, green: 0.02, blue: 0.03))
                    .frame(width: s * 0.42, height: s * 0.8)
                VStack(spacing: s * 0.035) {
                    ForEach([SessionState.red, .yellow, .green], id: \.self) { state in
                        Circle().fill(Color(nsColor: state.lampNSColor)).frame(width: lamp, height: lamp)
                    }
                }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 4)
    }
}

struct Fact: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(tint)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 11.5))
    }
}

struct StateTag: View {
    let state: SessionState

    var body: some View {
        Text(state.tag)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(state.tint.opacity(0.2)))
    }
}

/// A switch, or its SwiftUI stand-in under ImageRenderer.
struct KorSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            Capsule().fill(isOn ? Color.korOn : Color.primary.opacity(0.15))
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(radius: 0.5).padding(2)
                }
        } else {
            Toggle("", isOn: $isOn).toggleStyle(.switch).tint(Color.korOn).labelsHidden()
        }
    }
}

func formatElapsed(_ t: TimeInterval) -> String {
    let s = Int(t)
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

/// Human reset countdown, e.g. "resets 3d 23h" (weekly) / "resets 4h 57m" / "resets 42m".
func formatUsageReset(_ resetsAt: Date, now: Date = Date()) -> String {
    let s = Int(resetsAt.timeIntervalSince(now))
    if s <= 0 { return "resetting" }
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "resets \(d)d \(h)h" }
    if h > 0 { return "resets \(h)h \(m)m" }
    return "resets \(m)m"
}

/// Same thresholds as the statusline colours: green under 75%, amber under 90%, red above.
func usageTint(_ percent: Int) -> Color {
    percent >= 90 ? .korAlert : (percent >= 75 ? .korBusy : .korOn)
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
/// dark independent of the system (nil follows the system).
///
/// Only writes when the value differs: setting `window.appearance` invalidates the hosting
/// view, which calls `updateNSView` again — unconditional writes turned that into a layout
/// loop that pinned the main thread at 100% CPU.
struct WindowAppearance: NSViewRepresentable {
    let appearance: NSAppearance?

    final class ApplyingView: NSView {
        var target: NSAppearance? { didSet { applyDeferred() } }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyDeferred()
        }

        /// Deferred so the window isn't mutated mid SwiftUI update pass.
        private func applyDeferred() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window,
                      window.appearance?.name != self.target?.name else { return }
                window.appearance = self.target
            }
        }
    }

    func makeNSView(context: Context) -> ApplyingView {
        let view = ApplyingView()
        view.target = appearance
        return view
    }

    func updateNSView(_ nsView: ApplyingView, context: Context) {
        guard nsView.target?.name != appearance?.name else { return }
        nsView.target = appearance
    }
}
