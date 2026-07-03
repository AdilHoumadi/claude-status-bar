import Foundation
import StatusStore
import TestSupport

func usageSnapshotTests() -> TestSuite { ("UsageSnapshotTests", { t in
    let now = Date(timeIntervalSince1970: 1_000_000)

    // Parse the statusline stdin shape Claude Code emits (resets_at in epoch seconds).
    let stdin = """
    {"rate_limits":{"five_hour":{"used_percentage":28,"resets_at":1017857},
                     "seven_day":{"used_percentage":71,"resets_at":1500000}},
     "context_window":{"used_percentage":40}}
    """
    let snap = UsageStore.fromStatuslineStdin(Data(stdin.utf8), now: now)
    t.expect(snap != nil, "parsed rate_limits from stdin")
    t.expectEqual(snap?.fiveHourPercent, 28)
    t.expectEqual(snap?.sevenDayPercent, 71)
    t.expectEqual(snap?.fiveHourResetsAt, Date(timeIntervalSince1970: 1017857))
    t.expectEqual(snap?.updatedAt, now)

    // No rate_limits (e.g. API/Bedrock/Vertex) -> nil, no snapshot written.
    t.expect(UsageStore.fromStatuslineStdin(Data("{\"model\":{}}".utf8), now: now) == nil,
             "no rate_limits -> nil")

    // Percent clamped to 0...100.
    let over = UsageStore.fromStatuslineStdin(
        Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":140}}}".utf8), now: now)
    t.expectEqual(over?.fiveHourPercent, 100)

    // Round-trip through disk (write -> read) preserves values.
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("csb-usage-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("usage.json")
    try? UsageStore.write(snap!, to: url)
    let back = UsageStore.read(url)
    t.expectEqual(back?.fiveHourPercent, 28)
    t.expectEqual(back?.sevenDayPercent, 71)
    t.expectEqual(back?.fiveHourResetsAt, Date(timeIntervalSince1970: 1017857))

    // Staleness.
    t.expect(back!.isStale(now: now.addingTimeInterval(1000), maxAge: 900), "old snapshot is stale")
    t.expect(!back!.isStale(now: now.addingTimeInterval(60), maxAge: 900), "recent snapshot is fresh")

    // Missing file -> nil.
    t.expect(UsageStore.read(dir.appendingPathComponent("nope.json")) == nil, "missing file -> nil")

    // Compact status line: model (context suffix stripped), repo, context %, 5h, weekly.
    let full = """
    {"model":{"display_name":"Opus 4.8 (1M context)"},"cwd":"/Users/x/claude-status-bar",
     "context_window":{"used_percentage":40},
     "rate_limits":{"five_hour":{"used_percentage":8},"seven_day":{"used_percentage":32}}}
    """
    let line = UsageStore.statusLine(from: Data(full.utf8))
    t.expect(line.contains("Opus 4.8"), "model shown")
    t.expect(!line.contains("context)"), "context suffix stripped")
    t.expect(line.contains("claude-status-bar"), "repo (cwd basename) shown")
    t.expect(line.contains("ctx 40%"), "context percent shown")
    t.expect(line.contains("5h ") && line.contains("8%"), "5h shown")
    t.expect(line.contains("wk ") && line.contains("32%"), "weekly shown")

    // Empty / non-JSON stdin -> empty line, no crash.
    t.expectEqual(UsageStore.statusLine(from: Data("nonsense".utf8)), "")
}) }
