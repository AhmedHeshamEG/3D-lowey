import Foundation
#if canImport(Metal)
    import Metal
#endif

/// How much preview a device keeps smooth (CONTEXT §6). Tiers lower preview quality, never features; exports always
/// render at full quality on every tier, just slower.
public enum DeviceTier: String, Codable, Sendable, CaseIterable, Comparable {
    /// M-series iPads: full quality.
    case a = "A"
    /// Recent A-series iPads (iPad, iPad mini): the same features with a lighter preview.
    case b = "B"
    /// The oldest supported iPads: lighter still.
    case c = "C"

    /// The GPU generation, as Metal reports it (`MTLGPUFamily.appleN`).
    public struct GPU: Hashable, Sendable {
        public var appleFamily: Int

        public init(appleFamily: Int) {
            self.appleFamily = appleFamily
        }
    }

    /// The tier for a GPU generation and the device's memory. M-series iPads have family 7 or later and at least
    /// 8 GB; A-series iPads of the same generation have 6 GB or less (the A17 Pro iPad mini, with 8 GB and an M1-class
    /// GPU, counts as A). Families before 7 (A12, A13) are C.
    public static func classify(gpu: GPU, memoryGB: Double) -> DeviceTier {
        if gpu.appleFamily >= 7, memoryGB >= 7.5 { return .a }
        if gpu.appleFamily >= 7 || memoryGB >= 4.5 { return .b }
        return .c
    }

    public static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The tier forced by `-device-tier B` (simulator configurations in CI, testing a lighter preview on an M iPad).
    public static func override(arguments: [String] = ProcessInfo.processInfo.arguments) -> DeviceTier? {
        guard let index = arguments.firstIndex(of: "-device-tier"), index + 1 < arguments.count else { return nil }
        return DeviceTier(rawValue: arguments[index + 1].uppercased())
    }

    #if canImport(Metal)
        /// This device's tier (or the forced one).
        public static func current(device: MTLDevice? = MTLCreateSystemDefaultDevice()) -> DeviceTier {
            if let forced = override() { return forced }
            let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
            return classify(gpu: GPU(appleFamily: device.map(appleFamily) ?? 0), memoryGB: memoryGB)
        }

        /// The newest `MTLGPUFamily.appleN` the device supports.
        public static func appleFamily(_ device: MTLDevice) -> Int {
            let families: [(MTLGPUFamily, Int)] = [(.apple9, 9), (.apple8, 8), (.apple7, 7), (.apple6, 6), (.apple5, 5), (.apple4, 4)]
            return families.first { device.supportsFamily($0.0) }?.1 ?? 0
        }
    #endif
}

/// The hidden load meter (CONTEXT §6): silent while the device keeps up, it says so *before* frames drop.
///
/// Feed it every frame's time and, now and then, the scene's estimated cost as a fraction of what this tier keeps
/// smooth. Pressure is the larger of the two (p95 frame time over budget, scene cost); the chip appears when pressure
/// stays at or above `showAt` for `settle` seconds and leaves when it stays under `hideAt` as long (no flicker).
public struct LoadMeter: Sendable, Equatable {
    public enum Level: String, Sendable, Equatable {
        /// Nothing to say.
        case comfortable
        /// Near the edge: the chip shows with its one-tap fixes.
        case approaching
        /// Over budget: frames are being dropped right now.
        case over
    }

    public var showAt = 0.85
    public var hideAt = 0.70
    public var settle = 1.0
    public private(set) var level: Level = .comfortable
    public private(set) var pressure = 0.0
    private var frames: FrameStats
    private var sceneCost = 0.0
    private var crossedAt: Double?
    private var lastEvaluation = -Double.infinity

    public init(budget: Double = 1.0 / 120.0, window: Double = 2) {
        frames = FrameStats(window: window, budget: budget)
    }

    /// The frame budget (1/120 s on ProMotion, 1/60 s elsewhere).
    public var budget: Double {
        get { frames.budget }
        set { frames.budget = newValue }
    }

    /// One frame's work in seconds (CPU encode + GPU, or the interval between presented frames).
    public mutating func record(frame duration: Double, at time: Double) {
        frames.record(duration: duration, at: time)
        // Percentiles sort the window: a few evaluations a second are plenty.
        guard time - lastEvaluation >= 0.25 else { return }
        lastEvaluation = time
        evaluate(at: time)
    }

    /// The scene's estimated cost for this device: 1 = exactly what it keeps smooth.
    public mutating func setSceneCost(_ cost: Double, at time: Double) {
        sceneCost = max(cost, 0)
        evaluate(at: time)
    }

    public mutating func reset() {
        frames.reset()
        level = .comfortable
        pressure = 0
        crossedAt = nil
    }

    private mutating func evaluate(at time: Double) {
        let framePressure = frames.count >= 10 ? frames.p95 / max(frames.budget, 1e-6) : 0
        pressure = max(framePressure, sceneCost)
        let desired: Level = if pressure >= 1.15 {
            .over
        } else if pressure >= showAt || (level != .comfortable && pressure >= hideAt) {
            .approaching
        } else {
            .comfortable
        }
        guard desired != level else {
            crossedAt = nil
            return
        }
        guard let crossed = crossedAt else {
            crossedAt = time
            return
        }
        if time - crossed >= settle {
            level = desired
            crossedAt = nil
        }
    }
}
