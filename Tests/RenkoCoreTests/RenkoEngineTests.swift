import XCTest
@testable import RenkoCore

final class RenkoEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    /// 1 % bricks keep the arithmetic easy to read.
    private func engine() -> RenkoEngine { RenkoEngine(relativeStep: 0.01) }

    func testSeedPriceAloneEmitsNothing() {
        var e = engine()
        XCTAssertTrue(e.append(price: 100, at: t0).isEmpty)
        XCTAssertTrue(e.bricks.isEmpty)
    }

    func testFirstUpBrickIsOnePercentOfSeed() {
        var e = engine()
        e.append(price: 100, at: t0)
        let fresh = e.append(price: 101.5, at: t0)
        XCTAssertEqual(fresh.count, 1)
        XCTAssertTrue(fresh[0].isUp)
        XCTAssertEqual(fresh[0].open, 100, accuracy: 1e-9)
        XCTAssertEqual(fresh[0].close, 101, accuracy: 1e-9)
    }

    func testLargeJumpStacksSeveralBricks() {
        var e = engine()
        e.append(price: 100, at: t0)
        let fresh = e.append(price: 103.5, at: t0)
        XCTAssertEqual(fresh.count, 3)
        XCTAssertTrue(fresh.allSatisfy(\.isUp))
        XCTAssertEqual(fresh[2].close, 100 * pow(1.01, 3), accuracy: 1e-9)
    }

    func testEveryBrickHasTheSameRelativeSize() {
        var e = engine()
        e.append(price: 50_000, at: t0)
        for price in [50_900.0, 52_000, 49_000, 47_500, 55_000] {
            e.append(price: price, at: t0)
        }
        XCTAssertGreaterThan(e.bricks.count, 5)
        for brick in e.bricks {
            let ratio = brick.isUp ? brick.close / brick.open : brick.open / brick.close
            XCTAssertEqual(ratio, 1.01, accuracy: 1e-9)
        }
    }

    func testReversalNeedsTwoBricksAgainstTheTrend() {
        var e = engine()
        e.append(price: 100, at: t0)
        e.append(price: 101.5, at: t0)               // up brick 100 → 101
        XCTAssertTrue(e.append(price: 99.5, at: t0).isEmpty, "one brick back is not a reversal")
        let fresh = e.append(price: 99.0, at: t0)    // below 100 / 1.01
        XCTAssertEqual(fresh.count, 1)
        XCTAssertFalse(fresh[0].isUp)
        XCTAssertEqual(fresh[0].open, 100, accuracy: 1e-9, "reversal opens at the previous brick's open")
    }

    func testTriggersBeforeAndAfterFirstBrick() throws {
        var e = engine()
        XCTAssertNil(e.triggers)
        e.append(price: 100, at: t0)
        var t = try XCTUnwrap(e.triggers)
        XCTAssertEqual(t.up, 101, accuracy: 1e-9)
        XCTAssertEqual(t.down, 100 / 1.01, accuracy: 1e-9)

        e.append(price: 101.5, at: t0)               // brick 100 → 101
        t = try XCTUnwrap(e.triggers)
        XCTAssertEqual(t.up, 102.01, accuracy: 1e-9)
        XCTAssertEqual(t.down, 100 / 1.01, accuracy: 1e-9)
    }

    func testTriggersPredictTheNextBrick() throws {
        var e = engine()
        e.append(price: 100, at: t0)
        e.append(price: 101.5, at: t0)
        let t = try XCTUnwrap(e.triggers)
        XCTAssertTrue(e.append(price: t.up * 0.9999, at: t0).isEmpty)
        XCTAssertEqual(e.append(price: t.up * 1.0001, at: t0).count, 1)
    }

    func testCandleReplayCatchesWicksThatCloseOnlyReplayMisses() {
        var ohlc = engine()
        let candle = Candle(openTime: 1_700_000_000_000, open: 100, high: 103.5,
                            low: 99.9, close: 100.2, volume: 1)
        let fresh = ohlc.append(candle: candle)
        XCTAssertEqual(fresh.map(\.isUp), [true, true, true, false])

        var closeOnly = engine()
        closeOnly.append(price: candle.open, at: t0)
        closeOnly.append(price: candle.close, at: t0)
        XCTAssertTrue(closeOnly.bricks.isEmpty)
    }

    func testBearishCandleVisitsHighBeforeLow() {
        var e = engine()
        let candle = Candle(openTime: 0, open: 100, high: 101.5, low: 96.5,
                            close: 97, volume: 1)
        let fresh = e.append(candle: candle)
        // up to 101, then reversal + continuation down to ~97.03
        XCTAssertEqual(fresh.first?.isUp, true)
        XCTAssertEqual(fresh.last?.isUp, false)
    }

    func testInvalidPricesAreIgnored() {
        var e = engine()
        e.append(price: 100, at: t0)
        XCTAssertTrue(e.append(price: .nan, at: t0).isEmpty)
        XCTAssertTrue(e.append(price: -5, at: t0).isEmpty)
        XCTAssertTrue(e.append(price: 0, at: t0).isEmpty)
        var degenerate = RenkoEngine(relativeStep: 0)
        degenerate.append(price: 100, at: t0)
        XCTAssertTrue(degenerate.append(price: 200, at: t0).isEmpty, "zero step must not loop forever")
    }

    func testCorruptTickCannotFloodTheSeries() {
        var e = RenkoEngine(relativeStep: 0.001)
        e.append(price: 50_000, at: t0)
        let fresh = e.append(price: 0.0001, at: t0)
        XCTAssertLessThanOrEqual(fresh.count, 2000)
    }

    func testIdsSurviveTrimming() {
        var e = engine()
        e.append(price: 100, at: t0)
        e.append(price: 110, at: t0)
        let total = e.bricks.count
        XCTAssertGreaterThan(total, 5)
        e.trimOldest(keeping: 3)
        XCTAssertEqual(e.bricks.count, 3)
        XCTAssertEqual(e.bricks.last?.id, total - 1)
        e.append(price: 120, at: t0)
        XCTAssertEqual(e.bricks.last?.id, e.bricks.map(\.id).max())
    }

    func testResetRestartsSeeding() {
        var e = engine()
        e.append(price: 100, at: t0)
        e.append(price: 105, at: t0)
        e.reset()
        XCTAssertTrue(e.bricks.isEmpty)
        XCTAssertNil(e.triggers)
        XCTAssertTrue(e.append(price: 500, at: t0).isEmpty)
    }
}

final class RenkoAnalysisTests: XCTestCase {
    private func series(_ directions: [Bool]) -> [RenkoBrick] {
        var price = 100.0
        var out: [RenkoBrick] = []
        for (index, up) in directions.enumerated() {
            let open = price
            price = up ? price * 1.01 : price / 1.01
            out.append(RenkoBrick(id: index, open: open, close: price, isUp: up,
                                  time: Date(timeIntervalSince1970: Double(index))))
        }
        return out
    }

    func testEmaOfConstantSeriesIsConstantAndAligned() {
        let ema = Indicators.emaSeries([Double](repeating: 5, count: 30), period: 9)
        XCTAssertEqual(ema.count, 30)
        XCTAssertTrue(ema[0..<8].allSatisfy { $0 == nil })
        XCTAssertEqual(ema[8] ?? 0, 5, accuracy: 1e-12)
        XCTAssertEqual(ema[29] ?? 0, 5, accuracy: 1e-12)
    }

    func testEmaWithTooLittleDataIsAllNil() {
        XCTAssertTrue(Indicators.emaSeries([1, 2, 3], period: 9).allSatisfy { $0 == nil })
        XCTAssertTrue(Indicators.emaSeries([], period: 9).isEmpty)
    }

    func testStreakAndCounts() {
        let a = RenkoAnalysis(bricks: series([true, false, false, true, true, true]))
        XCTAssertEqual(a.count, 6)
        XCTAssertEqual(a.upCount, 4)
        XCTAssertEqual(a.downCount, 2)
        XCTAssertEqual(a.streak, 3)
        XCTAssertEqual(a.lastIsUp, true)
    }

    func testChopIsZeroForTrendAndOneForZigZag() {
        XCTAssertEqual(RenkoAnalysis(bricks: series([Bool](repeating: true, count: 25))).chop, 0, accuracy: 1e-12)
        let zigzag = (0..<25).map { $0 % 2 == 0 }
        XCTAssertEqual(RenkoAnalysis(bricks: series(zigzag)).chop, 1, accuracy: 1e-12)
    }

    func testCleanUptrendReadsLong() {
        XCTAssertEqual(RenkoAnalysis(bricks: series([Bool](repeating: true, count: 40))).bias, .long)
    }

    func testCleanDowntrendReadsShort() {
        XCTAssertEqual(RenkoAnalysis(bricks: series([Bool](repeating: false, count: 40))).bias, .short)
    }

    func testChoppySeriesAndShortSeriesReadWait() {
        let zigzag = (0..<40).map { $0 % 2 == 0 }
        XCTAssertEqual(RenkoAnalysis(bricks: series(zigzag)).bias, .wait)
        XCTAssertEqual(RenkoAnalysis(bricks: series([Bool](repeating: true, count: 10))).bias, .wait)
        XCTAssertEqual(RenkoAnalysis.empty.bias, .wait)
    }

    func testSeriesAreOptional() {
        let bricks = series([Bool](repeating: true, count: 30))
        XCTAssertEqual(RenkoAnalysis(bricks: bricks).emaFast.count, 30)
        XCTAssertTrue(RenkoAnalysis(bricks: bricks, includeSeries: false).emaFast.isEmpty)
    }
}
