import Foundation

/// Latest values of the Toobit `realtimes` (24h ticker) stream for one contract.
struct TickerSnapshot: Equatable, Sendable {
    let time: Date
    /// Last traded price — the value that feeds the Renko engine.
    let lastPrice: Double
    let open24h: Double
    let high24h: Double
    let low24h: Double
    /// Quote-asset (USDT) volume over the last 24 hours.
    let quoteVolume: Double

    /// 24h change as a fraction (0.0123 == +1.23 %).
    var change24h: Double {
        guard open24h > 0 else { return 0 }
        return (lastPrice - open24h) / open24h
    }
}
