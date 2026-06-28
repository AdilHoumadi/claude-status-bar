import AppKit
import StatusCore

private func notifLampColor(_ s: SessionState) -> NSColor {
    switch s {
    case .red: return NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    case .yellow: return NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    case .green: return NSColor(srgbRed: 0.20, green: 0.82, blue: 0.35, alpha: 1)
    }
}

/// Renders a traffic-light logo with only `active` lit, writes it to a temp PNG, and
/// returns the URL for use as a UNNotificationAttachment (which takes ownership of it).
func notificationIconURL(for active: SessionState) -> URL? {
    guard let data = renderNotificationIcon(active, size: 256) else { return nil }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-notif-\(active.rawValue)-\(UUID().uuidString).png")
    do { try data.write(to: url); return url } catch { return nil }
}

private func renderNotificationIcon(_ active: SessionState, size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
    let cs = CGColorSpaceCreateDeviceRGB()

    // Dark rounded-square background.
    let corner = s * 0.2237
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()
    if let grad = CGGradient(colorsSpace: cs, colors: [
        NSColor(srgbRed: 0.18, green: 0.19, blue: 0.23, alpha: 1).cgColor,
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    }
    ctx.restoreGState()

    // Housing.
    let hw = s * 0.42, hh = s * 0.74
    let housing = CGRect(x: (s - hw) / 2, y: (s - hh) / 2, width: hw, height: hh)
    ctx.addPath(CGPath(roundedRect: housing, cornerWidth: s * 0.14, cornerHeight: s * 0.14, transform: nil))
    ctx.setFillColor(NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor)
    ctx.fillPath()

    // Lamps — only the active one lit.
    let lampD = s * 0.215
    let cx = s / 2
    let pad = housing.height * 0.10
    let gap = (housing.height - 2 * pad - 3 * lampD) / 2
    for (i, state) in [SessionState.red, .yellow, .green].enumerated() {
        let y = housing.maxY - pad - CGFloat(i) * (lampD + gap) - lampD
        let rect = CGRect(x: cx - lampD / 2, y: y, width: lampD, height: lampD)
        if state == active {
            ctx.setFillColor(notifLampColor(state).withAlphaComponent(0.32).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: -lampD * 0.26, dy: -lampD * 0.26))
            ctx.setFillColor(notifLampColor(state).cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.4).cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.minX + lampD * 0.24, y: rect.minY + lampD * 0.5,
                                       width: lampD * 0.3, height: lampD * 0.28))
        } else {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
            ctx.fillEllipse(in: rect)
        }
    }

    return rep.representation(using: .png, properties: [:])
}
