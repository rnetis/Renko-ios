import SwiftUI

/// Candle-interval chips plus a brick-size menu (relative % of price).
struct IntervalRow: View {
    @Binding var interval: String
    @Binding var brickPercent: Double

    private let intervals = MarketSession.intervals
    private let choices = MarketSession.brickPercentChoices

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(intervals, id: \.self) { option in
                        Button {
                            interval = option
                        } label: {
                            Text(option)
                                .font(.system(size: 12,
                                              weight: interval == option ? .bold : .regular,
                                              design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundColor(interval == option ? Theme.accent : Theme.secondary)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(interval == option ? Theme.accent.opacity(0.15) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(interval == option ? Theme.accent.opacity(0.6) : Theme.grid,
                                                      lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 8)
            brickSizeMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func percentLabel(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private var brickSizeMenu: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button {
                    brickPercent = choice
                } label: {
                    if choice == brickPercent {
                        Label(percentLabel(choice), systemImage: "checkmark")
                    } else {
                        Text(percentLabel(choice))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.split.2x2")
                Text(percentLabel(brickPercent))
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(Theme.accent)
            .background(Theme.accent.opacity(0.12))
            .cornerRadius(6)
        }
    }
}
