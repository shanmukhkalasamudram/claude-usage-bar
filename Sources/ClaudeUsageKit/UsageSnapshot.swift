import Foundation

/// An immutable, point-in-time view of usage that the UI renders directly.
public struct UsageSnapshot: Sendable {
    /// When the snapshot was computed.
    public let generatedAt: Date
    /// The currently-open rolling window, or `nil` if nothing is active.
    public let activeBlock: SessionBlock?
    /// Total usage since local midnight today.
    public let today: UsageTotals
    /// Total usage since the start of the local calendar month.
    public let month: UsageTotals

    public init(
        generatedAt: Date,
        activeBlock: SessionBlock?,
        today: UsageTotals,
        month: UsageTotals
    ) {
        self.generatedAt = generatedAt
        self.activeBlock = activeBlock
        self.today = today
        self.month = month
    }

    /// Seconds until the active window resets, or `nil` when idle.
    public var secondsUntilReset: TimeInterval? {
        activeBlock?.timeRemaining(now: generatedAt)
    }

    /// An empty snapshot (no activity found).
    public static func empty(at date: Date) -> UsageSnapshot {
        UsageSnapshot(generatedAt: date, activeBlock: nil, today: .zero, month: .zero)
    }
}
