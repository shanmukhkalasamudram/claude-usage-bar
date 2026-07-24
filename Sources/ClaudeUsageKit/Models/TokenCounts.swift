import Foundation

/// A breakdown of token usage for a single request or an aggregate.
///
/// Claude bills four distinct token classes at different rates, so we keep
/// them separate all the way through the pipeline and only collapse them
/// when computing a cost or a headline "total".
public struct TokenCounts: Equatable, Sendable, Codable {
    /// Fresh input tokens (not served from cache).
    public var input: Int
    /// Generated output tokens.
    public var output: Int
    /// Tokens written into the ephemeral prompt cache with a 5-minute TTL.
    public var cacheWrite5m: Int
    /// Tokens written into the ephemeral prompt cache with a 1-hour TTL.
    public var cacheWrite1h: Int
    /// Tokens read back from the prompt cache.
    public var cacheRead: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheWrite5m: Int = 0,
        cacheWrite1h: Int = 0,
        cacheRead: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    /// Every token class summed together. This is the number most people mean
    /// by "tokens used".
    public var total: Int {
        input + output + cacheWrite5m + cacheWrite1h + cacheRead
    }

    /// Tokens excluding cache reads. Cache reads are cheap and dominate the
    /// raw total, so burn-rate indicators read better against this figure.
    public var billableWeighted: Int {
        input + output + cacheWrite5m + cacheWrite1h
    }

    public static let zero = TokenCounts()

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }
}
