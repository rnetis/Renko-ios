import Foundation

/// Builds the Renko state of several contracts from REST history only (no
/// sockets), a few requests at a time so a 20-contract watchlist stays polite
/// to the public API.
enum RenkoScanner {
    static func scan(symbols: [String],
                     interval: String,
                     brickPercent: Double,
                     maxConcurrent: Int = 4) async -> [ScanRow] {
        guard !symbols.isEmpty else { return [] }
        let limit = max(1, maxConcurrent)

        return await withTaskGroup(of: ScanRow?.self) { group -> [ScanRow] in
            var rows: [ScanRow] = []
            var next = 0

            while next < min(limit, symbols.count) {
                let symbol = symbols[next]
                next += 1
                group.addTask {
                    await RenkoScanner.row(symbol: symbol, interval: interval, brickPercent: brickPercent)
                }
            }
            while let result = await group.next() {
                if let result { rows.append(result) }
                if next < symbols.count {
                    let symbol = symbols[next]
                    next += 1
                    group.addTask {
                        await RenkoScanner.row(symbol: symbol, interval: interval, brickPercent: brickPercent)
                    }
                }
            }
            return rows
        }
    }

    static func row(symbol: String, interval: String, brickPercent: Double) async -> ScanRow? {
        guard var candles = try? await ToobitREST.klines(symbol: symbol, interval: interval, limit: 1000),
              !candles.isEmpty else { return nil }
        candles.sort { $0.openTime < $1.openTime }

        var engine = RenkoEngine(relativeStep: brickPercent)
        for candle in candles {
            engine.append(candle: candle)
        }
        guard let price = candles.last?.close else { return nil }
        return ScanRow(
            symbol: symbol,
            price: price,
            analysis: RenkoAnalysis(bricks: engine.bricks, includeSeries: false)
        )
    }
}
