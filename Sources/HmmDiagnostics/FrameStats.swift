import Foundation

/// Frame-time statistics over a sliding window (the HUD) or a whole run (the benchmark).
public struct FrameStats: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        /// When the frame finished (seconds, any monotonic clock).
        public var time: Double
        /// How long it took (seconds).
        public var duration: Double
    }

    /// Seconds kept (0 = keep everything).
    public var window: Double
    /// The frame budget in seconds (1/120 on ProMotion).
    public var budget: Double
    public private(set) var samples: [Sample] = []

    public init(window: Double = 5, budget: Double = 1.0 / 120.0) {
        self.window = window
        self.budget = budget
    }

    public mutating func record(duration: Double, at time: Double) {
        samples.append(Sample(time: time, duration: max(duration, 0)))
        guard window > 0, let first = samples.first, time - first.time > window else { return }
        let cutoff = time - window
        let firstKept = samples.firstIndex { $0.time >= cutoff } ?? samples.count
        samples.removeFirst(firstKept)
    }

    public mutating func reset() {
        samples.removeAll()
    }

    public var count: Int { samples.count }

    /// The `p`-th percentile (0…100) frame time in seconds (nearest rank).
    public func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.map(\.duration).sorted()
        let rank = Int((min(max(p, 0), 100) / 100 * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    public var p50: Double { percentile(50) }
    public var p95: Double { percentile(95) }
    public var p99: Double { percentile(99) }
    public var worst: Double { samples.map(\.duration).max() ?? 0 }
    public var mean: Double { samples.isEmpty ? 0 : samples.map(\.duration).reduce(0, +) / Double(samples.count) }

    /// Frames that missed the budget (took more than 1.5 budgets, i.e. at least one display refresh was lost).
    public var dropped: Int { samples.filter { $0.duration > budget * 1.5 }.count }

    /// Frames longer than `threshold` (33 ms by default): a hitch anyone can see.
    public func hitches(over threshold: Double = 0.033) -> Int {
        samples.filter { $0.duration > threshold }.count
    }

    /// Frames per second over the window.
    public var fps: Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return Double(samples.count - 1) / (last.time - first.time)
    }
}

/// The thermal state as the benchmark report writes it.
public enum ThermalLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }

    #if canImport(Darwin)
        public init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .serious
            }
        }

        public static var current: ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }
    #endif
}
