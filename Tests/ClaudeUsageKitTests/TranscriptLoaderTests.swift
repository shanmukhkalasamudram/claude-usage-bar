import XCTest
@testable import ClaudeUsageKit

final class TranscriptLoaderTests: XCTestCase {
    /// The `Fixtures` folder is copied into the test bundle by SwiftPM.
    private func fixturesConfigDirectory() throws -> URL {
        let base = try XCTUnwrap(Bundle.module.resourceURL)
            .appendingPathComponent("Fixtures", isDirectory: true)
        // Loader appends "projects" itself, so hand it the parent.
        return base
    }

    func testLoadsDedupesAndSortsEntries() throws {
        let loader = TranscriptLoader(configDirectory: try fixturesConfigDirectory())
        let entries = loader.load()

        // 3 unique assistant entries (the duplicate msg_A collapses, the
        // user/summary lines are ignored).
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.deduplicationKey), [
            "msg_A:req_A", "msg_C:req_C", "msg_D:req_D",
        ])
        // Sorted ascending by timestamp.
        XCTAssertEqual(entries, entries.sorted { $0.timestamp < $1.timestamp })
    }

    func testParsesTokenAndCacheSplit() throws {
        let loader = TranscriptLoader(configDirectory: try fixturesConfigDirectory())
        let first = try XCTUnwrap(loader.load().first)
        XCTAssertEqual(first.model, "claude-opus-4-8")
        XCTAssertEqual(first.tokens.input, 2)
        XCTAssertEqual(first.tokens.output, 248)
        XCTAssertEqual(first.tokens.cacheRead, 19241)
        XCTAssertEqual(first.tokens.cacheWrite1h, 7216)
        XCTAssertEqual(first.tokens.cacheWrite5m, 0)
    }

    func testModifiedSinceFutureCutoffSkipsEverything() throws {
        let loader = TranscriptLoader(configDirectory: try fixturesConfigDirectory())
        let future = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
        XCTAssertTrue(loader.load(modifiedSince: future).isEmpty)
    }

    func testTimestampParsingHandlesFractionalAndPlainSeconds() {
        XCTAssertNotNil(TranscriptLoader.parseTimestamp("2026-07-13T15:57:41.670Z"))
        XCTAssertNotNil(TranscriptLoader.parseTimestamp("2026-07-13T15:57:41Z"))
        XCTAssertNil(TranscriptLoader.parseTimestamp("not-a-date"))
    }

    func testParseLineIgnoresNonAssistantLines() {
        let userLine = #"{"type":"user","timestamp":"2026-07-13T15:00:00Z","message":{"role":"user"}}"#
        XCTAssertNil(TranscriptLoader.parseLine(userLine))
    }

    func testDeduplicationKeyComposition() {
        XCTAssertEqual(TranscriptLoader.deduplicationKey(messageID: "m", requestID: "r"), "m:r")
        XCTAssertEqual(TranscriptLoader.deduplicationKey(messageID: "m", requestID: nil), "m")
        XCTAssertEqual(TranscriptLoader.deduplicationKey(messageID: nil, requestID: "r"), "r")
        XCTAssertNil(TranscriptLoader.deduplicationKey(messageID: nil, requestID: nil))
    }
}
