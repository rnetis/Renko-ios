import Foundation

/// A single completed Renko brick.
///
/// Bricks are the atomic unit of the chart: each one spans a fixed relative
/// price move (the brick size) and is colored by direction. `id` is a global
/// sequence number that survives trimming, so SwiftUI identity stays stable.
struct RenkoBrick: Identifiable, Equatable, Sendable {
    /// Sequential brick index (never reused, even after the oldest bricks are trimmed).
    let id: Int
    let open: Double
    let close: Double
    let isUp: Bool
    /// Time of the price observation that completed the brick.
    let time: Date

    var low: Double { min(open, close) }
    var high: Double { max(open, close) }
}
