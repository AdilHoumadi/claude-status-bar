import Foundation
import StatusApp
import StatusCore
import TestSupport

func desktopSessionSourceTests() -> TestSuite { ("DesktopSessionSourceTests", { t in
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("csb-desk-\(UUID().uuidString)", isDirectory: true)
    let sess = base.appendingPathComponent("account/session", isDirectory: true)
    try? fm.createDirectory(at: sess, withIntermediateDirectories: true)

    let now = Date()
    func write(_ name: String, cwd: String, agoSec: Double, archived: Bool = false) {
        let ms = (now.timeIntervalSince1970 - agoSec) * 1000
        let json = "{\"sessionId\":\"\(name)\",\"cwd\":\"\(cwd)\",\"lastActivityAt\":\(ms),\"isArchived\":\(archived)}"
        try? Data(json.utf8).write(to: sess.appendingPathComponent("local_\(name).json"))
    }
    write("active", cwd: "/work/a", agoSec: 2)                    // recent -> yellow
    write("idle", cwd: "/work/b", agoSec: 120)                    // idle -> green
    write("arch", cwd: "/work/c", agoSec: 5, archived: true)      // archived -> skip
    write("stale", cwd: "/work/d", agoSec: 5000)                  // beyond ttl -> skip

    let items = DesktopSessionSource(baseDir: base).sessions(now: now, ttl: 1800, activeWindow: 12)
    t.expectEqual(items.count, 2)
    let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    t.expectEqual(byId["active"]?.state, .yellow)
    t.expectEqual(byId["active"]?.cwd, "/work/a")
    t.expectEqual(byId["active"]?.source, .desktop)
    t.expectEqual(byId["idle"]?.state, .green)
    t.expect(byId["arch"] == nil, "archived session skipped")
    t.expect(byId["stale"] == nil, "stale session skipped")

    // missing directory -> empty, no crash
    let none = DesktopSessionSource(baseDir: base.appendingPathComponent("nope")).sessions(now: now)
    t.expectEqual(none.count, 0)
}) }
