import Foundation

/// A point-in-time view of the account rate-limit windows Claude Code reports.
///
/// Claude Code only hands these numbers to a **statusline** command (on stdin as
/// `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`); they aren't in hook
/// payloads or any file it writes. So the flow is: a statusline runs `claude-statusbar-hook
/// --usage-snapshot`, which parses that stdin and persists this snapshot to `usage.json`; the
/// menu-bar app then reads it. On-disk shape matches the common external-usage convention:
/// `{ updated_at, five_hour: {used_percentage, resets_at}, seven_day: {…} }` (epoch seconds).
public struct UsageSnapshot: Equatable, Sendable {
    public var updatedAt: Date
    public var fiveHourPercent: Int?
    public var fiveHourResetsAt: Date?
    public var sevenDayPercent: Int?
    public var sevenDayResetsAt: Date?

    public init(updatedAt: Date, fiveHourPercent: Int?, fiveHourResetsAt: Date?,
                sevenDayPercent: Int?, sevenDayResetsAt: Date?) {
        self.updatedAt = updatedAt
        self.fiveHourPercent = fiveHourPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayPercent = sevenDayPercent
        self.sevenDayResetsAt = sevenDayResetsAt
    }

    /// True when this snapshot is too old to trust (the statusline hasn't fired lately).
    public func isStale(now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(updatedAt) > maxAge
    }
}

public enum UsageStore {
    /// `~/.claude/statusbar/usage.json`.
    public static func defaultURL() -> URL {
        StateStore.defaultDirectory().appendingPathComponent("usage.json")
    }

    /// Parse the JSON Claude Code pipes to a statusline command (stdin) into a snapshot.
    /// Returns nil when there are no rate limits (e.g. API / Bedrock / Vertex usage).
    public static func fromStatuslineStdin(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = obj["rate_limits"] as? [String: Any] else { return nil }
        let (fp, fr) = window(rl["five_hour"])
        let (sp, sr) = window(rl["seven_day"])
        if fp == nil, sp == nil, fr == nil, sr == nil { return nil }
        return UsageSnapshot(updatedAt: now, fiveHourPercent: fp, fiveHourResetsAt: fr,
                             sevenDayPercent: sp, sevenDayResetsAt: sr)
    }

    /// Read a persisted snapshot from disk (tolerant of epoch seconds or milliseconds).
    public static func read(_ url: URL = defaultURL()) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updated = date(obj["updated_at"]) else { return nil }
        let (fp, fr) = window(obj["five_hour"])
        let (sp, sr) = window(obj["seven_day"])
        if fp == nil, sp == nil { return nil }
        return UsageSnapshot(updatedAt: updated, fiveHourPercent: fp, fiveHourResetsAt: fr,
                             sevenDayPercent: sp, sevenDayResetsAt: sr)
    }

    public static func write(_ snapshot: UsageSnapshot, to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonData(snapshot).write(to: url, options: [.atomic])
    }

    static func jsonData(_ s: UsageSnapshot) -> Data {
        var out: [String: Any] = ["updated_at": s.updatedAt.timeIntervalSince1970]
        func win(_ p: Int?, _ r: Date?) -> [String: Any]? {
            var m: [String: Any] = [:]
            if let p { m["used_percentage"] = p }
            if let r { m["resets_at"] = r.timeIntervalSince1970 }
            return m.isEmpty ? nil : m
        }
        if let f = win(s.fiveHourPercent, s.fiveHourResetsAt) { out["five_hour"] = f }
        if let d = win(s.sevenDayPercent, s.sevenDayResetsAt) { out["seven_day"] = d }
        return (try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - parsing helpers

    private static func window(_ raw: Any?) -> (Int?, Date?) {
        guard let w = raw as? [String: Any] else { return (nil, nil) }
        let pct = (w["used_percentage"] as? NSNumber).map {
            Int(min(100, max(0, $0.doubleValue)).rounded())
        }
        return (pct, date(w["resets_at"]))
    }

    /// Accepts epoch seconds or milliseconds; ignores non-positive / non-numeric.
    private static func date(_ raw: Any?) -> Date? {
        guard let n = raw as? NSNumber else { return nil }
        let v = n.doubleValue
        guard v > 0 else { return nil }
        return Date(timeIntervalSince1970: v > 1e12 ? v / 1000 : v)
    }
}
