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

    // Desktop/hook dedup: a Cowork session fires hooks AND leaves a transcript for the same
    // folder (different ids). The Desktop copy must be dropped; a hook-less folder survives.
    let ddir = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-vm-dd-\(UUID().uuidString)", isDirectory: true)
    let dstore = StateStore(directory: ddir)
    let dnow = Date(timeIntervalSince1970: 20_000)
    try? dstore.write(SessionRecord(sessionId: "hook1", state: .green, cwd: "/work/shared",
                                    updatedAt: dnow, stateSince: dnow))
    try? dstore.write(SessionRecord(sessionId: "hook2", state: .green, cwd: "/work/shared/",  // trailing slash
                                    updatedAt: dnow, stateSince: dnow))

    let deskBase = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-desk-dd-\(UUID().uuidString)", isDirectory: true)
    let deskSess = deskBase.appendingPathComponent("acct/sess", isDirectory: true)
    try? FileManager.default.createDirectory(at: deskSess, withIntermediateDirectories: true)
    func writeDesk(_ id: String, cwd: String, agoSec: Double) {
        let ms = (dnow.timeIntervalSince1970 - agoSec) * 1000
        let json = "{\"sessionId\":\"\(id)\",\"cwd\":\"\(cwd)\",\"lastActivityAt\":\(ms),\"isArchived\":false}"
        try? Data(json.utf8).write(to: deskSess.appendingPathComponent("local_\(id).json"))
    }
    writeDesk("dupe", cwd: "/work/shared", agoSec: 2)     // same folder as hooks -> dropped
    writeDesk("solo", cwd: "/work/onlyapp", agoSec: 2)    // no hook -> kept as APP

    let vm3 = StatusViewModel(store: dstore, desktop: DesktopSessionSource(baseDir: deskBase),
                              ttl: 1800, clock: { dnow })
    vm3.refresh()
    let ids = Set(vm3.sessions.map(\.id))
    t.expectEqual(vm3.sessions.count, 3)                  // hook1, hook2, solo (dupe dropped)
    t.expect(ids.contains("hook1") && ids.contains("hook2"), "both hook sessions kept")
    t.expect(ids.contains("solo"), "hook-less desktop session kept")
    t.expect(!ids.contains("dupe"), "desktop dupe of a hook folder dropped")
    t.expectEqual(vm3.sessions.first { $0.id == "solo" }?.source, .desktop)
}) }
