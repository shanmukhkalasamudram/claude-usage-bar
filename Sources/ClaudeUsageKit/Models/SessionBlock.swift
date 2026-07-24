import Foundation

/// A rolling usage window.
///
/// Claude subscription limits reset on a fixed-length rolling window (5 hours
/// at the time of writing). We reconstruct those windows locally from the
/// transcripts so we can show "time until reset" without any network call.
public struct SessionBlock: Equatable, Sendable {
    /// Start of the window, floored to the top of the hour of the first entry.
    public let startTime: Date
    /// Nominal end of the window: ``startTime`` + the window length.
    public let endTime: Date
    /// Timestamp of the last entry that landed in this window.
    public let lastActivity: Date
    /// Aggregate token usage across the window.
    public let tokens: TokenCounts
    /// Number of billed responses in the window.
    public let entryCount: Int
    /// Distinct models seen in the window.
    public let models: [String]

    public init(
        startTime: Date,
        endTime: Date,
        lastActivity: Date,
        tokens: TokenCounts,
        entryCount: Int,
        models: [String]
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.lastActivity = lastActivity
        self.tokens = tokens
        self.entryCount = entryCount
        self.models = models
    }

    /// Whether the window is still open at `now`.
    public func isActive(now: Date) -> Bool {
        now < endTime
    }

    /// Seconds remaining until the window resets, clamped at zero.
    public func timeRemaining(now: Date) -> TimeInterval {
        max(0, endTime.timeIntervalSince(now))
    }

    /// How far through the window we are, in `0...1`.
    public func progress(now: Date) -> Double {
        let span = endTime.timeIntervalSince(startTime)
        guard span > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startTime) / span))
    }

    /// Average token consumption per minute since the window opened.
    ///
    /// Measured against wall-clock elapsed time (not just active minutes) so it
    /// reflects the pace the limit is actually being spent at.
    public func burnRateTokensPerMinute(now: Date) -> Double {
        let elapsedMinutes = now.timeIntervalSince(startTime) / 60
        guard elapsedMinutes > 0 else { return 0 }
        return Double(tokens.billableWeighted) / elapsedMinutes
    }
}
