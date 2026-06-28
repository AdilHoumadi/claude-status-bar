import AppKit
import Foundation

// Renders the app icon (a glowing traffic-light on a dark squircle) into an .iconset.
// Usage: swift scripts/make-icon.swift <output.iconset dir>

func makeIconPNG(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()

    // Background squircle with a dark vertical gradient.
    let corner = s * 0.2237
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let bgGrad = CGGradient(colorsSpace: cs, colors: [
        NSColor(srgbRed: 0.18, green: 0.19, blue: 0.23, alpha: 1).cgColor,
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    // soft top sheen
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.05).cgColor)
    ctx.fill(CGRect(x: 0, y: s * 0.62, width: s, height: s * 0.38))
    ctx.restoreGState()

    // Housing.
    let hw = s * 0.42, hh = s * 0.74
    let housing = CGRect(x: (s - hw) / 2, y: (s - hh) / 2, width: hw, height: hh)
    let hr = s * 0.14
    ctx.addPath(CGPath(roundedRect: housing, cornerWidth: hr, cornerHeight: hr, transform: nil))
    ctx.setFillColor(NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: housing, cornerWidth: hr, cornerHeight: hr, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()

    // Three lamps, all lit and glowing (red, amber, green).
    let lampD = s * 0.215
    let cx = s / 2
    let pad = housing.height * 0.10
    let usable = housing.height - 2 * pad
    let gap = (usable - 3 * lampD) / 2
    let colors = [
        NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1),
        NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.82, blue: 0.35, alpha: 1),
    ]
    for i in 0..<3 {
        let y = housing.maxY - pad - CGFloat(i) * (lampD + gap) - lampD
        let rect = CGRect(x: cx - lampD / 2, y: y, width: lampD, height: lampD)
        ctx.setFillColor(colors[i].withAlphaComponent(0.32).cgColor)
        ctx.fillEllipse(in: rect.insetBy(dx: -lampD * 0.26, dy: -lampD * 0.26))
        ctx.setFillColor(colors[i].cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.fillEllipse(in: CGRect(x: rect.minX + lampD * 0.24, y: rect.minY + lampD * 0.5,
                                   width: lampD * 0.3, height: lampD * 0.28))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// (filename, pixel size)
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    let data = makeIconPNG(px)
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("Wrote \(variants.count) PNGs to \(out)")
