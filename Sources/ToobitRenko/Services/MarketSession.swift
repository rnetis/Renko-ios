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
/// history seed, the live WebSocket feed and the favourites watchlist.
///
/// Data flow:
/// 1. `bootstrapIfNeeded()` starts the history seed + socket immediately and
///    loads the contract list in parallel (the chart never waits for it).
/// 2. `startSeed()` pulls up to 1000 candles via REST and replays them
///    (open / extreme / extreme / close) through `RenkoEngine`.
/// 3. `connect()` opens `wss://stream.toobit.com/quote/ws/v1` and subscribes
///    to the `realtimes` topic; every last-traded price feeds the engine.
///    Ticks that arrive while the seed is in flight are buffered.
/// 4. A 20 s JSON heartbeat doubles as a staleness watchdog: if nothing
///    arrives for 45 s the socket is cancelled and the reconnect loop
///    (2 s … 15 s backoff) starts over. After any reconnect, or after the app
///    returns from a long stay in the background, history is re-seeded so
///    bricks formed during the gap are backfilled instead of lost.
@MainActor
final class MarketSession: ObservableObject {

    // MARK: - Published state

    @Published private(set) var contracts: [ContractInfo] = [] {
        didSet {
            contractIndex = Dictionary(contracts.map { ($0.symbol, $0) },
                                       uniquingKeysWith: { first, _ in first })
        }
    }
    @Published private(set) var contractError: String?
    @Published private(set) var bricks: [RenkoBrick] = []
    @Published private(set) var analysis = RenkoAnalysis.empty
    @Published private(set) var triggers: PriceTriggers?
    @Published private(set) var ticker: TickerSnapshot?
    @Published private(set) var status: StreamStatus = .idle
    @Published private(set) var loadError: String?
    @Published private(set) var isSeeding = false

    @Published private(set) var favorites: [String] = []
    @Published private(set) var scanRows: [ScanRow] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanFailures = 0
    @Published private(set) var scanLabel: String?
    @Published private(set) var lastScanAt: Date?

    /// Selected contract, e.g. `BTC-SWAP-USDT`.
    @Published var symbol = "BTC-SWAP-USDT" {
        didSet {
            guard symbol != oldValue else { return }
            defaults.set(symbol, forKey: Keys.symbol)
            restart()
        }
    }
    /// Candle granularity used to seed history (`1m`…`1d`).
    @Published var interval = "1m" {
        didSet {
            guard interval != oldValue else { return }
            defaults.set(interval, forKey: Keys.interval)
            restart()
        }
    }
    /// Relative brick size, e.g. `0.005` == 0.5 % of price.
    @Published var brickPercent = 0.005 {
        didSet {
            guard brickPercent != oldValue else { return }
            defaults.set(brickPercent, forKey: Keys.brick)
            restart()
        }
    }
    /// Sound effect on a completed brick (haptics stay on).
    @Published var soundOn = true {
        didSet { defaults.set(soundOn, forKey: Keys.sound) }
    }

    /// Mirrors the scene phase; feedback is suppressed while the app is in the background.
    private(set) var isAppActive = true

    // MARK: - Static choices

    static let intervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"]
    static let brickPercentChoices: [Double] = [0.001, 0.0025, 0.005, 0.01]
    static let maxFavorites = 20

    private static let maxBricks = 4000
    private static let historyLimit = 1000
    /// Time in the background after which the feed is rebuilt on return.
    private static let resumeResyncAfter: TimeInterval = 15

    private enum Keys {
        static let symbol = "session.symbol"
        static let interval = "session.interval"
        static let brick = "session.brickPercent"
        static let sound = "session.soundOn"
        static let favorites = "session.favorites"
    }

    // MARK: - Internals

    private let defaults = UserDefaults.standard
    private var engine = RenkoEngine(relativeStep: 0.005)
    private var contractIndex: [String: ContractInfo] = [:]
    private let streamURL = URL(string: "wss://stream.toobit.com/quote/ws/v1")!
    private var socketTask: URLSessionWebSocketTask?
    private var readTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var seedTask: Task<Void, Never>?
    /// Bumped on every (re)connect; events from older sockets are dropped.
    private var generation = 0
    /// Bumped on every seed; only the newest seed may touch state.
    private var seedToken = 0
    private var attempt = 0
    private var lastMessageAt: Date?
    private var backgroundedAt: Date?
    /// Set when ticks may have been missed; the next live message triggers a re-seed.
    private var needsResync = false
    /// Latest live price seen while history is still seeding, applied afterwards.
    private var pendingLive: (price: Double, time: Date)?
    private var bootstrapStarted = false

    // MARK: - Init

    init() {
        if let saved = defaults.string(forKey: Keys.symbol), !saved.isEmpty {
            symbol = saved
        }
        if let saved = defaults.string(forKey: Keys.interval), Self.intervals.contains(saved) {
            interval = saved
        }
        let savedBrick = defaults.double(forKey: Keys.brick)
        if Self.brickPercentChoices.contains(savedBrick) {
            brickPercent = savedBrick
        }
        if defaults.object(forKey: Keys.sound) != nil {
            soundOn = defaults.bool(forKey: Keys.sound)
        }
        favorites = defaults.stringArray(forKey: Keys.favorites) ?? []
        engine = RenkoEngine(relativeStep: brickPercent)
    }

    // MARK: - Derived

    var selectedContract: ContractInfo? {
        contractIndex[symbol]
    }

    /// Decimal places for price strings, derived from the contract tick size.
    var decimals: Int {
        if let contract = contractIndex[symbol] {
            return Format.decimals(forTick: contract.tickSize)
        }
        if let price = ticker?.lastPrice {
            return price >= 100 ? 2 : (price >= 1 ? 3 : 6)
        }
        return 2
    }

    func decimals(for symbol: String, price: Double) -> Int {
        if let contract = contractIndex[symbol] {
            return Format.decimals(forTick: contract.tickSize)
        }
        return price >= 100 ? 2 : (price >= 1 ? 3 : 6)
    }

    var displayName: String {
        selectedContract?.displayName ?? ContractInfo.displayName(for: symbol)
    }

    // MARK: - Lifecycle

    func bootstrapIfNeeded() {
        guard !bootstrapStarted else { return }
        bootstrapStarted = true
        // The chart does not need the 780-contract list, so start it right away.
        restart()
        Task { await loadContracts() }
    }

    func loadContracts() async {
        do {
            let list = try await ToobitREST.contracts()
            contracts = list
            contractError = nil
        } catch {
            contractError = "Could not load contract list: \(error.localizedDescription)"
        }
    }

    /// Tears everything down and starts over with the current settings.
    func restart() {
        guard bootstrapStarted else { return }
        teardownSocket()
        reconnectTask?.cancel()
        reconnectTask = nil
        bricks = []
        analysis = .empty
        triggers = nil
        engine = RenkoEngine(relativeStep: brickPercent)
        ticker = nil
        loadError = nil
        attempt = 0
        needsResync = false
        status = .idle
        pendingLive = nil
        startSeed()
        connect()
    }

    /// Alias used by the Retry button on the error overlay.
    func retryHistory() {
        restart()
    }

    /// Called from the scene phase. Coming back from a long stay in the
    /// background the socket is usually dead and ticks were missed, so the
    /// feed is rebuilt (reconnect + history re-seed).
    func setAppActive(_ active: Bool) {
        let wasActive = isAppActive
        isAppActive = active
        guard bootstrapStarted else { return }
        if !active {
            if wasActive { backgroundedAt = Date() }
            return
        }
        if let since = backgroundedAt,
           Date().timeIntervalSince(since) > Self.resumeResyncAfter {
            needsResync = true
            reconnectTask?.cancel()
            reconnectTask = nil
            attempt = 0
            connect()
        }
        backgroundedAt = nil
    }

    // MARK: - History seed

    private func startSeed() {
        seedTask?.cancel()
        seedToken += 1
        let token = seedToken
        isSeeding = true
        seedTask = Task { [weak self] in
            await self?.seedHistory(token: token)
        }
    }

    private func seedHistory(token: Int) async {
        // A cancelled/superseded seed must not clear the flag of the newer one.
        defer { if token == seedToken { isSeeding = false } }
        let seedSymbol = symbol
        let seedInterval = interval
        do {
            var candles = try await ToobitREST.klines(
                symbol: seedSymbol,
                interval: seedInterval,
                limit: Self.historyLimit
            )
            guard token == seedToken, !Task.isCancelled else { return }
            candles.sort { $0.openTime < $1.openTime }

            var fresh = RenkoEngine(relativeStep: brickPercent)
            for candle in candles {
                fresh.append(candle: candle)
            }
            fresh.trimOldest(keeping: Self.maxBricks)
            engine = fresh
            publishBricks()
            loadError = nil

            if let pending = pendingLive {
                pendingLive = nil
                feed(price: pending.price, at: pending.time)
            }
        } catch {
            guard token == seedToken, !Task.isCancelled else { return }
            loadError = "History unavailable: \(error.localizedDescription)"
        }
    }

    // MARK: - Live feed

    /// Single place where engine state becomes UI state. Runs once per
    /// completed brick (never per tick), so the O(n) analysis is cheap.
    private func publishBricks() {
        bricks = engine.bricks
        analysis = RenkoAnalysis(bricks: bricks)
        triggers = engine.triggers
    }

    private func feed(price: Double, at time: Date) {
        let fresh = engine.append(price: price, at: time)
        guard !fresh.isEmpty else { return }
        engine.trimOldest(keeping: Self.maxBricks)
        let previousBias = analysis.bias
        publishBricks()
        guard isAppActive, let last = fresh.last else { return }
        Haptics.brickHaptic(up: last.isUp)
        if soundOn {
            Haptics.playBrickSound()
        }
        if analysis.bias != previousBias, analysis.bias != .wait {
            Haptics.biasChangeHaptic()
        }
    }

    // MARK: - WebSocket

    private func connect() {
        teardownSocket()
        generation += 1
        let gen = generation
        status = .connecting
        lastMessageAt = Date()

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
                if needsResync {
                    // Ticks were missed while offline: rebuild from history.
                    // Starting the seed *before* handling this message makes
                    // sure the tick is buffered instead of fed to a stale engine.
                    needsResync = false
                    startSeed()
                }
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
        needsResync = true
        status = .reconnecting(attempt: attempt, reason: reason)
        let delaySeconds = min(Double(attempt) * 2.0, 15.0)
        let gen = generation
        reconnectTask?.cancel()
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

    // MARK: - Watchlist

    func isFavorite(_ symbol: String) -> Bool {
        favorites.contains(symbol)
    }

    func toggleFavorite(_ symbol: String) {
        if let index = favorites.firstIndex(of: symbol) {
            favorites.remove(at: index)
        } else if favorites.count < Self.maxFavorites {
            favorites.append(symbol)
        }
        defaults.set(favorites, forKey: Keys.favorites)
        scanRows.removeAll { !favorites.contains($0.symbol) }
    }

    /// Rebuilds Renko state for every favourite with the *current* interval
    /// and brick size, so rows are directly comparable.
    func refreshScan() async {
        guard !isScanning, !favorites.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }
        let symbols = favorites
        let scanInterval = interval
        let scanPercent = brickPercent
        let rows = await RenkoScanner.scan(
            symbols: symbols,
            interval: scanInterval,
            brickPercent: scanPercent
        )
        scanRows = rows
        scanFailures = symbols.count - rows.count
        scanLabel = "\(scanInterval) history · \(String(format: "%.2f", scanPercent * 100))% bricks"
        lastScanAt = Date()
    }

    // MARK: - Small helpers

    private func shortError(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.count > 60 ? String(text.prefix(60)) : text
    }

    /// Toobit sends `t` as a JSON string on some streams, so parse both forms
    /// instead of only `NSNumber` (which would stamp every brick at 1970).
    private func dateFromMillis(_ any: Any?) -> Date {
        guard let ms = ToobitREST.number(any), ms > 0 else { return Date() }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
