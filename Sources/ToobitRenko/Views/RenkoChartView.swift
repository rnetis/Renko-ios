import SwiftUI

/// Canvas-rendered Renko chart with pan / pinch zoom, price axis, time axis
/// and a dashed last-price line.
///
/// Interaction:
/// * drag — scroll through history; the chart follows the finger;
/// * pinch — change how many bricks are visible, up to the whole series;
/// * tap a brick — pin a crosshair and an exact readout (time, open, close, move);
///   tap the same brick again to dismiss it;
/// * **Fit** — zoom out until every kept brick is on screen;
/// * **Live** — snap back to the newest brick (shown while scrolled back);
/// * **EMA** — toggle the 9 / 21 EMA of brick closes.
///
/// While the newest brick is in view, two dotted lines mark the exact prices
/// at which the next up / down brick completes. While scrolled back, new
/// bricks no longer shift the window under the finger.
struct RenkoChartView: View {
    let bricks: [RenkoBrick]
    let analysis: RenkoAnalysis
    let triggers: PriceTriggers?
    let lastPrice: Double?
    let decimals: Int

    @State private var visibleCount: Double = 60
    @State private var scrollBack: Double = 0
    @State private var dragBase: Double?
    @State private var zoomBase: Double?
    /// `id` of the brick under the inspection crosshair. Ids survive trimming
    /// and appends, so the crosshair stays on the same brick as the feed moves.
    @State private var inspectedID: Int?
    @State private var showEMA = true

    private let axisWidth: CGFloat = 64
    private let timeAxisHeight: CGFloat = 20

    private var minVisible: Double { 10 }
    /// Fit-all ceiling: every brick the engine kept can be shown at once.
    private var maxVisible: Double { Double(max(10, bricks.count)) }

    var body: some View {
        GeometryReader { geo in
            let width = chartWidth(for: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    draw(&context, size: canvasSize, slice: currentSlice, isLive: scrollBack < 0.5)
                }
                .contentShape(Rectangle())
                .gesture(
                    panGesture(chartWidth: width)
                        .simultaneously(with: zoomGesture)
                )
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        inspect(at: value.location, chartWidth: width)
                    }
                )

                if let brick = inspectedBrick {
                    inspector(for: brick)
                        .padding(8)
                }

                HStack {
                    Spacer()
                    chartControls
                }
                .padding(.top, 6)
            }
        }
        .clipped()
        .onChange(of: bricks.last?.id) { old, new in
            // Keep the window anchored while scrolled back: every new brick
            // would otherwise slide the visible slice by one brick.
            guard scrollBack > 0, let old, let new, new > old else { return }
            scrollBack = min(scrollBack + Double(new - old), Double(max(0, bricks.count - 1)))
        }
    }

    // MARK: - Windowing

    /// Brick width for the current visible count, used by the pan gesture.
    private func chartWidth(for size: CGSize) -> CGFloat {
        max(size.width - axisWidth, 10)
    }

    private var currentSlice: ArraySlice<RenkoBrick> {
        guard !bricks.isEmpty else { return bricks[0..<0] }
        let count = max(8, min(Int(visibleCount.rounded()), bricks.count))
        let scrolled = Int(min(scrollBack, Double(max(0, bricks.count - 1))))
        let end = max(count, bricks.count - scrolled)
        let clampedEnd = min(end, bricks.count)
        let start = max(0, clampedEnd - count)
        return bricks[start..<max(start + 1, clampedEnd)]
    }

    private var inspectedBrick: RenkoBrick? {
        // Ids are contiguous (the engine only ever trims from the front).
        guard let id = inspectedID, let first = bricks.first else { return nil }
        let index = id - first.id
        guard bricks.indices.contains(index), bricks[index].id == id else { return nil }
        return bricks[index]
    }

    /// Resolves a tap to the brick under the finger and toggles the crosshair.
    private func inspect(at point: CGPoint, chartWidth width: CGFloat) {
        let slice = currentSlice
        guard !slice.isEmpty, width > 0,
              point.x >= 0, point.x < width else { return }
        let brickWidth = width / CGFloat(slice.count)
        let offset = min(max(Int(point.x / max(brickWidth, 0.0001)), 0), slice.count - 1)
        let brick = bricks[slice.startIndex + offset]
        inspectedID = inspectedID == brick.id ? nil : brick.id
    }

    /// Scrolling follows the finger: dragging right reveals older bricks.
    private func panGesture(chartWidth width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragBase == nil {
                    dragBase = scrollBack
                    inspectedID = nil
                }
                let visible = CGFloat(max(minVisible, min(visibleCount, 10_000)))
                let step = Double(value.translation.width / max(width / visible, 1))
                scrollBack = min(max((dragBase ?? 0) + step, 0),
                                 Double(max(0, bricks.count - 1)))
            }
            .onEnded { _ in dragBase = nil }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if zoomBase == nil {
                    zoomBase = visibleCount
                    inspectedID = nil
                }
                let base = zoomBase ?? visibleCount
                visibleCount = min(max(base / max(scale, 0.05), minVisible), maxVisible)
            }
            .onEnded { _ in zoomBase = nil }
    }

    // MARK: - Overlay controls

    private var chartControls: some View {
        HStack(spacing: 6) {
            if scrollBack > 0.5 {
                control("Live", systemImage: "arrow.right") {
                    scrollBack = 0
                }
            }
            control("EMA", systemImage: "waveform.path.ecg") {
                showEMA.toggle()
            }
            .opacity(showEMA ? 1 : 0.5)
            control("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                visibleCount = maxVisible
                scrollBack = 0
                inspectedID = nil
            }
        }
        .padding(.trailing, axisWidth + 8)
    }

    private func control(_ title: String,
                         systemImage: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .foregroundColor(Theme.accent)
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func inspector(for brick: RenkoBrick) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(brick.isUp ? Theme.up : Theme.down)
                    .frame(width: 6, height: 6)
                Text(brick.isUp ? "UP" : "DOWN")
                    .foregroundColor(brick.isUp ? Theme.up : Theme.down)
                Text(Format.exact(brick.time))
                    .foregroundColor(Theme.secondary)
            }
            row("O", Format.price(brick.open, decimals: decimals))
            row("C", Format.price(brick.close, decimals: decimals))
            row("D", Format.signed(brick.close / brick.open - 1))
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface.opacity(0.95)))
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.grid, lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(key).foregroundColor(Theme.secondary)
            Text(value).foregroundColor(Theme.text)
        }
    }

    // MARK: - Drawing

    /// Polyline of an EMA series over the visible slice (indices are global,
    /// matching `bricks`; `nil` entries break the line).
    private func emaPath(_ series: [Double?],
                         range: Range<Int>,
                         brickWidth: CGFloat,
                         y: (Double) -> CGFloat) -> Path {
        var path = Path()
        var started = false
        for global in range {
            guard global < series.count, let value = series[global] else {
                started = false
                continue
            }
            let point = CGPoint(x: CGFloat(global - range.lowerBound) * brickWidth + brickWidth / 2,
                                y: y(value))
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        return path
    }

    private func draw(_ context: inout GraphicsContext,
                      size: CGSize,
                      slice: ArraySlice<RenkoBrick>,
                      isLive: Bool) {
        let all = Array(slice)
        guard !all.isEmpty, size.width > axisWidth + 20, size.height > timeAxisHeight + 20 else { return }

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.background))

        let chartW = size.width - axisWidth
        let chartH = size.height - timeAxisHeight
        let count = CGFloat(all.count)
        let bw = chartW / count

        var lowBound = all.map(\.low).min() ?? 0
        var highBound = all.map(\.high).max() ?? 1
        if let lp = lastPrice {
            lowBound = min(lowBound, lp)
            highBound = max(highBound, lp)
        }
        // Keep the next-brick trigger levels on screen while following the feed.
        if isLive, let t = triggers {
            lowBound = min(lowBound, t.down)
            highBound = max(highBound, t.up)
        }
        if highBound <= lowBound {
            highBound = lowBound + max(1, lowBound * 0.001)
        }
        let pad = (highBound - lowBound) * 0.10
        lowBound -= pad
        highBound += pad

        func yPos(_ price: Double) -> CGFloat {
            chartH * CGFloat((highBound - price) / (highBound - lowBound))
        }

        // Horizontal grid + right-side price labels.
        let levels = 6
        for i in 0...levels {
            let fraction = Double(i) / Double(levels)
            let price = highBound - (highBound - lowBound) * fraction
            let y = yPos(price)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: chartW, y: y))
            context.stroke(line, with: .color(Theme.grid.opacity(0.6)), lineWidth: 0.5)
            let label = Format.price(price, decimals: decimals)
            context.draw(
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.secondary),
                at: CGPoint(x: chartW + axisWidth / 2, y: y)
            )
        }

        // Bricks. Reversal bricks get a subtle outline so trend flips stand out.
        // When zoomed far out the gap is dropped so every brick stays visible
        // instead of blurring into an overlapping band.
        let inset = bw > 4 ? bw * 0.15 : 0
        for (index, brick) in all.enumerated() {
            let x = CGFloat(index) * bw
            let yTop = yPos(brick.high)
            let yBottom = yPos(brick.low)
            let rect = CGRect(
                x: x + inset,
                y: yTop,
                width: max(bw - inset * 2, 1),
                height: max(yBottom - yTop, 1.2)
            )
            let path = Path(rect)
            context.fill(path, with: .color(brick.isUp ? Theme.up : Theme.down))
            if index > 0, all[index - 1].isUp != brick.isUp {
                context.stroke(path, with: .color(Theme.text.opacity(0.35)), lineWidth: 0.8)
            }
        }

        // EMA overlay on brick closes (series is aligned with `bricks`).
        if showEMA, analysis.emaFast.count == bricks.count {
            let range = slice.startIndex..<slice.endIndex
            context.stroke(
                emaPath(analysis.emaSlow, range: range, brickWidth: bw, y: yPos),
                with: .color(Theme.emaSlow.opacity(0.9)),
                lineWidth: 1.2
            )
            context.stroke(
                emaPath(analysis.emaFast, range: range, brickWidth: bw, y: yPos),
                with: .color(Theme.emaFast.opacity(0.9)),
                lineWidth: 1.2
            )
        }

        // Exact prices at which the next up / down brick completes.
        if isLive, let t = triggers {
            let triggerLevels: [(Double, Color, String)] = [(t.up, Theme.up, "▲"), (t.down, Theme.down, "▼")]
            for (price, color, glyph) in triggerLevels {
                let y = yPos(price)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: chartW, y: y))
                context.stroke(
                    line,
                    with: .color(color.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [2, 4])
                )
                context.draw(
                    Text("\(glyph) \(Format.price(price, decimals: decimals))")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(color.opacity(0.9)),
                    at: CGPoint(x: 4, y: y + (price == t.up ? 8 : -8)),
                    anchor: .leading
                )
            }
        }

        // Time labels under the chart, spread evenly.
        let span = all[all.count - 1].time.timeIntervalSince(all[0].time)
        let labelStride = max(1, all.count / 8)
        for (index, brick) in all.enumerated() where index % labelStride == 0 {
            let x = CGFloat(index) * bw + bw / 2
            guard x < chartW - 4 else { continue }
            context.draw(
                Text(Format.axisTime(brick.time, span: span))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.secondary.opacity(0.9)),
                at: CGPoint(x: x, y: chartH + timeAxisHeight / 2)
            )
        }

        // Dashed last-price line + gold pill on the axis.
        if let lp = lastPrice {
            let y = yPos(lp)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: chartW, y: y))
            context.stroke(
                line,
                with: .color(Theme.accent.opacity(0.8)),
                style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])
            )
            // Canvas can only draw text, images and resolved symbols — not
            // arbitrary views — so the pill background is a path and the
            // label is a resolved (re-shaded) Text.
            var label = context.resolve(
                Text(Format.price(lp, decimals: decimals))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            )
            let textSize = label.measure(in: CGSize(width: axisWidth, height: timeAxisHeight))
            let pillHeight = textSize.height + 4
            let pillWidth = min(textSize.width + 10, axisWidth - 4)
            let pillRect = CGRect(
                x: chartW + 2,
                y: y - pillHeight / 2,
                width: pillWidth,
                height: pillHeight
            )
            context.fill(
                Path(roundedRect: pillRect, cornerRadius: 3),
                with: .color(Theme.accent)
            )
            label.shading = .color(Theme.background)
            context.draw(label, at: CGPoint(x: pillRect.midX, y: pillRect.midY))
        }

        // Inspection crosshair: vertical marker, close-price line and outline.
        if let id = inspectedID {
            if let local = all.firstIndex(where: { $0.id == id }) {
                let brick = all[local]
                let x = CGFloat(local) * bw + bw / 2
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: chartH))
                context.stroke(
                    vertical,
                    with: .color(Theme.text.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                )
                let yClose = yPos(brick.close)
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: yClose))
                horizontal.addLine(to: CGPoint(x: chartW, y: yClose))
                context.stroke(
                    horizontal,
                    with: .color(Theme.text.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                )
                let highlight = CGRect(
                    x: x - bw / 2 + inset,
                    y: yPos(brick.high),
                    width: max(bw - inset * 2, 1),
                    height: max(yClose - yPos(brick.high), 1.2)
                )
                context.stroke(
                    Path(highlight),
                    with: .color(Theme.text),
                    lineWidth: 1
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 2, y: yClose - 2, width: 4, height: 4)),
                    with: .color(Theme.text)
                )
            }
        }
    }
}
