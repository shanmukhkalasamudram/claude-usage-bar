import ClaudeUsageKit
import Foundation
import SwiftUI

/// Owns the current ``UsageLimits`` and refreshes them from Anthropic's usage
/// endpoint on a timer.
@MainActor
final class LimitsViewModel: ObservableObject {
    @Published private(set) var limits: UsageLimits?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshed: Date?

    /// How often the limits are re-fetched.
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
    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Hold `self` only for the fetch, then release it before the
                // sleep so the view model isn't retained for the whole interval.
                let interval: TimeInterval
                do {
                    guard let self else { return }
                    await self.refresh()
                    interval = self.refreshInterval
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Fetch the latest limits now.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let limits = try await client.fetch()
            self.limits = limits
            self.errorMessage = nil
            self.lastRefreshed = limits.fetchedAt
        } catch {
            self.errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LimitsClient.LimitsError.noToken:
            return "No Claude login found. Sign in with Claude Code, then reopen."
        case LimitsClient.LimitsError.unauthorized:
            return "Login expired. Run any Claude Code command to refresh it."
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
