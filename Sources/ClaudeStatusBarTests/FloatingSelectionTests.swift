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

    // same sessions, cap 3 (a lower slider value): shows 3, overflow 4
    let r3cap = FloatingSelection.select(many, max: 3)
    t.expectEqual(r3cap.shown.count, 3)
    t.expectEqual(r3cap.overflow, 4)
    t.expectEqual(r3cap.shown.map(\.state), [.red, .red, .yellow])

    // cap 1: single worst light, rest overflow
    let r1cap = FloatingSelection.select(many, max: 1)
    t.expectEqual(r1cap.shown.count, 1)
    t.expectEqual(r1cap.overflow, 6)

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

func floatingLayoutTests() -> TestSuite { ("FloatingLayoutTests", { t in
    let cell = FloatingLayout.cell, gap = FloatingLayout.gap
    let chip = FloatingLayout.chip, floor = FloatingLayout.headerMin

    // empty / one light: floored to the header min so "CLAUDE CODE" never clips
    t.expectEqual(FloatingLayout.contentWidth(shown: 0, overflow: false), floor)
    t.expectEqual(FloatingLayout.contentWidth(shown: 1, overflow: false), floor)  // 46 < floor

    // three lights, no chip: 3*46 + 2*4 = 146 (above floor)
    t.expectEqual(FloatingLayout.contentWidth(shown: 3, overflow: false), 3*cell + 2*gap)

    // three lights + chip: + gap + chip
    t.expectEqual(FloatingLayout.contentWidth(shown: 3, overflow: true), 3*cell + 2*gap + gap + chip)

    // five lights + chip: the widest case
    t.expectEqual(FloatingLayout.contentWidth(shown: 5, overflow: true), 5*cell + 4*gap + gap + chip)

    // width grows monotonically with count
    t.expect(FloatingLayout.contentWidth(shown: 4, overflow: false) >
             FloatingLayout.contentWidth(shown: 3, overflow: false), "width grows with count")

    // window width = content + padding both sides
    t.expectEqual(FloatingLayout.windowWidth(shown: 3, overflow: true),
                  FloatingLayout.contentWidth(shown: 3, overflow: true) + FloatingLayout.padding * 2)
}) }
