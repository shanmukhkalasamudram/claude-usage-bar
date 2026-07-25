import AppKit
import ClaudeUsageKit

/// Ensures only one ClaudeUsageBar process runs at a time.
///
/// The app is distributed unsigned (ad-hoc `codesign -s -`) and may be launched
/// repeatedly by an impatient user — e.g. while fighting a Keychain prompt — or
/// run "translocated" from a randomized read-only path by Gatekeeper. Every live
/// copy independently polls `oauth/usage` once a minute, and stacking several of
/// them is exactly what pushed the endpoint to HTTP 429. This guard collapses
/// duplicates down to one before any of them starts polling.
///
/// Matching is by **bundle identifier**, never by path: `NSRunningApplication`'s
/// `bundleIdentifier` is read from the bundle's Info.plist and is identical for a
/// translocated copy and an `/Applications` copy, whereas their `bundleURL`s
/// differ. So comparing identifiers is what makes translocation a non-issue.
@MainActor
enum SingleInstanceGuard {
    /// The app's bundle identifier (matches `CFBundleIdentifier` in the packaged
    /// Info.plist produced by scripts/build-app.sh — "com.claudeusagebar.app").
    /// Falls back to that literal so the guard still works if the process is
    /// launched in an unusual way where `Bundle.main.bundleIdentifier` is nil.
    static let bundleID: String =
        Bundle.main.bundleIdentifier ?? "com.claudeusagebar.app"

    /// Call once, as early as possible in `applicationDidFinishLaunching`.
    ///
    /// If this instance is not the elected survivor, it terminates the current
    /// process (via `exit(0)`) and never returns.
    static func enforce() {
        // `runningApplications(withBundleIdentifier:)` returns *every* live
        // process carrying this bundle id — importantly, that set INCLUDES the
        // current process. LaunchServices registration can lag a hair behind
        // exec, so we also insert our own pid explicitly to be safe.
        let myPID = ProcessInfo.processInfo.processIdentifier

        var pids = Set(
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .filter { !$0.isTerminated }
                .map { $0.processIdentifier }
        )
        pids.insert(myPID)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        DiagnosticLog.log("launch v\(version) pid=\(myPID) liveInstances=\(pids.count) pids=\(pids.sorted())")

        // We're the only live copy — nothing to do.
        guard pids.count > 1 else {
            DiagnosticLog.log("single instance — running")
            return
        }

        // Deterministic, OBSERVER-INDEPENDENT total order: the lowest pid wins.
        //
        // pids are global identifiers — every process sees the exact same set of
        // pids from every vantage point, so all racers compute the SAME survivor.
        // That guarantees exactly one survivor: no zero-survivor outcome and no
        // double-survivor outcome. (We deliberately do NOT use `launchDate` as
        // the key: `NSRunningApplication.current.launchDate` can be nil for the
        // self-view while peers observe a populated date for the same process,
        // and its resolution is too coarse — that asymmetry can make two racers
        // each conclude they are "later" and both exit, leaving zero survivors.)
        //
        // Under normal monotonic pid allocation the earliest-launched copy has
        // the lowest pid, so this also keeps the already-running instance and
        // exits the freshly-launched duplicate — the intended UX.
        let survivorPID = pids.min()!  // safe: count > 1
        if myPID != survivorPID {
            DiagnosticLog.log("duplicate instance — exiting (survivor pid=\(survivorPID))")
            // We lost. Exit immediately — we're still inside didFinishLaunching,
            // so the menu bar item hasn't painted and the refresh loop (started
            // by MenuBarLabel's .task) hasn't run. No Keychain handle is held,
            // no URLSession exists yet, so there is nothing to tear down;
            // `exit(0)` avoids a flashed icon.
            exit(0)
        }
        // else: we are the survivor — fall through and run normally.
        DiagnosticLog.log("surviving instance — running (collapsed \(pids.count) copies)")
    }
}
