import SwiftUI

/// Watchlist scan: the Renko state (bias, streak, chop) of every favourite at
/// the current interval and brick size, so setups can be compared at a glance.
struct ScannerView: View {
    @EnvironmentObject private var session: MarketSession
    @Environment(\.dismiss) private var dismiss

    /// Actionable rows first, then calmest (lowest chop), then by name.
    private var sortedRows: [ScanRow] {
        session.scanRows.sorted { lhs, rhs in
            let l = lhs.analysis, r = rhs.analysis
            if (l.bias != .wait) != (r.bias != .wait) { return l.bias != .wait }
            if l.chop != r.chop { return l.chop < r.chop }
            return lhs.symbol < rhs.symbol
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.favorites.isEmpty {
                    ContentUnavailableView(
                        "No watchlist yet",
                        systemImage: "star",
                        description: Text("Tap the star in the toolbar, or swipe a contract in the picker, to watch up to \(MarketSession.maxFavorites) contracts.")
                    )
                } else if session.scanRows.isEmpty && session.isScanning {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Scanning \(session.favorites.count) contracts…")
                            .font(.footnote)
                            .foregroundColor(Theme.secondary)
                    }
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Watchlist scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await session.refreshScan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(session.isScanning || session.favorites.isEmpty)
                    .accessibilityLabel("Rescan")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if session.scanRows.isEmpty {
                    await session.refreshScan()
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(sortedRows) { row in
                    Button {
                        session.symbol = row.symbol
                        dismiss()
                    } label: {
                        rowView(row)
                    }
                    .listRowBackground(Theme.surface)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let label = session.scanLabel {
                        Text("Scanned with \(label). Pull down to rescan.")
                    }
                    if session.scanFailures > 0 {
                        Text("\(session.scanFailures) contract(s) could not be loaded.")
                    }
                    Text("Descriptive Renko / EMA state — not trading advice.")
                }
                .font(.system(size: 10))
                .foregroundColor(Theme.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await session.refreshScan() }
    }

    private func rowView(_ row: ScanRow) -> some View {
        let a = row.analysis
        let color: Color = {
            switch a.bias {
            case .long: return Theme.up
            case .short: return Theme.down
            case .wait: return Theme.secondary
            }
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.text)
                Text(Format.price(row.price, decimals: session.decimals(for: row.symbol, price: row.price)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(a.bias.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.15)))
                Text("streak \(a.streak)\(a.lastIsUp == true ? "↑" : "↓") · chop \(String(format: "%.0f", a.chop * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
