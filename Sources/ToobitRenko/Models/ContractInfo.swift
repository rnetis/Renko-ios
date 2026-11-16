import Foundation

/// A linear USDT-margined perpetual contract listed on Toobit.
struct ContractInfo: Identifiable, Hashable, Sendable {
    /// Raw exchange symbol, e.g. `BTC-SWAP-USDT`.
    let symbol: String
    /// Underlying base asset, e.g. `BTC`.
    let base: String
    /// Minimum price increment from the contract's PRICE_FILTER.
    let tickSize: Double
    let status: String

    var id: String { symbol }

    /// Friendly display name, e.g. `BTC-SWAP-USDT` → `BTCUSDT.P`.
    var displayName: String { Self.displayName(for: symbol) }

    static func displayName(for symbol: String) -> String {
        symbol.replacingOccurrences(of: "-SWAP-USDT", with: "USDT") + ".P"
    }
}
