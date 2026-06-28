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

    let vm = StatusViewModel(store: store, ttl: 1800, clock: { now })
    vm.refresh()

    // worst-state-wins aggregate
    t.expectEqual(vm.aggregate, .red)
    // every session present, sorted worst-first
    t.expectEqual(vm.sessions.count, 3)
    t.expectEqual(vm.sessions.map(\.state), [.red, .yellow, .green])
    // elapsed derived from stateSince (not updatedAt)
    let red = vm.sessions.first { $0.id == "b" }
    t.expectEqual(red?.elapsed, 500)        // 10000 - 9500
    t.expectEqual(red?.cwd, "/work/beta")
    t.expectEqual(red?.displayName, "beta")

    // stale sessions reaped on refresh
    let later = Date(timeIntervalSince1970: 15_000) // 5000s after updatedAt; ttl 1800
    let vm2 = StatusViewModel(store: store, ttl: 1800, clock: { later })
    vm2.refresh()
    t.expectEqual(vm2.sessions.count, 0)
    t.expectEqual(vm2.aggregate, .green)
}) }
