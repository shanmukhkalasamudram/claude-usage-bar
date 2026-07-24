import Foundation

/// Groups usage entries into fixed-length rolling windows ("blocks").
///
/// The algorithm mirrors the widely-used `ccusage` heuristic so numbers line
/// up with that tool:
///
/// 1. Entries are processed in timestamp order.
/// 2. The first entry opens a block whose start is floored to the top of its
///    hour.
/// 3. An entry starts a *new* block when either it lands at or beyond the
///    window length from the current block's start, or more than a window
///    length has elapsed since the previous entry (an idle gap).
/// 4. A block's nominal end is `start + windowLength`; its real reset time for
///    display purposes is that nominal end.
public struct BlockCalculator: Sendable {
    /// Length of a rolling window. Defaults to 5 hours.
    public let windowLength: TimeInterval
    private let calendar: Calendar

    public init(windowLength: TimeInterval = 5 * 60 * 60) {
        self.windowLength = windowLength
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        self.calendar = calendar
    }

    /// Build blocks from entries. Input need not be sorted.
    public func blocks(from entries: [UsageEntry]) -> [SessionBlock] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        var blocks: [SessionBlock] = []
        var accumulator: Accumulator?

        for entry in sorted {
            if var current = accumulator {
                let sinceStart = entry.timestamp.timeIntervalSince(current.startTime)
                let sinceLast = entry.timestamp.timeIntervalSince(current.lastActivity)
                if sinceStart >= windowLength || sinceLast >= windowLength {
                    blocks.append(current.finalize(windowLength: windowLength))
                    accumulator = Accumulator(start: floorToHour(entry.timestamp), first: entry)
                } else {
                    current.add(entry)
                    accumulator = current
                }
            } else {
                accumulator = Accumulator(start: floorToHour(entry.timestamp), first: entry)
            }
        }

        if let last = accumulator {
            blocks.append(last.finalize(windowLength: windowLength))
        }
        return blocks
    }

    /// The block that is still open at `now`, if any. This is the window whose
    /// countdown the menu bar shows.
    public func activeBlock(from entries: [UsageEntry], now: Date) -> SessionBlock? {
        blocks(from: entries).last { $0.isActive(now: now) }
    }

    private func floorToHour(_ date: Date) -> Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: date)
        ) ?? date
    }

    /// Mutable state while a block is being assembled.
    private struct Accumulator {
        let startTime: Date
        var lastActivity: Date
        var tokens: TokenCounts
        var entryCount: Int
        var modelOrder: [String]
        var modelSet: Set<String>

        init(start: Date, first entry: UsageEntry) {
            self.startTime = start
            self.lastActivity = entry.timestamp
            self.tokens = entry.tokens
            self.entryCount = 1
            self.modelOrder = [entry.model]
            self.modelSet = [entry.model]
        }

        mutating func add(_ entry: UsageEntry) {
            lastActivity = entry.timestamp
            tokens += entry.tokens
            entryCount += 1
            if modelSet.insert(entry.model).inserted {
                modelOrder.append(entry.model)
            }
        }

        func finalize(windowLength: TimeInterval) -> SessionBlock {
            SessionBlock(
                startTime: startTime,
                endTime: startTime.addingTimeInterval(windowLength),
                lastActivity: lastActivity,
                tokens: tokens,
                entryCount: entryCount,
                models: modelOrder
            )
        }
    }
}
