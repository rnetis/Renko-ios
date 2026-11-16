import Foundation

/// One line of the watchlist scan: the Renko state of a favourite contract.
struct ScanRow: Identifiable, Equatable, Sendable {
    let symbol: String
    /// Close of the newest candle at scan time.
    let price: Double
    /// Series-free analysis (no EMA arrays) to keep rows light.
    let analysis: RenkoAnalysis

    var id: String { symbol }
    var displayName: String { ContractInfo.displayName(for: symbol) }
}
