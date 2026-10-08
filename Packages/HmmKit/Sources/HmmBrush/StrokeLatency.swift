import Foundation

/// How long a Pencil sample takes to reach the screen (touch timestamp → the frame showing it), in milliseconds:
/// the brush engine's latency, kept for the last strokes and shown in Diagnostics. The device checklist records it.
public struct StrokeLatency: Equatable, Sendable {
    /// The most recent samples kept.
    public static let capacity = 1200
    public private(set) var samples: [Double] = []

    public init() {}

    public mutating func add(_ milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1000 else { return }
        samples.append(milliseconds)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public var median: Double? { percentile(0.5) }
    public var p95: Double? { percentile(0.95) }

    /// The value below which `fraction` of the samples fall (nearest rank).
    public func percentile(_ fraction: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    /// "11.8 ms median · 15.2 ms p95 · 340 samples", or nil before the first stroke.
    public var summary: String? {
        guard let median, let p95 else { return nil }
        return String(format: "%.1f ms median · %.1f ms p95 · %d samples", median, p95, samples.count)
    }
}
