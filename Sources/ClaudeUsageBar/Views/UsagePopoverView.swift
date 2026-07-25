import ClaudeUsageKit
import SwiftUI

/// The panel shown when the menu bar item is clicked: the current session and
/// weekly limits, straight from Anthropic's usage endpoint.
struct UsagePopoverView: View {
    @ObservedObject var model: LimitsViewModel

    /// Claude's warm coral accent.
    static let brand = Color(red: 0.85, green: 0.46, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let limits = model.limits {
                LimitCard(title: "Current session", subtitle: "5-hour limit", window: limits.session, prominent: true)
                LimitCard(title: "This week", subtitle: "7-day limit", window: limits.week, prominent: false)
                if let opus = limits.weekOpus {
                    LimitCard(title: "This week · Opus", subtitle: "7-day limit", window: opus, prominent: false)
                }
            } else if model.showsErrorTakeover, let error = model.errorMessage {
                errorView(error)
            } else {
                loadingView
            }

            footer
        }
        .padding(18)
        .frame(width: 300)
        .task { await model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Self.brand)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Usage").font(.headline)
                subline
            }
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    /// The subtitle line under "Claude Usage". Normally the last-updated time;
    /// when the numbers are stale (a refresh failed but we still have prior
    /// data) it becomes a muted warning that keeps the last-good time visible,
    /// so the user knows how old the numbers are without a full error takeover.
    @ViewBuilder private var subline: some View {
        if model.isStale {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                if let error = model.errorMessage {
                    Text(error)
                }
                if let refreshed = model.lastRefreshed {
                    Text("· from \(Formatting.clock(refreshed))")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let refreshed = model.lastRefreshed {
            Text("Updated \(Formatting.clock(refreshed))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading your limits…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.fileURL])
            } label: {
                Label("Log", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Reveal the diagnostics log in Finder")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

// MARK: - Limit card

/// One limit window rendered as a rounded card: title, a big colored
/// percentage, a thick meter, and a live reset countdown.
private struct LimitCard: View {
    let title: String
    let subtitle: String
    let window: LimitWindow
    let prominent: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatting.percent(window.utilization))
                        .font(.system(prominent ? .title : .title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }

                MeterBar(fraction: window.fraction, color: color)

                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.caption2)
                    Text("Resets in \(Formatting.durationLong(window.timeRemaining(now: context.date)))")
                        .fontWeight(.medium)
                    Text("· \(Formatting.clock(window.resetsAt))")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    /// Green → yellow → orange → red as the limit fills.
    private var color: Color {
        switch window.fraction {
        case ..<0.5: return .green
        case ..<0.75: return .yellow
        case ..<0.9: return .orange
        default: return .red
        }
    }
}

/// A thick, rounded usage meter.
private struct MeterBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                if fraction > 0.001 {
                    Capsule()
                        .fill(color.gradient)
                        // Keep a tiny minimum so a sub-pixel value is still
                        // visible, but show nothing at a true 0%.
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
        }
        .frame(height: 9)
    }
}
