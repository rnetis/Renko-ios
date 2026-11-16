import SwiftUI

/// Bottom strip with session Renko statistics and the EMA-based bias read.
struct StatsBar: View {
    let analysis: RenkoAnalysis
    let brickPercent: Double
    /// Latest price, used to express one brick in USDT.
    let referencePrice: Double?

    /// Approximate absolute value of one brick at the latest price.
    private var brickValue: String {
        guard let referencePrice else { return "—" }
        return Format.adaptive(referencePrice * brickPercent)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                stat("Bricks", "\(analysis.count)", color: Theme.text)
                stat("Up", "\(analysis.upCount)", color: Theme.up)
                stat("Down", "\(analysis.downCount)", color: Theme.down)
                if let isUp = analysis.lastIsUp {
                    stat("Streak", "\(analysis.streak)\(isUp ? "↑" : "↓")",
                         color: isUp ? Theme.up : Theme.down)
                }
                Spacer()
                stat("Size", String(format: "%.2f%% ≈ %@ USDT", brickPercent * 100, brickValue),
                     color: Theme.secondary)
            }
            HStack(spacing: 10) {
                biasPill
                stat("Chop", String(format: "%.0f%%", analysis.chop * 100), color: chopColor)
                Spacer()
                Text("EMA \(RenkoAnalysis.fastPeriod)/\(RenkoAnalysis.slowPeriod) on brick closes")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var biasColor: Color {
        switch analysis.bias {
        case .long: return Theme.up
        case .short: return Theme.down
        case .wait: return Theme.secondary
        }
    }

    private var chopColor: Color {
        analysis.chop > RenkoAnalysis.chopLimit ? Theme.accent : Theme.secondary
    }

    private var biasPill: some View {
        HStack(spacing: 5) {
            Text("Bias")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.secondary)
            Text(analysis.bias.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(biasColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(biasColor.opacity(0.15)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Renko bias \(analysis.bias.rawValue)")
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
