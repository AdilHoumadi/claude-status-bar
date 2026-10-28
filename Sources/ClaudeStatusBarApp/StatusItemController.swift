import AppKit
import Combine
import SwiftUI

/// The menu bar item and its panel, ported from KOR VPN. AppKit's NSStatusItem rather than
/// SwiftUI's MenuBarExtra: the extra kept the panel's view alive while closed, so its
/// elapsed-time timer re-laid it out every second, and it ignores the accessibility press.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MenuBarPanel()
    private var observer: AnyCancellable?
    private var shownIcon: String?

    init(model: AppModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown]) // menus open on press, not release
        }
        panel.onEscape = { [weak self] in self?.close(deactivate: true) }
        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
        updateButton()
        // objectWillChange fires before the change: read the new state on the next turn.
        observer = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateButton() }
        }
    }

    private func updateButton() {
        guard let button = item.button else { return }
        let key = "\(model.aggregate.rawValue)-\(model.menuBarDark)"
        guard key != shownIcon else { return }
        shownIcon = key
        button.image = cachedMenuBarIcon(for: model.aggregate, dark: model.menuBarDark)
        button.setAccessibilityLabel("Claude Status: \(model.aggregate.tag)")
    }

    @objc private func toggle() {
        if panel.isVisible { close(deactivate: true); return }
        // A click on the icon takes the key from the panel before its action arrives, so the
        // panel has just closed: that click meant close, not open again.
        if let lostKeyAt, Date().timeIntervalSince(lostKeyAt) < 0.3 { return }
        open()
    }

    /// When the panel last closed because it lost the key.
    private var lostKeyAt: Date?

    private func open() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        // A fresh view each time: onAppear refreshes the hook check and clears old notices.
        let view = PanelView(model: model).environment(\.closePanel, ClosePanelAction { [weak self] in
            self?.close(deactivate: false)
        })
        let host = NSHostingView(rootView: view)
        panel.setContent(host)
        panel.appearance = AppearanceMode.current.nsAppearance
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        panel.setFrame(Self.panelFrame(size: host.fittingSize, below: anchor, in: screen), display: true)
        NSApp.activate(ignoringOtherApps: true) // the panel takes keys: ⌘Q, Escape, the gear menu
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
    }

    /// `deactivate`: hand the keyboard back to the app in front, when nothing else of ours is
    /// open. Not when an action is about to open one of our windows.
    private func close(deactivate: Bool) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        item.button?.highlight(false)
        // Hidden, the view would keep ticking its elapsed timers, so let it go once the action
        // that closed the panel has returned.
        DispatchQueue.main.async { [panel] in
            if !panel.isVisible, NSApp.modalWindow == nil { panel.contentView = nil }
        }
        if deactivate, !NSApp.windows.contains(where: { $0 !== panel && $0.isVisible && $0.level == .normal }) {
            NSApp.deactivate()
        }
    }

    /// A click elsewhere, or another of our windows (the editor, an alert) taking over.
    @objc private func panelResignedKey() {
        if panel.isVisible { lostKeyAt = Date() }
        close(deactivate: false)
    }

    /// Under the item with their left edges aligned, like the system's menus, and kept on screen.
    static func panelFrame(size: NSSize, below item: NSRect, in screen: NSRect) -> NSRect {
        let margin: CGFloat = 6
        let x = max(screen.minX + margin, min(item.minX, screen.maxX - size.width - margin))
        return NSRect(x: x, y: item.minY - 4 - size.height, width: size.width, height: size.height)
    }
}

/// Borderless and rounded like a menu, but able to become key: the panel has a gear menu,
/// context menus and ⌘Q. It floats above ordinary windows, as menus do.
final class MenuBarPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        // Non-activating, so it takes keys even when macOS declines to bring the app forward;
        // a click elsewhere then still takes the key and closes it.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        setAccessibilityLabel("Claude Status")
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// Replaces the content, or the view the panel kept because an alert was open when it closed.
    func setContent(_ view: NSView) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        contentView = container
        view.frame = container.bounds
    }
}

/// Closes the panel from inside it, before an action opens a window the panel would cover.
struct ClosePanelAction: Sendable {
    let run: @MainActor @Sendable () -> Void
    @MainActor func callAsFunction() { run() }
}

private struct ClosePanelKey: EnvironmentKey {
    static let defaultValue = ClosePanelAction {}
}

extension EnvironmentValues {
    var closePanel: ClosePanelAction {
        get { self[ClosePanelKey.self] }
        set { self[ClosePanelKey.self] = newValue }
    }
}

/// The panel grows when its content gets taller (a new session) but the window would keep its
/// old height. This sizes the window to the content, keeping its top edge under the menu bar.
struct TopEdgePin: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let height = self.height
        // After this layout pass, so the window has its current frame.
        DispatchQueue.main.async {
            // Compare content with content: comparing the frame with the content height would
            // resize forever, each resize triggering another layout.
            guard let window = nsView.window, height > 0 else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - height) > 0.5 else { return }
            let target = NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height)
            window.setFrame(window.frameRect(forContentRect: target), display: true)
        }
    }
}
