import Foundation

/// Fetches subscription usage limits from Anthropic's OAuth usage endpoint —
/// the same data Claude's `/usage` shows.
public struct LimitsClient: Sendable {
    public enum LimitsError: Error, Equatable {
        /// No Claude Code token found in the Keychain (is Claude Code logged in?).
        case noToken
        /// Token was rejected (likely expired — use Claude Code to refresh it).
        case unauthorized
        /// Non-200 HTTP status.
        case http(Int)
        /// The response could not be decoded into limits.
        case malformed
    }

    private let endpoint: URL
    private let tokenProvider: @Sendable () -> String?
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        tokenProvider: @escaping @Sendable () -> String? = KeychainTokenReader.claudeCodeAccessToken,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Fetch the current limits.
    public func fetch(now: Date = Date()) async throws -> UsageLimits {
        guard let token = tokenProvider() else { throw LimitsError.noToken }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LimitsError.malformed }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw LimitsError.unauthorized
        default: throw LimitsError.http(http.statusCode)
        }

        return try Self.decode(data, now: now)
    }

    /// Parse the endpoint payload into ``UsageLimits``.
    static func decode(_ data: Data, now: Date) throws -> UsageLimits {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let session = window(root["five_hour"]),
            let week = window(root["seven_day"])
        else {
            throw LimitsError.malformed
        }
        return UsageLimits(
            session: session,
            week: week,
            weekOpus: window(root["seven_day_opus"]),
            fetchedAt: now
        )
    }

    /// Decode one `{ utilization, resets_at }` window; `nil` if absent/null.
    private static func window(_ value: Any?) -> LimitWindow? {
        guard
            let dict = value as? [String: Any],
            let utilization = (dict["utilization"] as? NSNumber)?.doubleValue,
            let resetString = dict["resets_at"] as? String,
            let resetsAt = parseDate(resetString)
        else {
            return nil
        }
        return LimitWindow(utilization: utilization, resetsAt: resetsAt)
    }

    // Reset timestamps look like "2026-07-24T06:59:59.252451+00:00".
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ raw: String) -> Date? {
        fractional.date(from: raw) ?? plain.date(from: raw)
    }
}
