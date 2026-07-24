import XCTest
@testable import ClaudeUsageKit

final class LimitsClientTests: XCTestCase {
    private let sample = Data("""
    {
      "five_hour":  { "utilization": 45.0, "resets_at": "2026-07-24T06:59:59.252451+00:00" },
      "seven_day":  { "utilization": 25.0, "resets_at": "2026-07-27T11:59:59.252473+00:00" },
      "seven_day_opus": { "utilization": 12.5, "resets_at": "2026-07-27T11:59:59Z" },
      "extra_usage": null
    }
    """.utf8)

    func testDecodeParsesAllWindows() throws {
        let limits = try LimitsClient.decode(sample, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(limits.session.utilization, 45.0, accuracy: 1e-9)
        XCTAssertEqual(limits.week.utilization, 25.0, accuracy: 1e-9)
        XCTAssertEqual(limits.weekOpus?.utilization, 12.5)
        XCTAssertEqual(limits.session.fraction, 0.45, accuracy: 1e-9)
    }

    func testDecodeRejectsBooleanUtilization() {
        // A JSON boolean bridges to NSNumber; it must not be read as 0/1.
        let bad = Data(#"{ "five_hour": { "utilization": true, "resets_at": "2026-07-24T00:00:00Z" }, "seven_day": { "utilization": 5, "resets_at": "2026-07-27T00:00:00Z" } }"#.utf8)
        XCTAssertThrowsError(try LimitsClient.decode(bad, now: Date())) { error in
            XCTAssertEqual(error as? LimitsClient.LimitsError, .malformed)
        }
    }

    func testDecodeMissingRequiredWindowThrows() {
        let bad = Data(#"{ "seven_day": { "utilization": 1, "resets_at": "2026-07-27T00:00:00Z" } }"#.utf8)
        XCTAssertThrowsError(try LimitsClient.decode(bad, now: Date())) { error in
            XCTAssertEqual(error as? LimitsClient.LimitsError, .malformed)
        }
    }

    /// Reference box so the `@Sendable` token provider can record a call
    /// without capturing a mutable local (illegal under Swift 6 concurrency).
    private final class CallFlag: @unchecked Sendable {
        var wasCalled = false
    }

    func testFetchRefusesNonAnthropicHostBeforeAnyNetwork() async {
        // A non-approved host must be rejected without a token read or a request.
        let flag = CallFlag()
        let client = LimitsClient(
            endpoint: URL(string: "https://evil.example.com/api/oauth/usage")!,
            tokenProvider: { flag.wasCalled = true; return "secret" }
        )
        do {
            _ = try await client.fetch()
            XCTFail("expected untrustedHost")
        } catch {
            XCTAssertEqual(error as? LimitsClient.LimitsError, .untrustedHost)
        }
        XCTAssertFalse(flag.wasCalled, "token must not be read for an untrusted host")
    }

    func testFetchWithoutTokenThrowsNoTokenAndMakesNoRequest() async {
        let client = LimitsClient(tokenProvider: { nil }) // default (trusted) endpoint
        do {
            _ = try await client.fetch()
            XCTFail("expected noToken")
        } catch {
            XCTAssertEqual(error as? LimitsClient.LimitsError, .noToken)
        }
    }

    func testTimestampParsingHandlesFractionalOffsetAndZulu() {
        XCTAssertNotNil(LimitsClient.parseDate("2026-07-24T06:59:59.252451+00:00"))
        XCTAssertNotNil(LimitsClient.parseDate("2026-07-27T11:59:59Z"))
        XCTAssertNil(LimitsClient.parseDate("nope"))
    }
}
