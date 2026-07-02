import Foundation
import StatusCore
import StatusStore
import TestSupport

private func makeTempStore() -> StateStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-test-\(UUID().uuidString)", isDirectory: true)
    return StateStore(directory: dir)
}

func stateStoreTests() -> TestSuite { ("StateStoreTests", { t in
    let store = makeTempStore()
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let rec = SessionRecord(sessionId: "abc", state: .yellow, cwd: "/p", updatedAt: t0, stateSince: t0)

    // round-trip
    try? store.write(rec)
    t.expectEqual(store.readAll().count, 1)
    t.expectEqual(store.read("abc"), rec)

    // overwrite replaces cleanly (no duplicate file)
    var rec2 = rec
    rec2.state = .green
    try? store.write(rec2)
    t.expectEqual(store.read("abc")?.state, .green)
    t.expectEqual(store.readAll().count, 1)

    // delete
    store.delete("abc")
    t.expectEqual(store.read("abc"), nil)
    t.expectEqual(store.readAll().count, 0)

    // reap: stale removed, fresh kept
    let old = Date(timeIntervalSince1970: 1_000_000)
    let fresh = Date(timeIntervalSince1970: 2_000_000)
    try? store.write(SessionRecord(sessionId: "stale", state: .yellow, cwd: nil, updatedAt: old, stateSince: old))
    try? store.write(SessionRecord(sessionId: "live", state: .yellow, cwd: nil, updatedAt: fresh, stateSince: fresh))
    let now = Date(timeIntervalSince1970: 2_000_100)
    let removed = store.reap(ttl: 1000, now: now)
    t.expectEqual(removed, 1)
    t.expectEqual(store.read("stale"), nil)
    t.expect(store.read("live") != nil, "live session should survive reap")
}) }

func ignoreListTests() -> TestSuite { ("IgnoreListTests", { t in
    let prefixes = ["/Users/me/tools", "/tmp/work/"]
    // exact + nested paths under an ignored prefix
    t.expect(IgnoreList.isIgnored("/Users/me/tools", prefixes: prefixes), "exact match ignored")
    t.expect(IgnoreList.isIgnored("/Users/me/tools/server", prefixes: prefixes), "nested path ignored")
    t.expect(IgnoreList.isIgnored("/tmp/work/x", prefixes: prefixes), "trailing-slash prefix ignored")
    // not a prefix-boundary match — must not false-positive on sibling dirs
    t.expect(!IgnoreList.isIgnored("/Users/me/tools-other", prefixes: prefixes), "sibling not ignored")
    t.expect(!IgnoreList.isIgnored("/Users/me/projects/app", prefixes: prefixes), "unrelated not ignored")
    t.expect(!IgnoreList.isIgnored(nil, prefixes: prefixes), "nil cwd not ignored")
    t.expect(!IgnoreList.isIgnored("/Users/me/tools", prefixes: []), "empty list ignores nothing")

    // reading + tilde expansion from a file
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("csb-ign-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("ignore.txt")
    try? Data("~/tools\n\n  /tmp/x  \n".utf8).write(to: file)
    let read = IgnoreList.prefixes(from: file)
    t.expectEqual(read.count, 2)
    t.expect(read.contains("/tmp/x"), "trimmed line parsed")
    t.expect(read.contains { $0.hasSuffix("/tools") && $0.hasPrefix("/") }, "tilde expanded to absolute")
}) }

func hookProcessorTests() -> TestSuite { ("HookProcessorTests", { t in
    func ev(_ name: String, notif: String? = nil, session: String = "s1", cwd: String? = "/proj") -> HookEvent {
        HookEvent(sessionId: session, hookEventName: name, notificationType: notif, cwd: cwd)
    }
    let store = makeTempStore()

    // Gap 4 — .set upserts: a brand-new session (no SessionStart seen) still appears.
    let t1 = Date(timeIntervalSince1970: 100)
    HookProcessor.apply(ev("UserPromptSubmit"), store: store, now: t1)
    var r = store.read("s1")
    t.expect(r != nil, "UserPromptSubmit should upsert-create the session")
    t.expectEqual(r?.state, .yellow)
    t.expectEqual(r?.stateSince, t1)
    t.expectEqual(r?.cwd, "/proj")

    // Gap 2 — same state later: stateSince preserved, updatedAt advances.
    let t2 = Date(timeIntervalSince1970: 200)
    HookProcessor.apply(ev("PostToolUse"), store: store, now: t2)
    r = store.read("s1")
    t.expectEqual(r?.state, .yellow)
    t.expectEqual(r?.stateSince, t1)
    t.expectEqual(r?.updatedAt, t2)

    // state change resets stateSince
    let t3 = Date(timeIntervalSince1970: 300)
    HookProcessor.apply(ev("Stop"), store: store, now: t3)
    r = store.read("s1")
    t.expectEqual(r?.state, .green)
    t.expectEqual(r?.stateSince, t3)

    // permission prompt → red
    HookProcessor.apply(ev("Notification", notif: "permission_prompt"), store: store, now: Date(timeIntervalSince1970: 400))
    t.expectEqual(store.read("s1")?.state, .red)

    // ignore: irrelevant notification leaves state unchanged
    HookProcessor.apply(ev("Notification", notif: "auth_success"), store: store, now: Date(timeIntervalSince1970: 500))
    t.expectEqual(store.read("s1")?.state, .red)

    // SessionEnd removes the file
    HookProcessor.apply(ev("SessionEnd"), store: store, now: Date(timeIntervalSince1970: 600))
    t.expectEqual(store.read("s1"), nil)

    // unknown event creates nothing
    HookProcessor.apply(ev("WeirdEvent", session: "ghost"), store: store, now: Date(timeIntervalSince1970: 700))
    t.expectEqual(store.read("ghost"), nil)
}) }
