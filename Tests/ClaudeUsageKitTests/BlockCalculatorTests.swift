import XCTest
@testable import ClaudeUsageKit

final class BlockCalculatorTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    private func entry(_ iso: String, model: String = "claude-opus-4-8", tokens: Int = 100) -> UsageEntry {
        UsageEntry(
            timestamp: date(iso),
            model: model,
            tokens: TokenCounts(input: tokens),
            deduplicationKey: iso
        )
    }

    func testEntriesWithinWindowFormOneBlock() {
        let calc = BlockCalculator()
        let blocks = calc.blocks(from: [
            entry("2026-07-13T15:57:41Z"),
            entry("2026-07-13T17:30:00Z"),
        ])
        XCTAssertEqual(blocks.count, 1)
        // Start floored to the top of the first entry's hour, in UTC.
        XCTAssertEqual(blocks[0].startTime, date("2026-07-13T15:00:00Z"))
        XCTAssertEqual(blocks[0].endTime, date("2026-07-13T20:00:00Z"))
        XCTAssertEqual(blocks[0].entryCount, 2)
    }

    func testGapBeyondWindowStartsNewBlock() {
        let calc = BlockCalculator()
        let blocks = calc.blocks(from: [
            entry("2026-07-13T15:57:41Z"),
            entry("2026-07-13T23:00:00Z"), // >5h after the 15:00 start
        ])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].startTime, date("2026-07-13T23:00:00Z"))
    }

    func testEntryPastNominalEndStartsNewBlockEvenWithoutIdleGap() {
        let calc = BlockCalculator()
        // Steady activity that crosses the 5h boundary should still roll over.
        let blocks = calc.blocks(from: [
            entry("2026-07-13T15:10:00Z"),
            entry("2026-07-13T18:00:00Z"),
            entry("2026-07-13T20:30:00Z"), // 5h20m after 15:00 start → new block
        ])
        XCTAssertEqual(blocks.count, 2)
    }

    func testActiveBlockDetection() {
        let calc = BlockCalculator()
        let entries = [entry("2026-07-13T15:57:41Z")]
        // now inside the window
        XCTAssertNotNil(calc.activeBlock(from: entries, now: date("2026-07-13T18:00:00Z")))
        // now after the window closes
        XCTAssertNil(calc.activeBlock(from: entries, now: date("2026-07-13T21:00:00Z")))
    }

    func testBurnRateIsBillableTokensPerElapsedMinute() {
        let start = date("2026-07-13T15:00:00Z")
        let block = SessionBlock(
            startTime: start,
            endTime: start.addingTimeInterval(5 * 3600),
            lastActivity: start.addingTimeInterval(600),
            tokens: TokenCounts(input: 600), // 600 billable tokens
            entryCount: 1,
            models: ["claude-opus-4-8"]
        )
        // 10 minutes elapsed → 60 tokens/min
        let now = start.addingTimeInterval(600)
        XCTAssertEqual(block.burnRateTokensPerMinute(now: now), 60, accuracy: 1e-6)
    }

    func testEmptyInputProducesNoBlocks() {
        XCTAssertTrue(BlockCalculator().blocks(from: []).isEmpty)
    }
}
