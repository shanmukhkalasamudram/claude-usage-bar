import Foundation

/// A single rate-limit window as reported by Anthropic: how much of the limit
/// is consumed, and when it resets.
public struct LimitWindow: Equatable, Sendable {
    /// Percentage of the limit consumed, `0...100`.
    public let utilization: Double
    /// When this window resets.
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    /// Fraction consumed, clamped to `0...1` (for progress bars).
    public var fraction: Double {
        min(1, max(0, utilization / 100))
    }

    /// Seconds until this window resets, clamped at zero.
    public func timeRemaining(now: Date) -> TimeInterval {
        max(0, resetsAt.timeIntervalSince(now))
    }
}

/// The subscription limits shown by Claude's `/usage`: the rolling 5-hour
/// session window and the 7-day (weekly) window, plus the weekly Opus-specific
/// window when the plan has one.
public struct UsageLimits: Equatable, Sendable {
    /// The current 5-hour session window.
    public let session: LimitWindow
    /// The rolling 7-day window (all models).
    public let week: LimitWindow
    /// The weekly Opus-specific window, when present on the plan.
    public let weekOpus: LimitWindow?
    /// When these numbers were fetched.
    public let fetchedAt: Date

    public init(session: LimitWindow, week: LimitWindow, weekOpus: LimitWindow?, fetchedAt: Date) {
        self.session = session
        self.week = week
        self.weekOpus = weekOpus
        self.fetchedAt = fetchedAt
    }
}
