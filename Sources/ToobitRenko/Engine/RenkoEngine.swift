import Foundation

/// Percentage-based Renko builder.
///
/// Bricks live in log-price space so that every brick represents the same
/// *relative* move (default 0.5 % of price) no matter the absolute price
/// level. Because each new brick derives its size from its own anchor price,
/// the brick size is always "current" — the chart works for any coin from
/// BTC to a micro-cap without manual settings.
///
/// Classic stacking rules are used:
/// * A continuation brick forms when price closes one brick beyond the last
///   brick's close.
/// * A reversal brick forms when price closes one brick beyond the last
///   brick's *open* (i.e. a two-brick swing against the trend).
/// * One large price jump can emit several bricks at once.
struct RenkoEngine: Sendable {
    /// Relative brick size, e.g. `0.005` == 0.5 % of price.
    var relativeStep: Double

    /// Explicit init because the stored properties below are private, which
    /// would otherwise make the synthesized memberwise init private too.
    init(relativeStep: Double) {
        self.relativeStep = relativeStep
    }

    private(set) var bricks: [RenkoBrick] = []

    /// One step in log-price space: `ln(1 + relativeStep)`.
    private var logStep: Double { log(1 + relativeStep) }

    private var lastTop: Double?
    private var lastBottom: Double?
    private var lastIsUp = true
    private var seedLog: Double?
    private var nextID = 0

    var lastBrick: RenkoBrick? { bricks.last }

    /// Clears all state (used when the symbol, interval or brick size changes).
    mutating func reset() {
        bricks.removeAll(keepingCapacity: true)
        lastTop = nil
        lastBottom = nil
        seedLog = nil
        nextID = 0
    }

    /// Drops the oldest bricks so at most `last` remain. The edges of the
    /// newest brick are unaffected, so the live feed keeps working seamlessly.
    mutating func trimOldest(keeping last: Int) {
        guard bricks.count > last else { return }
        bricks.removeFirst(bricks.count - last)
    }

    /// Feeds one price observation and returns every brick it completed.
    @discardableResult
    mutating func append(price: Double, at time: Date) -> [RenkoBrick] {
        guard price.isFinite, price > 0 else { return [] }
        let lp = log(price)
        let step = logStep
        var fresh: [RenkoBrick] = []

        // Before the first brick exists, seed on the first price and wait for
        // a one-step move in either direction.
        if lastTop == nil {
            guard let seed = seedLog else {
                seedLog = lp
                return []
            }
            if lp >= seed + step {
                emit(openLog: seed, closeLog: seed + step, isUp: true, time: time, into: &fresh)
            } else if lp <= seed - step {
                emit(openLog: seed, closeLog: seed - step, isUp: false, time: time, into: &fresh)
            } else {
                return []
            }
        }

        // Drain thresholds: a single tick can stack many continuation bricks.
        while let top = lastTop, let bottom = lastBottom {
            if lastIsUp {
                if lp >= top + step {
                    emit(openLog: top, closeLog: top + step, isUp: true, time: time, into: &fresh)
                } else if lp <= bottom - step {
                    emit(openLog: bottom, closeLog: bottom - step, isUp: false, time: time, into: &fresh)
                } else {
                    break
                }
            } else {
                if lp <= bottom - step {
                    emit(openLog: bottom, closeLog: bottom - step, isUp: false, time: time, into: &fresh)
                } else if lp >= top + step {
                    emit(openLog: top, closeLog: top + step, isUp: true, time: time, into: &fresh)
                } else {
                    break
                }
            }
        }
        return fresh
    }

    private mutating func emit(openLog: Double, closeLog: Double, isUp: Bool, time: Date, into out: inout [RenkoBrick]) {
        let brick = RenkoBrick(
            id: nextID,
            open: exp(openLog),
            close: exp(closeLog),
            isUp: isUp,
            time: time
        )
        nextID += 1
        bricks.append(brick)
        lastTop = max(openLog, closeLog)
        lastBottom = min(openLog, closeLog)
        lastIsUp = isUp
        out.append(brick)
    }
}
