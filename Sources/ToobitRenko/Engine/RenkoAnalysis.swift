import Foundation

/// Directional read of the Renko series. Purely descriptive — it summarises
/// what the bricks and two EMAs of brick closes are doing, it is not advice.
enum RenkoBias: String, Sendable {
    case long = "LONG"
    case short = "SHORT"
    case wait = "WAIT"
}

enum Indicators {
    /// Exponential moving average aligned 1:1 with `values`.
    /// The first `period - 1` entries are `nil` (not enough data); the first
    /// value is the simple average of the first `period` samples.
    static func emaSeries(_ values: [Double], period: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: values.count)
        guard period > 0, values.count >= period else { return out }
        let k = 2.0 / Double(period + 1)
        var ema = values[0..<period].reduce(0, +) / Double(period)
        out[period - 1] = ema
        if values.count > period {
            for index in period..<values.count {
                ema = values[index] * k + ema * (1 - k)
                out[index] = ema
            }
        }
        return out
    }
}

/// Everything the UI and the watchlist scanner need to know about a series.
/// Computed once per completed brick, never per tick.
struct RenkoAnalysis: Equatable, Sendable {
    static let fastPeriod = 9
    static let slowPeriod = 21
    /// Number of most recent bricks used for the chop measure.
    static let chopWindow = 20
    /// Above this direction-flip ratio the series is considered too choppy to read.
    static let chopLimit = 0.5

    var count = 0
    var upCount = 0
    /// Direction of the newest brick (`nil` when there are no bricks).
    var lastIsUp: Bool?
    /// Consecutive same-direction bricks at the tail (the reversal brick counts as 1).
    var streak = 0
    /// Share of direction flips among the last `chopWindow` bricks (0 = clean trend, 1 = pure zig-zag).
    var chop = 0.0
    var bias: RenkoBias = .wait
    /// EMA series aligned with the brick array (empty when `includeSeries` was false).
    var emaFast: [Double?] = []
    var emaSlow: [Double?] = []

    var downCount: Int { count - upCount }

    static let empty = RenkoAnalysis()

    init() {}

    init(bricks: [RenkoBrick], includeSeries: Bool = true) {
        count = bricks.count
        upCount = bricks.reduce(0) { $0 + ($1.isUp ? 1 : 0) }
        guard let last = bricks.last else { return }
        lastIsUp = last.isUp

        var run = 0
        for brick in bricks.reversed() {
            if brick.isUp == last.isUp { run += 1 } else { break }
        }
        streak = run

        let window = bricks.suffix(Self.chopWindow)
        if window.count >= 2 {
            var flips = 0
            var previous: Bool?
            for brick in window {
                if let p = previous, p != brick.isUp { flips += 1 }
                previous = brick.isUp
            }
            chop = Double(flips) / Double(window.count - 1)
        }

        let closes = bricks.map(\.close)
        let fast = Indicators.emaSeries(closes, period: Self.fastPeriod)
        let slow = Indicators.emaSeries(closes, period: Self.slowPeriod)
        if includeSeries {
            emaFast = fast
            emaSlow = slow
        }

        // Bias needs a full chop window and both EMAs, so it never fires on a
        // half-built series; a zig-zagging series always reads WAIT.
        if window.count >= Self.chopWindow,
           chop <= Self.chopLimit,
           let f = fast.last.flatMap({ $0 }),
           let s = slow.last.flatMap({ $0 }) {
            if last.isUp && f > s {
                bias = .long
            } else if !last.isUp && f < s {
                bias = .short
            }
        }
    }
}
