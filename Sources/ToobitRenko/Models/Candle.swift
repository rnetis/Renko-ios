import Foundation

/// One OHLC candle from the Toobit klines REST endpoint.
struct Candle: Equatable, Sendable {
    /// Candle open time, milliseconds since epoch.
    let openTime: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    var openDate: Date {
        Date(timeIntervalSince1970: Double(openTime) / 1000)
    }
}
