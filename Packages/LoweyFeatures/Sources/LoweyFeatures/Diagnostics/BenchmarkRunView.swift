import HmmDesign
import HmmDiagnostics
import LoweyCore
import LoweyEngine
import SwiftUI
import UIKit

/// The benchmark, full screen: the Night Market plays on its own stage for 20 seconds, every presented frame is
/// recorded, then the report is written and shown.
struct BenchmarkRunView: View {
    let diagnostics: DiagnosticsCenter
    /// The preview tier to run with (Tier B on any iPad shows how a recent A-chip iPad will feel).
    var tier: DeviceTier = PreviewQuality.current.tier
    @State private var report: BenchmarkReport?
    @State private var file: URL?
    @State private var failed: String?
    @State private var sharing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if report == nil, failed == nil {
                BenchmarkStage(tier: tier) { result in
                    switch result {
                    case let .success(made):
                        report = made
                        file = try? MarketBenchmark.write(made, to: diagnostics.benchmarksFolder)
                        diagnostics.log("Benchmark: p95 \(String(format: "%.2f", made.p95)) ms, passed \(made.passed)")
                    case let .failure(error):
                        failed = String(describing: error)
                    }
                }
                .ignoresSafeArea()
                Text("Benchmark running… keep your hands off for 20 seconds")
                    .font(.hmm(.footnote, weight: .semibold))
                    .padding(HmmSpacing.s)
                    .hmmGlass(in: Capsule(), interactive: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, HmmSpacing.l)
            } else {
                result
            }
        }
        .sheet(isPresented: $sharing) { if let file { ShareSheet(items: [file]) } }
        .statusBarHidden()
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            if let report {
                Text(report.passed ? "Passed" : "Not there yet").font(.hmm(.title1, weight: .semibold))
                    .foregroundStyle(report.passed ? theme.success : theme.warning)
                Group {
                    Text(String(format: "p50 %.2f ms · p95 %.2f ms · p99 %.2f ms · worst %.1f ms", report.p50, report.p95, report.p99, report.worst))
                    Text("\(report.frames) frames in \(String(format: "%.1f", report.seconds)) s · \(report.hitches) hitches · \(report.dropped) dropped")
                    Text(String(format: "Render scale: min %.2f, mean %.2f · heat: %@ · memory peak %.0f MB", report.renderScaleMin, report.renderScaleMean,
                                report.thermalWorst.rawValue, report.memoryPeakMB))
                }
                .font(.hmmNumbers(.body, weight: .regular))
                HmmPillButton("Share the report", systemName: "square.and.arrow.up", prominent: true) { sharing = true }
                    .disabled(file == nil)
                    .accessibilityIdentifier("share-benchmark")
            } else if let failed {
                Text("The benchmark couldn't run").font(.hmm(.title2, weight: .semibold))
                Text(failed).font(.hmm(.body)).foregroundStyle(theme.text2)
            }
            HmmPillButton("Done") { dismiss() }
        }
        .padding(HmmSpacing.xl)
        .frame(maxWidth: 560)
        .hmmPanelBackground()
        .padding(HmmSpacing.l)
    }
}

/// The benchmark's own stage view.
private struct BenchmarkStage: UIViewRepresentable {
    let tier: DeviceTier
    let finished: (Result<BenchmarkReport, Error>) -> Void

    func makeCoordinator() -> Holder { Holder() }

    func makeUIView(context: Context) -> UIView {
        do {
            let stage = try StageView(device: RenderDevice.sharedDevice(), quality: PreviewQuality(tier: tier))
            let fps = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.maximumFramesPerSecond ?? 60
            let benchmark = MarketBenchmark(tier: tier, budget: 1 / Double(max(fps, 30)))
            context.coordinator.benchmark = benchmark
            stage.showsGrid = false
            stage.frameSource = { stage in
                let scale = stage.contentScaleFactor
                return benchmark.frame(size: CGSize(width: stage.bounds.width * scale, height: stage.bounds.height * scale),
                                       renderScale: stage.dynamicScale.scale)
            }
            let holder = context.coordinator
            stage.onFrameTime = { [weak stage] _, total, scale in
                guard let stage, !holder.done, benchmark.record(frameTime: total, renderScale: scale, report: stage.lastReport) else { return }
                holder.done = true
                stage.isContinuous = false
                stage.frameSource = nil
                finished(.success(benchmark.report(appVersion: AppIdentity.shortVersion, device: DiagnosticsCenter.deviceModel,
                                                   system: "iPadOS \(UIDevice.current.systemVersion)")))
            }
            stage.isContinuous = true
            return stage
        } catch {
            Task { @MainActor in finished(.failure(error)) }
            return UIView()
        }
    }

    func updateUIView(_: UIView, context _: Context) {}

    final class Holder {
        var benchmark: MarketBenchmark?
        var done = false
    }
}
