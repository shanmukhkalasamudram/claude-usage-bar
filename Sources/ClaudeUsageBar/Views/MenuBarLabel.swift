import ClaudeUsageKit
import SwiftUI

/// The compact content shown directly in the macOS menu bar: a gauge icon plus
/// the current session's utilization percentage.
struct MenuBarLabel: View {
    @ObservedObject var model: LimitsViewModel

    var body: some View {
        if let session = model.limits?.session {
            Image(systemName: symbol(for: session.fraction))
            Text(Formatting.percent(session.utilization))
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.0percent")
        }
    }

    /// The gauge fills as the session limit is consumed.
    private func symbol(for fraction: Double) -> String {
        switch fraction {
        case ..<0.5: return "gauge.with.dots.needle.bottom.0percent"
        case ..<0.85: return "gauge.with.dots.needle.bottom.50percent"
        default: return "gauge.with.dots.needle.bottom.100percent"
        }
    }
}
