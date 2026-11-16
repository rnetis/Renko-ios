import SwiftUI

/// Composes the whole screen: ticker bar, interval row, chart, stats bar.
struct RootView: View {
    @EnvironmentObject private var session: MarketSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSymbolPicker = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TickerBar(
                    displayName: session.displayName,
                    ticker: session.ticker,
                    status: session.status,
                    decimals: session.decimals
                )
                Rectangle().fill(Theme.grid).frame(height: 0.5)
                IntervalRow(
                    interval: $session.interval,
                    brickPercent: $session.brickPercent
                )
                chartArea
                Rectangle().fill(Theme.grid).frame(height: 0.5)
                StatsBar(
                    analysis: session.analysis,
                    brickPercent: session.brickPercent,
                    referencePrice: session.ticker?.lastPrice ?? session.bricks.last?.close
                )
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(Theme.accent)
                    }
                    .accessibilityLabel("Watchlist scan")

                    Button {
                        session.toggleFavorite(session.symbol)
                    } label: {
                        Image(systemName: session.isFavorite(session.symbol) ? "star.fill" : "star")
                            .foregroundColor(Theme.accent)
                    }
                    .accessibilityLabel(session.isFavorite(session.symbol)
                                        ? "Remove from watchlist"
                                        : "Add to watchlist")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        session.soundOn.toggle()
                    } label: {
                        Image(systemName: session.soundOn
                              ? "speaker.wave.2.fill"
                              : "speaker.slash.fill")
                            .foregroundColor(Theme.accent)
                    }
                    .accessibilityLabel("Toggle brick sound")

                    Button {
                        showSymbolPicker = true
                    } label: {
                        HStack(spacing: 3) {
                            Text(session.displayName)
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    }
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SymbolPicker(
                    contracts: session.contracts,
                    favorites: session.favorites,
                    loadError: session.contractError,
                    selection: $session.symbol,
                    onToggleFavorite: { session.toggleFavorite($0) },
                    onReload: { Task { await session.loadContracts() } }
                )
            }
            .sheet(isPresented: $showScanner) {
                ScannerView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            session.setAppActive(phase == .active)
        }
        .task {
            session.bootstrapIfNeeded()
        }
    }

    @ViewBuilder
    private var chartArea: some View {
        if session.bricks.isEmpty {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    if let error = session.loadError {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(Theme.accent)
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Retry") {
                            session.retryHistory()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading bricks…")
                            .font(.footnote)
                            .foregroundColor(Theme.secondary)
                    }
                }
            }
        } else {
            RenkoChartView(
                bricks: session.bricks,
                analysis: session.analysis,
                triggers: session.triggers,
                lastPrice: session.ticker?.lastPrice,
                decimals: session.decimals
            )
        }
    }
}
