import Foundation
import StatusApp
import StatusCore
import StatusStore
import TestSupport

func statusViewModelTests() -> TestSuite { ("StatusViewModelTests", { t in
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-vm-\(UUID().uuidString)", isDirectory: true)
    let store = StateStore(directory: dir)
    let now = Date(timeIntervalSince1970: 10_000)

    try? store.write(SessionRecord(sessionId: "a", state: .green, cwd: "/work/alpha",
                                   updatedAt: now, stateSince: Date(timeIntervalSince1970: 9_000)))
    try? store.write(SessionRecord(sessionId: "b", state: .red, cwd: "/work/beta",
                                   updatedAt: now, stateSince: Date(timeIntervalSince1970: 9_500)))
    try? store.write(SessionRecord(sessionId: "c", state: .yellow, cwd: "/work/gamma",
                                   updatedAt: now, stateSince: Date(timeIntervalSince1970: 9_900)))

    var clockNow = now
    let vm = StatusViewModel(store: store, ttl: 1800, clock: { clockNow })
    t.expect(vm.refresh(), "first refresh reports a change")

    // worst-state-wins aggregate
    t.expectEqual(vm.aggregate, .red)
    // every session present, sorted worst-first
    t.expectEqual(vm.sessions.count, 3)
    t.expectEqual(vm.sessions.map(\.state), [.red, .yellow, .green])
    // elapsed derived from stateSince (not updatedAt)
    let red = vm.sessions.first { $0.id == "b" }
    t.expectEqual(red?.elapsed(at: now), 500)        // 10000 - 9500
    t.expectEqual(red?.cwd, "/work/beta")
    t.expectEqual(red?.displayName, "beta")

    // time passing alone is not a change (elapsed is derived at render time)
    clockNow = Date(timeIntervalSince1970: 10_060)
    t.expect(!vm.refresh(), "unchanged store reports no change as time passes")
    t.expectEqual(vm.sessions.count, 3)

    // a state change on disk is a change
    try? store.write(SessionRecord(sessionId: "c", state: .green, cwd: "/work/gamma",
                                   updatedAt: clockNow, stateSince: clockNow))
    t.expect(vm.refresh(), "state change reports a change")
    t.expectEqual(vm.sessions.map(\.state), [.red, .green, .green])

    // stale sessions reaped on refresh
    let later = Date(timeIntervalSince1970: 15_000) // 5000s after updatedAt; ttl 1800
    let vm2 = StatusViewModel(store: store, ttl: 1800, clock: { later })
    vm2.refresh()
    t.expectEqual(vm2.sessions.count, 0)
    t.expectEqual(vm2.aggregate, .green)
}) }
