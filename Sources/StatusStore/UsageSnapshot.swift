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

    /// A compact one-line status for the terminal when this binary is used as the statusline,
    /// e.g. "Opus 4.8 · claude-status-bar · ctx 40% · 5h 8% · wk 32%" (5h/wk coloured by
    /// threshold). Segments are omitted when their data is absent.
    public static func statusLine(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        var parts: [String] = []
        if let name = (obj["model"] as? [String: Any])?["display_name"] as? String {
            parts.append(stripContextSuffix(name))
        }
        if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
            parts.append((cwd as NSString).lastPathComponent)
        }
        if let ctx = pct((obj["context_window"] as? [String: Any])?["used_percentage"]) {
            parts.append("ctx \(ctx)%")
        }
        if let rl = obj["rate_limits"] as? [String: Any] {
            if let p = pct((rl["five_hour"] as? [String: Any])?["used_percentage"]) {
                parts.append("5h " + colored("\(p)%", p))
            }
            if let p = pct((rl["seven_day"] as? [String: Any])?["used_percentage"]) {
                parts.append("wk " + colored("\(p)%", p))
            }
        }
        return parts.joined(separator: "\u{1B}[2m · \u{1B}[0m")   // dim separators
    }

    // MARK: - parsing helpers

    private static func pct(_ raw: Any?) -> Int? {
        guard let n = raw as? NSNumber else { return nil }
        return Int(min(100, max(0, n.doubleValue)).rounded())
    }

    /// ANSI colour by the same thresholds as the bar: green <75, yellow <90, red ≥90.
    private static func colored(_ s: String, _ pct: Int) -> String {
        let code = pct >= 90 ? "31" : (pct >= 75 ? "33" : "32")
        return "\u{1B}[\(code)m\(s)\u{1B}[0m"
    }

    /// Drop a trailing "(… context …)" suffix, e.g. "Opus 4.8 (1M context)" → "Opus 4.8".
    private static func stripContextSuffix(_ name: String) -> String {
        if let r = name.range(of: #"\s*\([^)]*context[^)]*\)"#,
                              options: [.regularExpression, .caseInsensitive]) {
            return String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

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
