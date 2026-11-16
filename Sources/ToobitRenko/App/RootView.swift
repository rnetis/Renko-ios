import SwiftUI

/// Composes the whole screen: ticker bar, interval row, chart, stats bar.
struct RootView: View {
    @EnvironmentObject private var session: MarketSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSymbolPicker = false

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
                    bricks: session.bricks,
                    brickPercent: session.brickPercent,
                    decimals: session.decimals
                )
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                SymbolPicker(contracts: session.contracts, selection: $session.symbol)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            session.isAppActive = (phase == .active)
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
                lastPrice: session.ticker?.lastPrice,
                decimals: session.decimals
            )
        }
    }
}
