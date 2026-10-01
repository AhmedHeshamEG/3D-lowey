#if canImport(SwiftUI)
    import HmmDesign
    import SwiftUI

    /// What the HUD shows (the host refreshes it a few times a second, not every frame).
    public struct PerformanceSnapshot: Equatable, Sendable {
        /// The last few seconds of frame times in milliseconds, oldest first.
        public var frameTimes: [Double]
        public var p50: Double
        public var p95: Double
        public var p99: Double
        public var dropped: Int
        public var fps: Double
        public var budget: Double
        public var thermal: ThermalLevel
        public var memoryMB: Double
        /// e.g. "Scale 0.85 · MetalFX"
        public var note: String

        public init(stats: FrameStats, thermal: ThermalLevel, memoryMB: Double, note: String = "") {
            frameTimes = stats.samples.suffix(240).map { $0.duration * 1000 }
            p50 = stats.p50 * 1000
            p95 = stats.p95 * 1000
            p99 = stats.p99 * 1000
            dropped = stats.dropped
            fps = stats.fps
            budget = stats.budget * 1000
            self.thermal = thermal
            self.memoryMB = memoryMB
            self.note = note
        }
    }

    /// The Performance HUD: a frame-time graph against the budget line, p50/p95/p99 over the last 5 s, dropped frames,
    /// thermal state and memory.
    public struct PerformanceHUD: View {
        private let snapshot: PerformanceSnapshot
        @Environment(\.hmmTheme) private var theme

        public init(_ snapshot: PerformanceSnapshot) {
            self.snapshot = snapshot
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                graph.frame(width: 220, height: 56)
                HStack(spacing: HmmSpacing.s) {
                    metric("fps", String(format: "%.0f", snapshot.fps))
                    metric("p50", String(format: "%.1f", snapshot.p50))
                    metric("p95", String(format: "%.1f", snapshot.p95), warn: snapshot.p95 > snapshot.budget)
                    metric("p99", String(format: "%.1f", snapshot.p99))
                }
                HStack(spacing: HmmSpacing.s) {
                    metric("dropped", "\(snapshot.dropped)", warn: snapshot.dropped > 0)
                    metric("thermal", snapshot.thermal.rawValue, warn: snapshot.thermal >= .serious)
                    metric("MB", String(format: "%.0f", snapshot.memoryMB))
                }
                if !snapshot.note.isEmpty {
                    Text(snapshot.note).font(.hmm(.caption)).foregroundStyle(theme.text2)
                }
            }
            .padding(HmmSpacing.s)
            .hmmPanelBackground(cornerRadius: HmmRadius.card)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("performance-hud")
        }

        private var graph: some View {
            Canvas { context, size in
                let ceiling = max(snapshot.budget * 4, 1)
                let budgetY = size.height * (1 - snapshot.budget / ceiling)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: budgetY))
                line.addLine(to: CGPoint(x: size.width, y: budgetY))
                context.stroke(line, with: .color(theme.success.opacity(0.7)), lineWidth: 1)
                let times = snapshot.frameTimes
                guard times.count > 1 else { return }
                let step = size.width / Double(times.count - 1)
                for (index, time) in times.enumerated() {
                    let height = min(time / ceiling, 1) * size.height
                    let bar = CGRect(x: Double(index) * step, y: size.height - height, width: max(step - 0.5, 0.5), height: height)
                    context.fill(Path(bar), with: .color(time > snapshot.budget * 1.5 ? theme.danger : theme.text2))
                }
            }
        }

        private func metric(_ label: String, _ value: String, warn: Bool = false) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.hmmNumbers(.footnote)).foregroundStyle(warn ? theme.warning : theme.text)
                Text(label).font(.hmm(.caption)).foregroundStyle(theme.text3)
            }
        }
    }
#endif
