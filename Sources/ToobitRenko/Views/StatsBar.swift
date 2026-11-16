import SwiftUI

/// Bottom strip with session Renko statistics.
struct StatsBar: View {
    let bricks: [RenkoBrick]
    let brickPercent: Double
    let decimals: Int

    private var upCount: Int { bricks.filter(\.isUp).count }
    private var downCount: Int { bricks.count - upCount }

    /// Consecutive same-direction bricks at the tail of the series.
    private var streak: (count: Int, isUp: Bool)? {
        guard let last = bricks.last else { return nil }
        var count = 0
        for brick in bricks.reversed() {
            if brick.isUp == last.isUp { count += 1 } else { break }
        }
        return (count, last.isUp)
    }

    /// Approximate absolute value of one brick at the latest price.
    private var brickValue: String {
        let reference = bricks.last?.close ?? bricks.last?.open ?? 0
        return Format.compact(reference * brickPercent)
    }

    var body: some View {
        HStack(spacing: 14) {
            stat("Bricks", "\(bricks.count)", color: Theme.text)
            stat("Up", "\(upCount)", color: Theme.up)
            stat("Down", "\(downCount)", color: Theme.down)
            if let streak {
                stat("Streak", "\(streak.count)\(streak.isUp ? "↑" : "↓")",
                     color: streak.isUp ? Theme.up : Theme.down)
            }
            Spacer()
            stat("Size", String(format: "%.2f%% ≈ %@ USDT", brickPercent * 100, brickValue),
                 color: Theme.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stat(_ key: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
