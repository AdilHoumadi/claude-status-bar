import CoreGraphics

/// Geometry for the floating panel — shared by the SwiftUI content (frame width) and the
/// window controller (window size) so they always agree, and unit-testable.
public enum FloatingLayout {
    public static let cell: CGFloat = 46        // one traffic-light cell (label) width
    public static let gap: CGFloat = 4          // spacing between cells
    public static let chip: CGFloat = 26        // the +N overflow chip width
    public static let headerMin: CGFloat = 132  // min width so "CLAUDE CODE" + close button never clip
    public static let padding: CGFloat = 12     // horizontal content padding (each side)
    public static let baseHeight: CGFloat = 120 // panel height with just the lights row
    public static let usageBarFirst: CGFloat = 42 // extra height for the divider + first usage bar
    public static let usageBarEach: CGFloat = 28  // extra height per additional usage bar (weekly)
    public static let usageMinContent: CGFloat = 178 // min content width so the usage row fits

    /// Panel height, taller for each usage bar shown at the bottom (0 = none, 1 = 5h, 2 = +weekly).
    public static func windowHeight(usageBars: Int) -> CGFloat {
        guard usageBars > 0 else { return baseHeight }
        return baseHeight + usageBarFirst + CGFloat(usageBars - 1) * usageBarEach
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
