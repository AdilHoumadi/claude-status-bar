import Foundation
import StatusCore

/// Reads and writes per-session state files. The directory is injectable so tests run
/// against a temp dir instead of the real `~/.claude/statusbar/`.
public struct StateStore: Sendable {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        self.decoder = dec
    }

    /// `~/.claude/statusbar/`.
    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/statusbar", isDirectory: true)
    }

    private func fileURL(_ sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).json")
    }

    public func write(_ record: SessionRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(record)
        // `.atomic` writes to a temp file and renames into place — no partial reads.
        try data.write(to: fileURL(record.sessionId), options: [.atomic])
    }

    public func read(_ sessionId: String) -> SessionRecord? {
        guard let data = try? Data(contentsOf: fileURL(sessionId)) else { return nil }
        return try? decoder.decode(SessionRecord.self, from: data)
    }

    public func readAll() -> [SessionRecord] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SessionRecord.self, from: data) // skip corrupt
            }
    }

    public func delete(_ sessionId: String) {
        try? FileManager.default.removeItem(at: fileURL(sessionId))
    }

    @discardableResult
    public func reap(ttl: TimeInterval, now: Date) -> Int {
        var removed = 0
        for record in readAll() where now.timeIntervalSince(record.updatedAt) > ttl {
            delete(record.sessionId)
            removed += 1
        }
        return removed
    }
}
