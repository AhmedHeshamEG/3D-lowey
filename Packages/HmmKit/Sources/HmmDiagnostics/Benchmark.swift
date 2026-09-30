import Foundation

/// What a benchmark run measured. Hesham runs it on the device after each phase and pastes the JSON back: CI can't
/// measure real GPU timing, so this file is the performance gate.
public struct BenchmarkReport: Codable, Hashable, Sendable {
    public var app: String
    public var appVersion: String
    public var scene: String
    public var device: String
    public var system: String
    public var date: Date
    public var seconds: Double
    public var frames: Int
    /// Milliseconds.
    public var p50: Double
    public var p95: Double
    public var p99: Double
    public var worst: Double
    public var budget: Double
    public var dropped: Int
    /// Frames over 33 ms.
    public var hitches: Int
    public var renderScaleMin: Double
    public var renderScaleMean: Double
    public var thermalWorst: ThermalLevel
    public var memoryPeakMB: Double
    /// The scene's own facts (objects, triangles, lights…).
    public var sceneFacts: [String: Double]
    /// The PROMPT's pass rule applied to this run.
    public var passed: Bool

    public var fileName: String {
        let deviceName = device.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        return "benchmark-\(deviceName)-\(appVersion).json"
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// A pass rule: p95 under a budget at a minimum render scale, with no hitches over 33 ms.
public struct BenchmarkTarget: Hashable, Sendable {
    public var p95Milliseconds: Double
    public var minimumRenderScale: Double
    public var maxHitches: Int

    public init(p95Milliseconds: Double, minimumRenderScale: Double, maxHitches: Int = 0) {
        self.p95Milliseconds = p95Milliseconds
        self.minimumRenderScale = minimumRenderScale
        self.maxHitches = maxHitches
    }

    public func passes(p95 milliseconds: Double, renderScaleMin: Double, hitches: Int) -> Bool {
        milliseconds <= p95Milliseconds && renderScaleMin >= minimumRenderScale && hitches <= maxHitches
    }
}

/// Collects one benchmark run: the host calls `frame(...)` once per presented frame, `finish` writes the report.
public struct BenchmarkRecorder: Sendable {
    public let duration: Double
    public let target: BenchmarkTarget
    public private(set) var stats: FrameStats
    public private(set) var scales: [Double] = []
    public private(set) var thermalWorst = ThermalLevel.nominal
    public private(set) var memoryPeakMB = 0.0
    private var start: Double?

    public init(duration: Double = 20, budget: Double = 1.0 / 120.0, target: BenchmarkTarget) {
        self.duration = duration
        self.target = target
        stats = FrameStats(window: 0, budget: budget)
    }

    /// Records a frame; returns true once the run is long enough.
    public mutating func frame(duration frameTime: Double, at time: Double, renderScale: Double, thermal: ThermalLevel,
                               memoryMB: Double) -> Bool {
        if start == nil { start = time }
        stats.record(duration: frameTime, at: time)
        scales.append(renderScale)
        thermalWorst = max(thermalWorst, thermal)
        memoryPeakMB = max(memoryPeakMB, memoryMB)
        return time - (start ?? time) >= duration
    }

    public var elapsed: Double {
        guard let start, let last = stats.samples.last else { return 0 }
        return last.time - start
    }

    public func report(app: String, appVersion: String, scene: String, device: String, system: String,
                       sceneFacts: [String: Double], date: Date = Date()) -> BenchmarkReport {
        let p95 = stats.p95 * 1000
        let scaleMin = scales.min() ?? 1
        let hitches = stats.hitches()
        return BenchmarkReport(
            app: app, appVersion: appVersion, scene: scene, device: device, system: system, date: date, seconds: elapsed,
            frames: stats.count, p50: stats.p50 * 1000, p95: p95, p99: stats.p99 * 1000, worst: stats.worst * 1000,
            budget: stats.budget * 1000, dropped: stats.dropped, hitches: hitches, renderScaleMin: scaleMin,
            renderScaleMean: scales.isEmpty ? 1 : scales.reduce(0, +) / Double(scales.count), thermalWorst: thermalWorst,
            memoryPeakMB: memoryPeakMB, sceneFacts: sceneFacts,
            passed: target.passes(p95: p95, renderScaleMin: scaleMin, hitches: hitches)
        )
    }
}
