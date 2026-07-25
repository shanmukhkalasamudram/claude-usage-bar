import Foundation

/// A minimal, append-only diagnostic log for field debugging.
///
/// Writes to `~/Library/Logs/ClaudeUsageBar.log`. It records only timings, HTTP
/// statuses, `Retry-After` values, usage percentages, and process/instance
/// info — **never** the OAuth token, account identifiers, or any credential.
/// The file is size-capped so it can be left on safely.
public enum DiagnosticLog {
    /// `~/Library/Logs/ClaudeUsageBar.log`.
    public static let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent("ClaudeUsageBar.log")
    }()

    /// Keep the file small; when it exceeds this, drop the oldest half.
    private static let maxBytes = 512 * 1024

    private static let lock = NSLock()

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Append one line. Best-effort: never throws, never blocks meaningfully.
    public static func log(_ message: String) {
        let line = "\(iso.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        try? fm.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            if (try? handle.offset()).map({ $0 > UInt64(maxBytes) }) == true {
                truncateHead()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Keep only the most recent half of the file so it never grows unbounded.
    private static func truncateHead() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let keep = data.suffix(maxBytes / 2)
        try? keep.write(to: fileURL)
    }
}
