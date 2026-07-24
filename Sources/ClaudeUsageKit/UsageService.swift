import Foundation

/// High-level façade that ties loading, blocking and aggregation together and
/// produces a ``UsageSnapshot``. Both the menu bar app and the CLI use this.
public struct UsageService: Sendable {
    private let loader: TranscriptLoader
    private let calculator: BlockCalculator
    private let calendar: Calendar

    public init(
        loader: TranscriptLoader = TranscriptLoader(),
        calculator: BlockCalculator = BlockCalculator(),
        calendar: Calendar = .current
    ) {
        self.loader = loader
        self.calculator = calculator
        self.calendar = calendar
    }

    /// Convenience initializer that wires up a loader for the default
    /// `.claude` config directory.
    public static func makeDefault() -> UsageService {
        UsageService(loader: TranscriptLoader(configDirectory: TranscriptLoader.defaultConfigDirectory()))
    }

    /// Compute a snapshot as of `now`.
    ///
    /// Only files modified since the earlier of "start of today", "start of the
    /// month" and "one window before now" are read, so refreshes stay cheap.
    public func snapshot(now: Date = Date()) -> UsageSnapshot {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? startOfDay
        let windowFloor = now.addingTimeInterval(-calculator.windowLength)

        // Read a little earlier than the strict minimum so a block that opened
        // just before the cutoff is still captured whole.
        let cutoff = min(startOfMonth, min(startOfDay, windowFloor))
            .addingTimeInterval(-calculator.windowLength)

        let entries = loader.load(modifiedSince: cutoff)

        let active = calculator.activeBlock(from: entries, now: now)
        let today = UsageTotals.total(of: entries, from: startOfDay, to: now)
        let month = UsageTotals.total(of: entries, from: startOfMonth, to: now)

        return UsageSnapshot(
            generatedAt: now,
            activeBlock: active,
            today: today,
            month: month
        )
    }
}
