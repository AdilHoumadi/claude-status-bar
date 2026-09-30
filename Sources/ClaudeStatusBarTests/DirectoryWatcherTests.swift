import Foundation
import StatusCore
import StatusStore
import TestSupport

func directoryWatcherTests() -> TestSuite { ("DirectoryWatcherTests", { t in
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-watch-\(UUID().uuidString)", isDirectory: true)
    let store = StateStore(directory: dir)
    let fired = DispatchSemaphore(value: 0)
    let watcher = DirectoryWatcher(
        directory: dir, queue: DispatchQueue(label: "csb.watch.test"), latency: 0.05
    ) { fired.signal() }
    watcher.start()
    Thread.sleep(forTimeInterval: 0.1)   // let the source arm (it also creates the dir)

    // an atomic store write fires the callback
    let t0 = Date(timeIntervalSince1970: 1_000)
    try? store.write(SessionRecord(sessionId: "w", state: .yellow, cwd: nil, updatedAt: t0, stateSince: t0))
    t.expect(fired.wait(timeout: .now() + 2) == .success, "write should fire the watcher")

    // a burst of writes coalesces into one callback
    for i in 0..<5 {
        try? store.write(SessionRecord(sessionId: "b\(i)", state: .green, cwd: nil, updatedAt: t0, stateSince: t0))
    }
    t.expect(fired.wait(timeout: .now() + 2) == .success, "burst should fire the watcher")
    t.expect(fired.wait(timeout: .now() + 0.3) == .timedOut, "burst should fire only once")

    // delete fires too (SessionEnd removes the file)
    store.delete("w")
    t.expect(fired.wait(timeout: .now() + 2) == .success, "delete should fire the watcher")

    // recreated directory is re-watched
    try? FileManager.default.removeItem(at: dir)
    _ = fired.wait(timeout: .now() + 1)          // the removal itself
    Thread.sleep(forTimeInterval: 0.2)
    try? store.write(SessionRecord(sessionId: "r", state: .red, cwd: nil, updatedAt: t0, stateSince: t0))
    t.expect(fired.wait(timeout: .now() + 2) == .success, "writes after recreate should fire")

    watcher.stop()
}) }
