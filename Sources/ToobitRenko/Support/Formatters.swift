import Foundation

enum Format {
    /// Number of decimals implied by a tick size, e.g. `0.1` → 1, `0.001` → 3.
    static func decimals(forTick tick: Double) -> Int {
        guard tick > 0, tick.isFinite else { return 2 }
        var value = tick
        var places = 0
        while places < 8 {
            if abs(value - value.rounded()) < 1e-7 { return places }
            value *= 10
            places += 1
        }
        return places
    }

    static func price(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// Price-like value with enough digits to stay meaningful for micro-caps
    /// (e.g. a 0.5 % brick of a $0.0123 coin is 0.0000615, not "0").
    static func adaptive(_ value: Double) -> String {
        let magnitude = abs(value)
        guard magnitude.isFinite, magnitude > 0 else { return "0" }
        if magnitude >= 1000 { return String(format: "%.0f", value) }
        if magnitude >= 1 { return String(format: "%.2f", value) }
        let digits = min(8, max(2, Int(ceil(-log10(magnitude))) + 2))
        return String(format: "%.\(digits)f", value)
    }

    /// Signed percentage string, e.g. `+1.23 %`.
    static func signed(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", sign, fraction * 100)
    }

    /// Human-readable volume, e.g. `351.52M`.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000_000...:
            return String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.2fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", value / 1_000)
        default:
            return String(format: "%.0f", value)
        }
    }

    private static let hourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayHourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private static let exactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()

    /// Full timestamp (down to the second) for the chart's brick readout.
    static func exact(_ date: Date) -> String {
        exactFormatter.string(from: date)
    }

    /// Picks a compact time format based on the visible time span.
    static func axisTime(_ date: Date, span: TimeInterval) -> String {
        switch span {
        case ..<7200:
            return hourMinute.string(from: date)
        case ..<172_800:
            return dayHourMinute.string(from: date)
        default:
            return day.string(from: date)
        }
    }
}
