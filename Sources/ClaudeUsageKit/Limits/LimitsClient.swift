import Foundation

/// Fetches subscription usage limits from Anthropic's OAuth usage endpoint —
/// the same data Claude's `/usage` shows.
///
/// Security & privacy posture (this is a public, open-source app):
/// - The **only** network destination is `api.anthropic.com`. The endpoint host
///   is verified before every request.
/// - The bearer token is read from the Keychain per request, sent only to that
///   host, and never logged, persisted, or included in error values.
/// - HTTP redirects are refused, so the `Authorization` header can never be
///   replayed to a different host.
/// - An ephemeral URL session is used: no on-disk cache, no cookies, no
///   credential storage. Nothing about the request or response is written to
///   disk by this client.
public struct LimitsClient: Sendable {
    public enum LimitsError: Error, Equatable {
        /// No Claude Code token found in the Keychain (is Claude Code logged in?).
        case noToken
        /// The configured endpoint is not an approved Anthropic host.
        case untrustedHost
        /// Token was rejected as expired/invalid (HTTP 401) — Claude Code
        /// refreshes it on next use.
        case unauthorized
        /// The token is valid but not allowed to read usage limits (HTTP 403) —
        /// e.g. no active Claude subscription on this account.
        case forbidden
        /// The request could not reach Anthropic (offline, DNS, timeout).
        case network
        /// Rate limited by Anthropic (HTTP 429). `retryAfter` is the number of
        /// seconds the server asked us to wait, parsed from the `Retry-After`
        /// header per RFC 7231 (delta-seconds or IMF-fixdate HTTP-date), or nil
        /// if the header is absent or unparseable.
        case rateLimited(retryAfter: TimeInterval?)
        /// Non-200 HTTP status (other than the ones handled explicitly).
        case http(Int)
        /// The response could not be decoded into limits.
        case malformed
    }

    /// Hosts this client is permitted to contact. Anything else is refused
    /// before a request is made, so a token can never be sent elsewhere.
    static let allowedHosts: Set<String> = ["api.anthropic.com"]

    private let endpoint: URL
    private let tokenProvider: @Sendable () -> String?
    private let timeout: TimeInterval

    public init(
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        tokenProvider: @escaping @Sendable () -> String? = KeychainTokenReader.claudeCodeAccessToken,
        timeout: TimeInterval = 15
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.timeout = timeout
    }

    /// Fetch the current limits.
    public func fetch(now: Date = Date()) async throws -> UsageLimits {
        guard endpoint.scheme == "https",
              let host = endpoint.host,
              Self.allowedHosts.contains(host)
        else {
            throw LimitsError.untrustedHost
        }
        guard let token = tokenProvider() else { throw LimitsError.noToken }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout

        // A fresh, ephemeral, redirect-refusing session per call: no disk cache,
        // no cookies, no cross-host redirects, nothing retained between fetches.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 5
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Surface a connection failure without leaking the token or request.
            throw LimitsError.network
        }

        guard let http = response as? HTTPURLResponse else { throw LimitsError.malformed }
        switch http.statusCode {
        case 200: break
        case 401: throw LimitsError.unauthorized
        case 403: throw LimitsError.forbidden
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Self.parseRetryAfter($0, now: now) }
            throw LimitsError.rateLimited(retryAfter: retryAfter)
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
            let utilization = number(dict["utilization"]),
            let resetString = dict["resets_at"] as? String,
            let resetsAt = parseDate(resetString)
        else {
            return nil
        }
        return LimitWindow(utilization: utilization, resetsAt: resetsAt)
    }

    /// Coerce a JSON value to a `Double`, rejecting JSON booleans (which also
    /// bridge to `NSNumber`, so `true` would otherwise become `1.0`).
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {
            return nil
        }
        return n.doubleValue
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

    // RFC 7231 §7.1.3 Retry-After is either delta-seconds (a non-negative
    // integer) or an HTTP-date. HTTP-date is sent as IMF-fixdate, e.g.
    // "Sun, 06 Nov 1994 08:49:37 GMT". Parse with a fixed POSIX/GMT formatter so
    // the device locale, 12/24h setting, or time zone can never skew it.
    private static let imfFixdate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    /// Parse a `Retry-After` header value into a non-negative wait in seconds,
    /// relative to `now`. Returns nil if the value is malformed.
    static func parseRetryAfter(_ raw: String, now: Date) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // delta-seconds form: a bare non-negative integer count of seconds.
        if let seconds = Int(trimmed), seconds >= 0 {
            return TimeInterval(seconds)
        }
        // HTTP-date (IMF-fixdate) form: seconds from now until that instant.
        if let date = imfFixdate.date(from: trimmed) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }
}

/// Refuses every HTTP redirect, so the `Authorization` header is only ever sent
/// to the original, host-verified URL and can't be replayed elsewhere.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
