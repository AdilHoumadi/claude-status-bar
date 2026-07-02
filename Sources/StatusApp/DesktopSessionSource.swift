import Foundation
import StatusCore

/// Reads Claude Desktop (Cowork / Code tab) sessions from their host-mirrored transcript
/// files. Those runs are sandboxed so they never fire hooks; instead we derive state from
/// `lastActivityAt` in each `local_*.json`. Parsed metadata is cached by file mtime so we
/// don't re-read large (~600 KB) transcripts every poll.
///
/// Limitation: a transcript at rest can't reliably signal "waiting for you" (red), so
/// Desktop sessions are only surfaced as yellow (recently active) or green (idle).
public final class DesktopSessionSource {
    private struct Meta {
        let id: String
        let cwd: String?
        let lastActivity: Date
        let archived: Bool
    }

    private var cache: [String: (mtime: Date, meta: Meta?)] = [:]
    private let baseDir: URL?

    public init(baseDir: URL? = DesktopSessionSource.defaultDirectory()) {
        self.baseDir = baseDir
    }

    public static func defaultDirectory() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// Active within `activeWindow` → yellow; otherwise idle → green. Archived and
    /// beyond-`ttl` sessions are dropped.
    public func sessions(now: Date, ttl: TimeInterval = 1800, activeWindow: TimeInterval = 12) -> [SessionViewItem] {
        guard let base = baseDir else { return [] }
        var out: [SessionViewItem] = []
        for url in transcriptFiles(base) {
            guard let mtime = modificationDate(url), now.timeIntervalSince(mtime) <= ttl else { continue }
            let meta: Meta?
            if let cached = cache[url.path], cached.mtime == mtime {
                meta = cached.meta
            } else {
                meta = parse(url)
                cache[url.path] = (mtime, meta)
            }
            guard let m = meta, !m.archived, now.timeIntervalSince(m.lastActivity) <= ttl else { continue }
            let idle = now.timeIntervalSince(m.lastActivity)
            out.append(SessionViewItem(
                id: m.id,
                state: idle < activeWindow ? .yellow : .green,
                cwd: m.cwd,
                elapsed: max(0, idle)
            ))
        }
        return out
    }

    // MARK: - internals

    private func transcriptFiles(_ base: URL) -> [URL] {
        let fm = FileManager.default
        func children(_ dir: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        // base / <account> / <session> / local_*.json
        return children(base)
            .flatMap(children)          // account dirs -> session dirs
            .flatMap(children)          // session dirs -> files
            .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func parse(_ url: URL) -> Meta? {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ms = obj["lastActivityAt"] as? Double else { return nil }
        let id = (obj["sessionId"] as? String) ?? (obj["cliSessionId"] as? String) ?? url.lastPathComponent
        return Meta(
            id: id,
            cwd: obj["cwd"] as? String,
            lastActivity: Date(timeIntervalSince1970: ms / 1000),
            archived: (obj["isArchived"] as? Bool) ?? false
        )
    }
}
