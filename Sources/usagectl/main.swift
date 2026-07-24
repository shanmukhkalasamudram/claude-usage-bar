import ClaudeUsageKit
import Foundation

// A tiny headless interface over ClaudeUsageKit.
//
//   usagectl              Show current session + weekly limits (from Anthropic).
//   usagectl --json       Emit the limits as JSON.
//   usagectl --tokens     Show token usage computed from local transcripts.
//   usagectl --help       Usage.

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print(
        """
        usagectl — Claude usage at a glance

        USAGE:
          usagectl            Current session + weekly limit % (from Anthropic)
          usagectl --json     Emit the limits as JSON
          usagectl --tokens   Token usage computed from local transcripts
          usagectl --help     Show this help

        Limits use the Claude Code OAuth token from your Keychain.
        """
    )
    exit(0)
}

if arguments.contains("--tokens") {
    TokenReport.run(json: arguments.contains("--json"))
} else {
    LimitsReport.run(json: arguments.contains("--json"))
}

// MARK: - Limits report (default)

/// A minimal box for smuggling an async result across the semaphore barrier.
private final class Box<T>: @unchecked Sendable {
    var value: T?
}

enum LimitsReport {
    static func run(json: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = Box<Result<UsageLimits, Error>>()
        Task {
            do { box.value = .success(try await LimitsClient().fetch()) }
            catch { box.value = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()

        switch box.value! {
        case .failure(let error):
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        case .success(let limits):
            print(json ? jsonString(limits) : text(limits))
        }
    }

    static func text(_ limits: UsageLimits) -> String {
        var lines: [String] = []
        func block(_ title: String, _ window: LimitWindow) {
            lines.append(title)
            lines.append("  Used        \(Formatting.percent(window.utilization))")
            lines.append("  Resets in   \(Formatting.durationLong(window.timeRemaining(now: limits.fetchedAt)))  (at \(Formatting.clock(window.resetsAt)))")
            lines.append("")
        }
        block("Current session (5h)", limits.session)
        block("This week (7d)", limits.week)
        if let opus = limits.weekOpus { block("This week · Opus (7d)", opus) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func jsonString(_ limits: UsageLimits) -> String {
        func window(_ w: LimitWindow) -> [String: Any] {
            [
                "utilizationPercent": w.utilization,
                "resetsAt": ISO8601DateFormatter().string(from: w.resetsAt),
                "resetsInSeconds": Int(w.timeRemaining(now: limits.fetchedAt)),
            ]
        }
        var payload: [String: Any] = [
            "session": window(limits.session),
            "week": window(limits.week),
        ]
        if let opus = limits.weekOpus { payload["weekOpus"] = window(opus) }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}

// MARK: - Token report (--tokens)

enum TokenReport {
    static func run(json: Bool) {
        let snapshot = UsageService.makeDefault().snapshot()
        if json {
            print(jsonString(snapshot))
        } else {
            print(text(snapshot))
        }
    }

    static func text(_ snapshot: UsageSnapshot) -> String {
        var lines: [String] = []
        if let block = snapshot.activeBlock {
            lines.append("Current 5-hour window")
            lines.append("  Resets in     \(Formatting.duration(block.timeRemaining(now: snapshot.generatedAt)))  (at \(Formatting.clock(block.endTime)))")
            lines.append("  Tokens        \(Formatting.tokens(block.tokens.total))")
            lines.append("  Burn rate     \(Formatting.tokens(Int(block.burnRateTokensPerMinute(now: snapshot.generatedAt))))/min")
        } else {
            lines.append("Current 5-hour window: idle")
        }
        lines.append("")
        lines.append("Today         \(Formatting.tokens(snapshot.today.tokens.total)) tokens")
        lines.append("This month    \(Formatting.tokens(snapshot.month.tokens.total)) tokens")
        return lines.joined(separator: "\n")
    }

    static func jsonString(_ snapshot: UsageSnapshot) -> String {
        var block: [String: Any] = ["active": false]
        if let b = snapshot.activeBlock {
            block = [
                "active": true,
                "resetsInSeconds": Int(b.timeRemaining(now: snapshot.generatedAt)),
                "tokens": b.tokens.total,
            ]
        }
        let payload: [String: Any] = [
            "block": block,
            "today": ["tokens": snapshot.today.tokens.total],
            "month": ["tokens": snapshot.month.tokens.total],
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
