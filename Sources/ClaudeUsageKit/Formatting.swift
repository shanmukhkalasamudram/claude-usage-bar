import Foundation

/// Presentation helpers shared by the menu bar app and the CLI so both render
/// numbers the same way.
public enum Formatting {
    /// Compact token counts: `812` → "812", `96_865` → "96.9K",
    /// `21_793_040` → "21.8M".
    public static func tokens(_ value: Int) -> String {
        let v = Double(value)
        switch abs(value) {
        case 1_000_000...:
            return trim(v / 1_000_000) + "M"
        case 1_000...:
            return trim(v / 1_000) + "K"
        default:
            return "\(value)"
        }
    }

    /// A whole-number percentage like "45%".
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// A short countdown like "4h 51m" or "12m" or "0m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// A longer countdown that rolls up into days: "3d 4h", "6h", "12m".
    public static func durationLong(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// The same countdown without a space, for the tight menu bar title: "4h51m".
    public static func durationCompact(_ seconds: TimeInterval) -> String {
        duration(seconds).replacingOccurrences(of: " ", with: "")
    }

    /// A clock time like "8:00 PM" in the user's locale/timezone.
    public static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private static func trim(_ value: Double) -> String {
        // One decimal place, but drop a trailing ".0".
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
