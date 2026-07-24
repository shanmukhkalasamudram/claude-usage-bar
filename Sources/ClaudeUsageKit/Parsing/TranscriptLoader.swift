import Foundation

/// Reads Claude Code transcripts and turns them into priced ``UsageEntry``
/// values.
///
/// Transcripts live as newline-delimited JSON under
/// `~/.claude/projects/<slug>/<session>.jsonl` (overridable with the
/// `CLAUDE_CONFIG_DIR` environment variable). Each `assistant` line carries a
/// `message.usage` block; other line types are ignored.
// `@unchecked` because the only non-`Sendable` stored value is a `FileManager`,
// which is thread-safe for the read-only operations used here.
public struct TranscriptLoader: @unchecked Sendable {
    private let projectsDirectory: URL
    private let fileManager: FileManager

    /// - Parameters:
    ///   - configDirectory: The `.claude` directory. Defaults to
    ///     `$CLAUDE_CONFIG_DIR` or `~/.claude`.
    ///   - fileManager: Injected for testability.
    public init(
        configDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let base = configDirectory ?? Self.defaultConfigDirectory(fileManager: fileManager)
        self.projectsDirectory = base.appendingPathComponent("projects", isDirectory: true)
        self.fileManager = fileManager
    }

    /// The default `.claude` directory: `$CLAUDE_CONFIG_DIR` if set, else
    /// `~/.claude`.
    public static func defaultConfigDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    /// Load and de-duplicate all usage entries.
    ///
    /// - Parameter modifiedSince: If provided, transcript files last modified
    ///   before this date are skipped. This is a large speed-up when only
    ///   recent activity matters (the active block, today, this month).
    /// - Returns: Entries sorted ascending by timestamp, de-duplicated by
    ///   `message.id`+`requestId`.
    public func load(modifiedSince: Date? = nil) -> [UsageEntry] {
        let files = transcriptFiles(modifiedSince: modifiedSince)
        var entries: [UsageEntry] = []
        var seen = Set<String>()
        entries.reserveCapacity(files.count * 64)

        for file in files {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            contents.enumerateLines { line, _ in
                guard let entry = Self.parseLine(line) else { return }
                if let key = entry.deduplicationKey {
                    guard seen.insert(key).inserted else { return }
                }
                entries.append(entry)
            }
        }

        entries.sort { $0.timestamp < $1.timestamp }
        return entries
    }

    // MARK: - File discovery

    private func transcriptFiles(modifiedSince: Date?) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let cutoff = modifiedSince {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = values?.contentModificationDate, modified < cutoff {
                    continue
                }
            }
            files.append(url)
        }
        return files
    }

    // MARK: - Line parsing

    /// Parse a single JSONL line into an entry, or `nil` if the line is not a
    /// billable assistant response.
    static func parseLine(_ line: String) -> UsageEntry? {
        guard
            let data = line.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(TranscriptLine.self, from: data),
            decoded.type == "assistant",
            let message = decoded.message,
            let usage = message.usage,
            let timestamp = decoded.timestamp.flatMap(Self.parseTimestamp)
        else {
            return nil
        }

        let dedupeKey = Self.deduplicationKey(messageID: message.id, requestID: decoded.requestId)

        return UsageEntry(
            timestamp: timestamp,
            model: message.model ?? "unknown",
            tokens: usage.tokenCounts,
            deduplicationKey: dedupeKey
        )
    }

    static func deduplicationKey(messageID: String?, requestID: String?) -> String? {
        switch (messageID, requestID) {
        case let (id?, req?): return "\(id):\(req)"
        case let (id?, nil): return id
        case let (nil, req?): return req
        default: return nil
        }
    }

    // MARK: - Timestamp parsing

    // `ISO8601DateFormatter.date(from:)` is backed by CFDateFormatter, which is
    // thread-safe for parsing, so sharing these read-only instances across
    // threads is safe despite the type not being `Sendable`.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseTimestamp(_ raw: String) -> Date? {
        fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }
}

// MARK: - Wire format

/// Minimal decodable view over a transcript line. All fields are optional so a
/// single `try?` decode tolerates the many non-usage line shapes.
private struct TranscriptLine: Decodable {
    let type: String?
    let timestamp: String?
    let requestId: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheCreation: CacheCreation?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheCreation = "cache_creation"
        }

        /// Collapse the wire shape into our ``TokenCounts``. When the ephemeral
        /// 5m/1h split is present we honor it; otherwise the aggregate
        /// `cache_creation_input_tokens` is treated as a 5-minute write (the
        /// default TTL).
        var tokenCounts: TokenCounts {
            let write5m: Int
            let write1h: Int
            if let split = cacheCreation {
                write5m = split.ephemeral5m ?? 0
                write1h = split.ephemeral1h ?? 0
            } else {
                write5m = cacheCreationInputTokens ?? 0
                write1h = 0
            }
            return TokenCounts(
                input: inputTokens ?? 0,
                output: outputTokens ?? 0,
                cacheWrite5m: write5m,
                cacheWrite1h: write1h,
                cacheRead: cacheReadInputTokens ?? 0
            )
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral5m: Int?
        let ephemeral1h: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
        }
    }
}
