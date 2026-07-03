import CoreGraphics

/// Geometry for the floating panel — shared by the SwiftUI content (frame width) and the
/// window controller (window size) so they always agree, and unit-testable.
public enum FloatingLayout {
    public static let cell: CGFloat = 46        // one traffic-light cell (label) width
    public static let gap: CGFloat = 4          // spacing between cells
    public static let chip: CGFloat = 26        // the +N overflow chip width
    public static let headerMin: CGFloat = 118  // min width so "CLAUDE CODE" never clips
    public static let padding: CGFloat = 12     // horizontal content padding (each side)
    public static let baseHeight: CGFloat = 120 // panel height with just the lights row
    public static let usageBarExtra: CGFloat = 42 // extra height when the 5h usage bar shows
    public static let usageMinContent: CGFloat = 178 // min content width so the usage row fits

    /// Panel height, taller when the usage bar is shown at the bottom.
    public static func windowHeight(showUsage: Bool) -> CGFloat {
        baseHeight + (showUsage ? usageBarExtra : 0)
    }

    /// Width of the content for `shown` lights (+ chip if there's overflow), floored so the
    /// header always fits — and wider still when the usage bar's row needs room.
    public static func contentWidth(shown: Int, overflow: Bool, showUsage: Bool = false) -> CGFloat {
        let n = max(shown, 0)
        var w = n == 0 ? headerMin : CGFloat(n) * cell + CGFloat(n - 1) * gap
        if n > 0, overflow { w += gap + chip }
        w = max(w, headerMin)
        if showUsage { w = max(w, usageMinContent) }
        return w
    }

    /// Full window width (content + padding on both sides).
    public static func windowWidth(shown: Int, overflow: Bool, showUsage: Bool = false) -> CGFloat {
        contentWidth(shown: shown, overflow: overflow, showUsage: showUsage) + padding * 2
    }
}
