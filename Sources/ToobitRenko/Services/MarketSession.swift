import Combine
import Foundation

/// Connection status of the live quote stream.
enum StreamStatus: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int, reason: String)
}

/// Owns everything market-related: the contract list, the Renko engine, the
/// history seed and the live WebSocket feed.
///
/// Data flow:
/// 1. `bootstrapIfNeeded()` loads the contract list from `exchangeInfo`.
/// 2. `seedHistory()` pulls up to 1000 candles via REST and replays their
///    closes through `RenkoEngine` to build the initial bricks.
/// 3. `connect()` opens `wss://stream.toobit.com/quote/ws/v1` and subscribes
///    to the `realtimes` topic; every last-traded price feeds the engine.
/// 4. A 20 s JSON heartbeat (`{"ping": ms}`) doubles as a staleness watchdog:
///    if nothing arrives for 45 s the socket is cancelled and the reconnect
///    loop (2 s … 15 s backoff) starts over with a fresh subscription.
@MainActor
final class MarketSession: ObservableObject {

    // MARK: - Published state

    @Published private(set) var contracts: [ContractInfo] = []
    @Published private(set) var bricks: [RenkoBrick] = []
    @Published private(set) var ticker: TickerSnapshot?
    @Published private(set) var status: StreamStatus = .idle
    @Published private(set) var loadError: String?
    @Published private(set) var isSeeding = false

    /// Selected contract, e.g. `BTC-SWAP-USDT`.
    @Published var symbol = "BTC-SWAP-USDT" {
        didSet { if symbol != oldValue { restart() } }
    }
    /// Candle granularity used to seed history (`1m`…`1d`).
    @Published var interval = "1m" {
        didSet { if interval != oldValue { restart() } }
    }
    /// Relative brick size, e.g. `0.005` == 0.5 % of price.
    @Published var brickPercent = 0.005 {
        didSet { if brickPercent != oldValue { restart() } }
    }
    /// Sound effect on a completed brick (haptics stay on).
    @Published var soundOn = true

    /// Mirrors the scene phase; feedback is suppressed while the app is in the background.
    var isAppActive = true

    // MARK: - Static choices

    static let intervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"]
    static let brickPercentChoices: [Double] = [0.001, 0.0025, 0.005, 0.01]

    private static let maxBricks = 4000
    private static let historyLimit = 1000

    // MARK: - Internals

    private var engine = RenkoEngine(relativeStep: 0.005)
    private let streamURL = URL(string: "wss://stream.toobit.com/quote/ws/v1")!
    private var socketTask: URLSessionWebSocketTask?
    private var readTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var seedTask: Task<Void, Never>?
    /// Bumped on every symbol/interval/size change; stale socket events are dropped.
    private var generation = 0
    private var attempt = 0
    private var lastMessageAt: Date?
    /// Latest live price seen while history is still seeding, applied afterwards.
    private var pendingLive: (price: Double, time: Date)?
    private var bootstrapStarted = false

    // MARK: - Derived

    var selectedContract: ContractInfo? {
        contracts.first { $0.symbol == symbol }
    }

    /// Decimal places for price strings, derived from the contract tick size.
    var decimals: Int {
        if let contract = selectedContract {
            return Format.decimals(forTick: contract.tickSize)
        }
        if let price = ticker?.lastPrice {
            return price >= 100 ? 2 : (price >= 1 ? 3 : 6)
        }
        return 2
    }

    var displayName: String {
        selectedContract?.displayName
            ?? symbol.replacingOccurrences(of: "-SWAP-USDT", with: "USDT") + ".P"
    }

    // MARK: - Lifecycle

    func bootstrapIfNeeded() {
        guard !bootstrapStarted else { return }
        bootstrapStarted = true
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await loadContracts()
        await seedHistory()
        connect()
    }

    func loadContracts() async {
        do {
            contracts = try await ToobitREST.contracts()
        } catch {
            loadError = "Could not load contract list: \(error.localizedDescription)"
        }
    }

    /// Tears everything down and starts over with the current settings.
    func restart() {
        generation += 1
        teardownSocket()
        reconnectTask?.cancel()
        reconnectTask = nil
        seedTask?.cancel()
        bricks = []
        engine = RenkoEngine(relativeStep: brickPercent)
        ticker = nil
        loadError = nil
        attempt = 0
        status = .idle
        pendingLive = nil
        seedTask = Task { await seedHistory() }
        connect()
    }

    /// Alias used by the Retry button on the error overlay.
    func retryHistory() {
        restart()
    }

    // MARK: - History seed

    private func seedHistory() async {
        let gen = generation
        isSeeding = true
        defer { isSeeding = false }
        do {
            let candles = try await ToobitREST.klines(
                symbol: symbol,
                interval: interval,
                limit: Self.historyLimit
            )
            guard gen == generation, !Task.isCancelled else { return }
            engine.reset()
            for candle in candles {
                engine.append(price: candle.close, at: candle.openDate)
            }
            engine.trimOldest(keeping: Self.maxBricks)
            bricks = engine.bricks
            loadError = nil
            if let pending = pendingLive {
                pendingLive = nil
                feed(price: pending.price, at: pending.time)
            }
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            loadError = "History unavailable: \(error.localizedDescription)"
        }
    }

    // MARK: - Live feed

    private func feed(price: Double, at time: Date) {
        let fresh = engine.append(price: price, at: time)
        guard !fresh.isEmpty else { return }
        bricks.append(contentsOf: fresh)
        engine.trimOldest(keeping: Self.maxBricks)
        if bricks.count > Self.maxBricks {
            bricks.removeFirst(bricks.count - Self.maxBricks)
        }
        guard isAppActive, let last = fresh.last else { return }
        Haptics.brickHaptic(up: last.isUp)
        if soundOn {
            Haptics.playBrickSound()
        }
    }

    // MARK: - WebSocket

    private func connect() {
        let gen = generation
        teardownSocket()
        status = .connecting

        let task = URLSession.shared.webSocketTask(with: streamURL)
        socketTask = task
        task.resume()
        sendSubscribe(on: task)
        readTask = Task { [weak self] in
            await self?.readLoop(task: task, generation: gen)
        }
        pingTask = Task { [weak self] in
            await self?.pingLoop(task: task, generation: gen)
        }
    }

    private func sendSubscribe(on task: URLSessionWebSocketTask) {
        let payload: [String: Any] = [
            "symbol": symbol,
            "topic": "realtimes",
            "event": "sub",
            "params": ["binary": false],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        task.send(.data(data)) { _ in }
    }

    private func readLoop(task: URLSessionWebSocketTask, generation gen: Int) async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                guard gen == generation, !Task.isCancelled else { return }
                scheduleReconnect(reason: "connection lost: \(shortError(error))")
                return
            }
            guard gen == generation else { return }
            lastMessageAt = Date()
            if status != .connected {
                status = .connected
                attempt = 0
            }
            switch message {
            case .string(let text):
                handleSocketText(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleSocketText(text)
                }
            @unknown default:
                break
            }
        }
    }

    /// Sends the documented JSON heartbeat and cancels a stale socket.
    private func pingLoop(task: URLSessionWebSocketTask, generation gen: Int) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if Task.isCancelled || gen != generation { return }
            let payload: [String: Int64] = ["ping": Int64(Date().timeIntervalSince1970 * 1000)]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                task.send(.data(data)) { _ in }
            }
            if let last = lastMessageAt, Date().timeIntervalSince(last) > 45 {
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func scheduleReconnect(reason: String) {
        teardownSocket()
        attempt += 1
        status = .reconnecting(attempt: attempt, reason: reason)
        let delaySeconds = min(Double(attempt) * 2.0, 15.0)
        let gen = generation
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self, gen == self.generation, !Task.isCancelled else { return }
            self.connect()
        }
    }

    private func teardownSocket() {
        readTask?.cancel()
        pingTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        readTask = nil
        pingTask = nil
        socketTask = nil
    }

    // MARK: - Socket message decoding

    private func handleSocketText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return }

        if dict["pong"] != nil { return }

        guard let topic = dict["topic"] as? String, topic == "realtimes",
              let rows = dict["data"] as? [[String: Any]],
              let row = rows.first else { return }

        let time = dateFromMillis(row["t"])
        guard let price = ToobitREST.number(row["c"]) else { return }
        let snapshot = TickerSnapshot(
            time: time,
            lastPrice: price,
            open24h: ToobitREST.number(row["o24h"]) ?? ToobitREST.number(row["o"]) ?? price,
            high24h: ToobitREST.number(row["h24h"]) ?? ToobitREST.number(row["h"]) ?? price,
            low24h: ToobitREST.number(row["l24h"]) ?? ToobitREST.number(row["l"]) ?? price,
            quoteVolume: ToobitREST.number(row["qv"]) ?? 0
        )
        ticker = snapshot

        if isSeeding {
            pendingLive = (price, time)
        } else {
            feed(price: price, at: time)
        }
    }

    // MARK: - Small helpers

    private func shortError(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.count > 60 ? String(text.prefix(60)) : text
    }

    private func dateFromMillis(_ any: Any?) -> Date {
        let ms = (any as? NSNumber)?.doubleValue ?? 0
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
