import SwiftUI

/// Top bar: contract name, live price, 24h change and a connection pill.
struct TickerBar: View {
    let displayName: String
    let ticker: TickerSnapshot?
    let status: StreamStatus
    let decimals: Int

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    if let t = ticker {
                        Text("24h Vol \(Format.compact(t.quoteVolume))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let t = ticker {
                        Text(Format.price(t.lastPrice, decimals: decimals))
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(t.change24h >= 0 ? Theme.up : Theme.down)
                        Text(Format.signed(t.change24h))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(t.change24h >= 0 ? Theme.up : Theme.down)
                    } else {
                        Text("—")
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.secondary)
                        Text("waiting…")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.secondary)
                    }
                }
            }
            HStack(spacing: 14) {
                statusBadge
                if let t = ticker {
                    keyValue("24h High", Format.price(t.high24h, decimals: decimals))
                    keyValue("24h Low", Format.price(t.low24h, decimals: decimals))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.surface))
    }

    private var statusColor: Color {
        switch status {
        case .connected: return Theme.up
        case .connecting, .reconnecting: return Theme.accent
        case .idle: return Theme.secondary
        }
    }

    private var statusText: String {
        switch status {
        case .idle: return "IDLE"
        case .connecting: return "CONNECTING"
        case .connected: return "LIVE"
        case .reconnecting(let attempt, _): return "RETRY #\(attempt)"
        }
    }
}

private struct KeyValueLabel: View {
    let key: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.text)
        }
    }
}

private func keyValue(_ key: String, _ value: String) -> some View {
    KeyValueLabel(key: key, value: value)
}
