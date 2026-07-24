import Foundation

/// A simple sum of tokens over some set of entries.
public struct UsageTotals: Equatable, Sendable {
    public var tokens: TokenCounts
    public var entryCount: Int

    public init(tokens: TokenCounts = .zero, entryCount: Int = 0) {
        self.tokens = tokens
        self.entryCount = entryCount
    }

    public static let zero = UsageTotals()

    public mutating func add(_ entry: UsageEntry) {
        tokens += entry.tokens
        entryCount += 1
    }

    /// Sum entries whose timestamp falls in `[start, end)`.
    public static func total(
        of entries: [UsageEntry],
        from start: Date,
        to end: Date
    ) -> UsageTotals {
        var totals = UsageTotals.zero
        for entry in entries where entry.timestamp >= start && entry.timestamp < end {
            totals.add(entry)
        }
        return totals
    }
}
