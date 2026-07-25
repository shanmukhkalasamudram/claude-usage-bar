import ClaudeUsageKit
import Foundation
import SwiftUI

/// What one refresh attempt told us, used to drive the timer loop's backoff.
enum RefreshOutcome: Equatable {
    /// Fetched fresh limits — return to the steady interval.
    case success
    /// HTTP 429; `retryAfter` is the server-requested wait in seconds, if any.
    case rateLimited(retryAfter: TimeInterval?)
    /// Network failure or an unexpected HTTP status — retry with mild backoff.
    case transient
    /// Token/config problem that a retry won't fix soon (noToken, unauthorized,
    /// forbidden, malformed, untrustedHost) — just keep the steady interval.
    case fatal
    /// The attempt was skipped: a refresh was already in flight (e.g. the
    /// popover's on-open refresh raced the loop) or the task was cancelled. The
    /// loop MUST leave its backoff state untouched so a concurrent manual
    /// refresh can't reset an in-progress 429 backoff.
    case skipped
}

/// Owns the current ``UsageLimits`` and refreshes them from Anthropic's usage
/// endpoint on a timer, backing off when the endpoint rate-limits us and
/// keeping the last-known numbers on screen through transient failures.
@MainActor
final class LimitsViewModel: ObservableObject {
    @Published private(set) var limits: UsageLimits?
    @Published private(set) var isRefreshing = false
    /// Message from the most recent *failed* fetch, or `nil` if the last fetch
    /// succeeded. Non-nil does NOT imply the numbers are gone — see `isStale`.
    @Published private(set) var errorMessage: String?
    /// Time of the last *successful* fetch. Left untouched on failure so the
    /// popover can show how old the last-known numbers are.
    @Published private(set) var lastRefreshed: Date?

    /// We have previously-loaded numbers on screen, but the most recent refresh
    /// failed — what's shown is last-known, not current. Drives the subtle
    /// "couldn't refresh" cue rather than a full error takeover.
    var isStale: Bool { limits != nil && errorMessage != nil }

    /// We have never successfully loaded anything and the last attempt failed —
    /// the error is allowed to take over the whole popover.
    var showsErrorTakeover: Bool { limits == nil && errorMessage != nil }

    /// The steady interval between refreshes when everything is healthy.
    let refreshInterval: TimeInterval

    private let client: LimitsClient
    private var refreshTask: Task<Void, Never>?

    // The usage endpoint is a free metadata call — it does not consume tokens
    // or count against any limit — so refreshing costs nothing. Once a minute
    // keeps the numbers fresh; the reset countdowns tick locally every second
    // in between.
    init(client: LimitsClient = LimitsClient(), refreshInterval: TimeInterval = 60) {
        self.client = client
        self.refreshInterval = refreshInterval
    }

    /// Begin the periodic refresh loop. Safe to call more than once.
    ///
    /// Backoff state lives on the task's stack, so it's isolated to this single
    /// loop and resets whenever the loop is (re)started. `self` is only touched
    /// inside `guard let self` blocks that finish before each sleep, so the view
    /// model isn't retained during the wait.
    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            let baseInterval: TimeInterval
            do {
                guard let self else { return }
                baseInterval = self.refreshInterval
            }
            let maxBackoff: TimeInterval = 900   // 15-minute ceiling.
            var backoff = baseInterval           // current backoff floor.

            while !Task.isCancelled {
                // Hold `self` only for the fetch, then release it before the
                // sleep so the view model isn't retained for the whole interval.
                let outcome: RefreshOutcome
                do {
                    guard let self else { return }
                    outcome = await self.refresh()
                }

                let delay: TimeInterval
                switch outcome {
                case .success:
                    backoff = baseInterval
                    delay = baseInterval

                case .rateLimited(let retryAfter):
                    // Grow the floor (60→120→240→480→900), then wait at least as
                    // long as the server asked. Jitter so leftover instances or
                    // multiple users don't resynchronise into a thundering herd.
                    backoff = min(maxBackoff, max(backoff * 2, baseInterval * 2))
                    delay = Self.jittered(max(backoff, retryAfter ?? 0))

                case .transient:
                    // Milder backoff for connectivity / unexpected-status blips,
                    // capped lower than the 429 ceiling.
                    backoff = min(maxBackoff, max(backoff * 2, baseInterval * 2))
                    delay = Self.jittered(min(backoff, 300))

                case .fatal:
                    // Resolves out of band (e.g. next Claude Code use refreshes
                    // the token); no point hammering, no point backing off hard.
                    delay = baseInterval

                case .skipped:
                    // Another refresh was already in flight (or the task is being
                    // cancelled). Do NOT touch `backoff` — otherwise a concurrent
                    // popover/manual refresh could reset an active 429 backoff.
                    delay = Self.jittered(backoff)
                }

                DiagnosticLog.log("next poll in \(Int(delay))s")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Apply ±15% jitter so leftover instances / multiple users don't resync.
    private static func jittered(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds > 0 else { return 0 }
        let jitter = seconds * 0.15
        return max(0, seconds + Double.random(in: -jitter...jitter))
    }

    /// Fetch the latest limits now. On failure the previously loaded limits and
    /// their `lastRefreshed` timestamp are intentionally preserved so a
    /// transient error (429, network blip) can't wipe the displayed numbers;
    /// only `errorMessage` updates, which drives the stale cue. Returns what
    /// happened so the loop can back off.
    @discardableResult
    func refresh() async -> RefreshOutcome {
        guard !isRefreshing else { return .skipped }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let limits = try await client.fetch()
            self.limits = limits
            self.errorMessage = nil
            self.lastRefreshed = limits.fetchedAt
            DiagnosticLog.log("fetch OK — session \(Int(limits.session.utilization))% week \(Int(limits.week.utilization))%")
            return .success
        } catch is CancellationError {
            // Explicit Swift cancellation — not a real failure. Leave state as-is.
            return .skipped
        } catch {
            // A cancelled task (app quitting, popover closed mid-fetch, loop
            // stopped) reaches us as LimitsError.network, because the client maps
            // URLSession's URLError(.cancelled) before we ever see a Swift
            // CancellationError. So decide on the task's OWN cancellation flag,
            // not the error type: a cancelled task was abandoned deliberately —
            // don't poison the UI. Otherwise record the failure but keep the
            // last-known limits + timestamp so the popover shows stale data.
            if Task.isCancelled { return .skipped }
            DiagnosticLog.log("fetch FAIL — \(Self.logDescription(for: error))")
            self.errorMessage = Self.message(for: error)
            return Self.outcome(for: error)
        }
    }

    /// A short, credential-free description of a fetch failure for the log.
    private static func logDescription(for error: Error) -> String {
        switch error {
        case LimitsClient.LimitsError.rateLimited(let retryAfter):
            return "429 rate-limited (retry-after=\(retryAfter.map { "\(Int($0))s" } ?? "none"))"
        case LimitsClient.LimitsError.unauthorized: return "401 unauthorized"
        case LimitsClient.LimitsError.forbidden: return "403 forbidden"
        case LimitsClient.LimitsError.network: return "network error"
        case LimitsClient.LimitsError.http(let code): return "HTTP \(code)"
        case LimitsClient.LimitsError.noToken: return "no token in keychain"
        case LimitsClient.LimitsError.untrustedHost: return "untrusted host"
        case LimitsClient.LimitsError.malformed: return "malformed response"
        default: return "unknown error"
        }
    }

    /// Classify an error for backoff purposes.
    private static func outcome(for error: Error) -> RefreshOutcome {
        switch error {
        case LimitsClient.LimitsError.rateLimited(let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case LimitsClient.LimitsError.network, LimitsClient.LimitsError.http:
            return .transient
        default:
            return .fatal
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LimitsClient.LimitsError.noToken:
            return "No Claude login found. Sign in with Claude Code, then reopen."
        case LimitsClient.LimitsError.unauthorized:
            return "Claude Code login expired. Use Claude Code once and it refreshes automatically."
        case LimitsClient.LimitsError.forbidden:
            return "This account can't read usage limits — an active Claude Pro or Max plan is required."
        case LimitsClient.LimitsError.rateLimited:
            return "Rate limited — backing off and retrying automatically."
        case LimitsClient.LimitsError.network:
            return "Couldn't reach Anthropic. Check your connection."
        case LimitsClient.LimitsError.http(let code):
            return "Anthropic returned HTTP \(code). Try again shortly."
        case LimitsClient.LimitsError.malformed:
            return "Couldn't read the usage response."
        default:
            return "Something went wrong. Try again shortly."
        }
    }
}
