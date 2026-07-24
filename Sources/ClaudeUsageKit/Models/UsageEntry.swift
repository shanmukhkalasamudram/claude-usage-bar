import Foundation

/// A single billed model response, parsed from one line of a Claude Code
/// transcript (`~/.claude/projects/**/*.jsonl`).
public struct UsageEntry: Equatable, Sendable {
    /// When the response was produced.
    public let timestamp: Date
    /// The model that produced it, e.g. `claude-opus-4-8`.
    public let model: String
    /// Token usage for this response.
    public let tokens: TokenCounts

    /// Stable identity used to de-duplicate entries that appear in more than
    /// one transcript (e.g. resumed or forked sessions). Mirrors the scheme
    /// used by the `ccusage` community tool: `message.id` + `requestId`.
    public let deduplicationKey: String?

    public init(
        timestamp: Date,
        model: String,
        tokens: TokenCounts,
        deduplicationKey: String?
    ) {
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
        self.deduplicationKey = deduplicationKey
    }
}
