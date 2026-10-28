import AppKit
import StatusStore
import SwiftUI

/// A small window to edit the ignore list. Saved on Save only: writing on every keystroke
/// briefly ignored everything while a path was half-typed (a lone "/" matches every cwd).
@MainActor
enum IgnoredProjectsEditor {
    private static var window: NSWindow?

    static func show(onSave: @escaping () -> Void) {
        window?.close()
        let url = IgnoreList.defaultFileURL()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let view = IgnoredProjectsView(text: text, close: { window?.close() }) { text in
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
                onSave()
                return nil
            } catch {
                return "Couldn't save: \(error.localizedDescription)"
            }
        }
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = "Ignored Projects"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.appearance = AppearanceMode.current.nsAppearance
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

private struct IgnoredProjectsView: View {
    @State var text: String
    let close: () -> Void
    /// Returns an error to show, or nil to close.
    let save: (String) -> String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppMark().frame(width: 22, height: 22)
                Text("Ignored Projects").font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                Text("One folder per line, e.g. ~/Projects/automation. Sessions under these folders are never shown. Lines starting with # are comments.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.korAlert)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let message = save(text) { error = message } else { close() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}
