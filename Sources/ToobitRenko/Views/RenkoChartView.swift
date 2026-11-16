import SwiftUI

/// Canvas-rendered Renko chart with pan / pinch zoom, price axis, time axis
/// and a dashed last-price line.
///
/// The view follows the newest bricks by default (`scrollBack == 0`); dragging
/// right/left scrolls back into history and a "Live" button appears to snap
/// back. Pinching changes how many bricks are visible.
struct RenkoChartView: View {
    let bricks: [RenkoBrick]
    let lastPrice: Double?
    let decimals: Int

    @State private var visibleCount: Double = 60
    @State private var scrollBack: Double = 0
    @State private var dragBase: Double?
    @State private var zoomBase: Double?

    private let axisWidth: CGFloat = 64
    private let timeAxisHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Canvas { context, canvasSize in
                    draw(&context, size: canvasSize, slice: currentSlice)
                }
                .contentShape(Rectangle())
                .gesture(
                    panGesture(chartWidth: chartWidth(for: geo.size))
                        .simultaneously(with: zoomGesture)
                )
                if scrollBack > 0.5 {
                    liveButton
                        .padding(.trailing, axisWidth + 8)
                }
            }
        }
        .clipped()
    }

    // MARK: - Windowing

    /// Brick width for the current visible count, used by the pan gesture.
    private func chartWidth(for size: CGSize) -> CGFloat {
        max(size.width - axisWidth, 10)
    }

    private var currentSlice: ArraySlice<RenkoBrick> {
        guard !bricks.isEmpty else { return bricks[0..<0] }
        let count = max(8, min(Int(visibleCount), bricks.count))
        let scrolled = Int(min(scrollBack, Double(max(0, bricks.count - 1))))
        let end = max(count, bricks.count - scrolled)
        let clampedEnd = min(end, bricks.count)
        let start = max(0, clampedEnd - count)
        return bricks[start..<max(start + 1, clampedEnd)]
    }

    private func panGesture(chartWidth width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragBase == nil { dragBase = scrollBack }
                let visible = CGFloat(max(8, min(Int(visibleCount), 10_000)))
                let step = Double(-value.translation.width / max(width / visible, 1))
                scrollBack = min(max((dragBase ?? 0) + step, 0),
                                 Double(max(0, bricks.count - 1)))
            }
            .onEnded { _ in dragBase = nil }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if zoomBase == nil { zoomBase = visibleCount }
                let base = zoomBase ?? visibleCount
                visibleCount = min(max(base / max(scale, 0.05), 10), 400)
            }
            .onEnded { _ in zoomBase = nil }
    }

    private var liveButton: some View {
        Button {
            scrollBack = 0
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                Text("Live")
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .foregroundColor(Theme.accent)
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, slice: ArraySlice<RenkoBrick>) {
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
        for (index, brick) in all.enumerated() {
            let x = CGFloat(index) * bw
            let yTop = yPos(brick.high)
            let yBottom = yPos(brick.low)
            let rect = CGRect(
                x: x + bw * 0.15,
                y: yTop,
                width: max(bw * 0.7, 1.2),
                height: max(yBottom - yTop, 1.4)
            )
            let path = Path(rect)
            context.fill(path, with: .color(brick.isUp ? Theme.up : Theme.down))
            if index > 0, all[index - 1].isUp != brick.isUp {
                context.stroke(path, with: .color(Theme.text.opacity(0.35)), lineWidth: 0.8)
            }
        }

        // Time labels under the chart, spread evenly.
        let span = all[all.count - 1].time.timeIntervalSince(all[0].time)
        let stride = max(1, all.count / 8)
        for (index, brick) in all.enumerated() where index % stride == 0 {
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
    }
}
