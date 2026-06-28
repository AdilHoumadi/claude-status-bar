import StatusApp
import StatusCore
import TestSupport

func floatingSelectionTests() -> TestSuite { ("FloatingSelectionTests", { t in
    func item(_ id: String, _ s: SessionState) -> SessionViewItem {
        SessionViewItem(id: id, state: s, cwd: nil, elapsed: 0)
    }

    // 7 sessions, cap 5: shows 5 worst-first, overflow 2
    let many = [
        item("a", .green), item("b", .red), item("c", .green),
        item("d", .yellow), item("e", .green), item("f", .red), item("g", .yellow),
    ]
    let r = FloatingSelection.select(many, max: 5)
    t.expectEqual(r.shown.count, 5)
    t.expectEqual(r.overflow, 2)
    t.expectEqual(r.shown.map(\.state), [.red, .red, .yellow, .yellow, .green])

    // fewer than cap: no overflow
    let r2 = FloatingSelection.select([item("x", .green), item("y", .red)], max: 5)
    t.expectEqual(r2.shown.count, 2)
    t.expectEqual(r2.overflow, 0)
    t.expectEqual(r2.shown.map(\.state), [.red, .green])

    // empty
    let r3 = FloatingSelection.select([], max: 5)
    t.expectEqual(r3.shown.count, 0)
    t.expectEqual(r3.overflow, 0)
}) }
