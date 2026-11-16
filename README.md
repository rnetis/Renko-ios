# Toobit Renko (iOS)

A native SwiftUI app that renders a **live Renko chart** of any **Toobit USDT-M perpetual futures** contract, built on real exchange data — no mock, no key required.

- Default contract: **BTC-SWAP-USDT**, with an in-app searchable picker for all ~780 tradable linear USDT-M perpetuals.
- Auto brick size: **0.5 % of price** (selectable 0.1 % / 0.25 % / 0.5 % / 1 %) — recalculated per brick from its own anchor price, so the chart works for BTC and micro-caps alike without manual steps.
- Dark terminal look, Canvas-rendered bricks, pan / pinch-zoom, dashed last-price line.
- Chart workbench: tap any brick for a crosshair with exact time / open / close / move, pinch out to fit the whole series on screen (**Fit**), and **Live** to snap back to the newest brick. While scrolled back the window stays put as new bricks arrive.
- **Next-brick triggers**: two dotted lines show the exact prices at which the next up / down brick completes (continuation *and* reversal), so you can see how far price is from printing.
- **EMA 9 / 21 on brick closes** (toggle with **EMA**) and a descriptive **bias** pill — `LONG`, `SHORT` or `WAIT` — plus a **chop** gauge (share of direction flips in the last 20 bricks). A heavy haptic fires when the bias flips on the selected contract.
- **Watchlist + scanner**: star up to 20 contracts (toolbar star, or swipe a row in the picker) and open the scanner to compare bias / streak / chop across all of them at the current interval and brick size.
- Settings (contract, interval, brick size, sound) and the watchlist persist between launches.
- Extras: live ticker bar (last price, 24 h change/high/low/volume, connection pill), interval selector, brick count / up-down / streak stats, haptic + optional sound when a brick completes.
- **iOS 17+**, pure SwiftUI, zero third-party dependencies.

---

## Getting an IPA

### GitHub Actions (recommended)

1. Push this repo to GitHub (or use *Import repository*).
2. Open the **Actions** tab → workflow **Build IPA** → it runs automatically on every push to `main` (and on tags `v*` / manual dispatch).
3. Download the **`ToobitRenko-unsigned-ipa`** artifact from the finished run — that's the IPA.

The workflow (`.github/workflows/build-ipa.yml`) does: install [XcodeGen](https://github.com/yonaskolb/XcodeGen) → `xcodegen generate` → `xcodebuild archive` with code signing disabled → zip the `.app` into `Payload/` → upload as artifact. It also cuts a GitHub Release with the IPA attached: a push to `main` publishes `v<MARKETING_VERSION>` (the tag is created at the pushed commit if missing, and an existing release of that version gets its IPA replaced), and pushing a `v*` tag publishes that tag. So a new release = bump `MARKETING_VERSION` in `project.yml` and push to `main`.

> The CI IPA is **unsigned** (no Apple certificate exists on the runner). See *Installing the unsigned IPA* below.

### Build locally

```bash
git clone https://github.com/rnetis/Renko-ios.git
cd Renko-ios
brew install xcodegen       # once
xcodegen generate           # creates ToobitRenko.xcodeproj from project.yml
open ToobitRenko.xcodeproj
swift test                  # engine + analysis unit tests, no simulator needed
```

Pick the **ToobitRenko** scheme → run on an iOS 17+ simulator, or set your Apple ID team under *Signing & Capabilities* to run on a device.

---

## Installing the unsigned IPA

An unsigned IPA can't install through Finder/iTunes. Pick one:

| Method | Notes |
| --- | --- |
| **Sideloadly** (macOS/Windows) | Free Apple ID, 7-day signature, drag-and-drop. |
| **AltStore / SideStore** | Refreshes the 7-day signature from your device. |
| **TrollStore** | Permanently signed on supported iOS versions. |
| **Xcode re-sign** | Open the generated project locally, set your team, archive & install — fully "proper" signing. |

iOS 17 requires **Developer Mode** (Settings → Privacy & Security) to launch sideloaded apps.

---

## How it works

### Data sources (public Toobit endpoints, verified live)

| What | Endpoint |
| --- | --- |
| Contract list | `GET https://api.toobit.com/api/v1/exchangeInfo` → `contracts[]` (filter `inverse == false`, `marginToken == "USDT"`, `status == "TRADING"`; tick size from `PRICE_FILTER`) |
| History candles | `GET https://api.toobit.com/quote/v1/klines?symbol=BTC-SWAP-USDT&interval=1m&limit=1000` → rows of `[openTime, open, high, low, close, volume, …]` |
| Live stream | `wss://stream.toobit.com/quote/ws/v1`, subscribe `{"symbol":"BTC-SWAP-USDT","topic":"realtimes","event":"sub","params":{"binary":false}}` |
| Heartbeat | send `{"ping": <epoch ms>}` every 20 s → server replies `{"pong": …}` |

Docs: <https://api-docs.toobit.com/api/usdt-m-market-data.html> and the websocket section of the same site. Toobit returns most quote numbers as JSON strings — the REST parser accepts both forms.

### Flow

1. `MarketSession` (an `ObservableObject`) starts the history seed and the socket immediately and loads the contract list in parallel — the chart never waits for the 780-contract `exchangeInfo`.
2. For the selected symbol + interval it fetches up to **1000 candles** and replays each one as *open → extreme → extreme → close* (bullish: low before high, bearish: high before low) through `RenkoEngine`. Replaying closes only would drop every intra-candle move that reverts before the close.
3. The WebSocket `realtimes` topic then pushes every last-traded price (`c`) — that tick feeds the engine live and updates the ticker bar. The newest price arriving while history is still seeding is buffered and applied afterwards.
4. Network resilience: 20 s JSON heartbeat doubles as a watchdog. If nothing arrives for 45 s the socket is torn down and the reconnect loop retries with 2 s → 15 s backoff, resubscribing automatically. **After a reconnect, or after more than 15 s in the background, history is re-seeded so bricks formed during the gap are backfilled.** Status shows as a pill (`LIVE` / `CONNECTING` / `RETRY #n`).

### Bias, chop and the scanner

All of this is computed once per *completed brick* (never per tick) in `Engine/RenkoAnalysis.swift`:

- **EMA 9 / 21** over the brick closes (first value = SMA of the first `period` bricks).
- **Chop** = direction flips ÷ (n − 1) over the last 20 bricks. 0 is a clean trend, 1 a pure zig-zag.
- **Bias**: `LONG` when the newest brick is up and EMA 9 > EMA 21, `SHORT` for the mirror image, otherwise `WAIT`. It also reads `WAIT` while fewer than 20 bricks exist or chop is above 50 %.

This is a transparent description of the series, not a backtested strategy. The scanner uses REST history only (4 requests at a time), so it works without extra sockets; rows are not live — pull down to rescan.

### Renko algorithm

Bricks are computed in **log-price space** with step `ln(1 + brickPercent)`, which is equivalent to "each brick is `brickPercent` of its anchor price":

- Continuation brick: price closes one step beyond the last brick's close.
- Reversal brick: price closes one step beyond the last brick's **open** (the classic two-brick swing).
- A single tick can stack multiple bricks (big moves); reversal bricks get a subtle outline.
- Because each brick derives its size from its own anchor, the size tracks the price level continuously — this is what makes "auto % of price" work.

The **interval selector** only affects the granularity of the history seed (1 m → 1 d); the live feed is always tick-level via the ticker stream.

### Project layout

```
project.yml                          # XcodeGen spec → ToobitRenko.xcodeproj
Sources/ToobitRenko/
  App/          ToobitRenkoApp.swift, RootView.swift
  Models/       Candle, RenkoBrick, TickerSnapshot, ContractInfo
  Networking/   ToobitREST (klines + exchangeInfo)
  Engine/       RenkoEngine (log-space percentage Renko), RenkoAnalysis (EMA, chop, bias)
  Services/     MarketSession (REST seed + WS feed + reconnect + watchlist), RenkoScanner
  Views/        RenkoChartView (Canvas), TickerBar, IntervalRow, SymbolPicker, StatsBar, ScannerView
  Support/      Theme, Formatters, Haptics
Package.swift                        # SwiftPM harness: compiles Engine + Models for `swift test`
Tests/RenkoCoreTests/                # engine + analysis unit tests
.github/workflows/build-ipa.yml      # unit tests + unsigned IPA CI
```

---

## Notes & limits

- Public endpoints only — the app never touches your Toobit account and holds no API keys.
- Backfill after a reconnect is as good as the candle granularity: bricks are rebuilt from the interval's candles (open / extreme / extreme / close), so a 1 m seed reproduces the gap closely but not tick-perfectly.
- iOS suspends the app in the background, so nothing can alert you while it is closed; there is no push channel. The watchlist scan is pull-based.
- Oldest bricks are trimmed beyond 4000 to keep memory flat; the chart window and stats are unaffected.
- **Not financial advice.** Renko is a visualization of price movement, not a signal.

## License

MIT — see [LICENSE](LICENSE).
