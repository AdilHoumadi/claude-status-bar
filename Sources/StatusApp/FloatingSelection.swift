import Foundation
import StatusCore

/// Selects which sessions the floating panel shows: worst-first, capped, with an
/// overflow count for the rest. Pure so it's testable.
public enum FloatingSelection {
    public struct Result: Equatable, Sendable {
        public let shown: [SessionViewItem]
        public let overflow: Int
        public init(shown: [SessionViewItem], overflow: Int) {
            self.shown = shown
            self.overflow = overflow
        }
    }

    public static func select(_ sessions: [SessionViewItem], max: Int = 5) -> Result {
        let sorted = sessions.sorted { $0.state.priority > $1.state.priority }
        let shown = Array(sorted.prefix(max))
        return Result(shown: shown, overflow: Swift.max(0, sorted.count - shown.count))
    }
}
