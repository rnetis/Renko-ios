import Foundation

enum ToobitError: LocalizedError {
    case badURL
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Could not build the request URL."
        case .badResponse:
            return "Malformed response from Toobit."
        case .http(let code):
            return "Toobit request failed (HTTP \(code))."
        }
    }
}

/// Public (unsigned) Toobit REST endpoints used by the app.
///
/// Verified against the live API:
/// * `GET /quote/v1/klines?symbol=BTC-SWAP-USDT&interval=1m&limit=1000`
///   returns rows of `[openTime, open, high, low, close, volume, ...]`
///   (numbers arrive as strings; the last candle may be the in-progress one).
/// * `GET /api/v1/exchangeInfo` returns a top-level `contracts` array with the
///   USDT-M futures (spot lives in `symbols`).
enum ToobitREST {
    static let base = URL(string: "https://api.toobit.com")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Fetches recent candles for a contract.
    static func klines(symbol: String, interval: String, limit: Int) async throws -> [Candle] {
        var comps = URLComponents(url: base.appendingPathComponent("quote/v1/klines"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps?.url else { throw ToobitError.badURL }

        let (data, response) = try await session.data(from: url)
        try checkStatus(response)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let rows = obj as? [[Any]] else { throw ToobitError.badResponse }

        return rows.compactMap { row -> Candle? in
            guard row.count >= 6,
                  let t = number(row[0]),
                  let o = number(row[1]),
                  let h = number(row[2]),
                  let l = number(row[3]),
                  let c = number(row[4]) else { return nil }
            return Candle(
                openTime: Int64(t),
                open: o,
                high: h,
                low: l,
                close: c,
                volume: number(row[5]) ?? 0
            )
        }
    }

    /// Fetches every linear USDT-margined perpetual that is currently tradable.
    static func contracts() async throws -> [ContractInfo] {
        let (data, response) = try await session.data(from: base.appendingPathComponent("api/v1/exchangeInfo"))
        try checkStatus(response)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let root = obj as? [String: Any],
              let list = root["contracts"] as? [[String: Any]] else { throw ToobitError.badResponse }

        var out: [ContractInfo] = []
        for entry in list {
            guard let symbol = entry["symbol"] as? String else { continue }
            let status = entry["status"] as? String ?? ""
            let inverse = entry["inverse"] as? Bool ?? false
            let marginToken = entry["marginToken"] as? String ?? ""
            guard status == "TRADING", !inverse, marginToken == "USDT" else { continue }

            var tick = 0.01
            if let filters = entry["filters"] as? [[String: Any]],
               let priceFilter = filters.first(where: { ($0["filterType"] as? String) == "PRICE_FILTER" }),
               let tickString = priceFilter["tickSize"] as? String,
               let parsed = Double(tickString) {
                tick = parsed
            }
            let baseAsset = symbol.hasSuffix("-SWAP-USDT")
                ? String(symbol.dropLast("-SWAP-USDT".count))
                : symbol
            out.append(ContractInfo(symbol: symbol, base: baseAsset, tickSize: tick, status: status))
        }
        return out.sorted { $0.symbol < $1.symbol }
    }

    // MARK: - Helpers

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ToobitError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw ToobitError.http(http.statusCode) }
    }

    /// Toobit returns most quote numbers as JSON strings; accept both forms.
    /// The parameter is optional because dictionary lookups return `Any?`.
    static func number(_ any: Any?) -> Double? {
        guard let value = any else { return nil }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
