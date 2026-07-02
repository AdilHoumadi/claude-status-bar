import CoreGraphics

/// Geometry for the floating panel — shared by the SwiftUI content (frame width) and the
/// window controller (window size) so they always agree, and unit-testable.
public enum FloatingLayout {
    public static let cell: CGFloat = 46        // one traffic-light cell (label) width
    public static let gap: CGFloat = 4          // spacing between cells
    public static let chip: CGFloat = 26        // the +N overflow chip width
    public static let headerMin: CGFloat = 118  // min width so "CLAUDE CODE" never clips
    public static let padding: CGFloat = 12     // horizontal content padding (each side)
    public static let height: CGFloat = 120     // fixed panel height (one row of lights)

    /// Width of the content for `shown` lights (+ chip if there's overflow), floored so the
    /// header always fits.
    public static func contentWidth(shown: Int, overflow: Bool) -> CGFloat {
        let n = max(shown, 0)
        if n == 0 { return headerMin }
        var w = CGFloat(n) * cell + CGFloat(n - 1) * gap
        if overflow { w += gap + chip }
        return max(w, headerMin)
    }

    /// Full window width (content + padding on both sides).
    public static func windowWidth(shown: Int, overflow: Bool) -> CGFloat {
        contentWidth(shown: shown, overflow: overflow) + padding * 2
    }
}
