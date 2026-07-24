import XCTest
@testable import ClaudeUsageKit

final class FormattingTests: XCTestCase {
    func testTokenFormatting() {
        XCTAssertEqual(Formatting.tokens(812), "812")
        XCTAssertEqual(Formatting.tokens(96_865), "96.9K")
        XCTAssertEqual(Formatting.tokens(1_000), "1K")
        XCTAssertEqual(Formatting.tokens(21_793_040), "21.8M")
        XCTAssertEqual(Formatting.tokens(0), "0")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Formatting.duration(4 * 3600 + 51 * 60), "4h 51m")
        XCTAssertEqual(Formatting.duration(12 * 60), "12m")
        XCTAssertEqual(Formatting.duration(0), "0m")
        XCTAssertEqual(Formatting.durationCompact(4 * 3600 + 51 * 60), "4h51m")
    }
}
