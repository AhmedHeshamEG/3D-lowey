import HmmDesign
import HmmDiagnostics
import LoweyCore
import LoweyEngine
import SwiftUI

/// Diagnostics: the Performance HUD, the Night Market benchmark (its JSON report is the performance gate), the
/// renderer's capabilities, and the log export. Nothing leaves the iPad unless you share it.
struct DiagnosticsSheet: View {
    let app: AppModel
    let editor: EditorModel?
    @AppStorage(AppSettings.showsPerformanceHUD) private var showsHUD = false
    @State private var sharing: [URL] = []
    @State private var runningBenchmark = false
    @State private var reports: [URL] = []
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("Diagnostics") {
            Toggle("Performance HUD over the stage", isOn: $showsHUD).font(.hmm(.headline, weight: .semibold))
            Hint("Frame times against the 120 fps budget, p50 / p95 / p99 over the last five seconds, dropped frames, heat and memory.")
            HmmSectionHeader("Benchmark")
            Hint("The Night Market: about 400 objects, six walking figures, four Blobs, lanterns and a slow dolly, for 20 seconds at full speed. "
                + "Pass: 95% of frames under 8.3 ms at render scale 0.85 or more, no hitch over 33 ms.")
            HmmPillButton("Run the benchmark", systemName: "speedometer", prominent: true) { runningBenchmark = true }
                .accessibilityIdentifier("run-benchmark")
            ForEach(reports, id: \.self) { url in
                HStack {
                    Label(url.lastPathComponent, systemImage: "doc.text").font(.hmm(.footnote)).lineLimit(1)
                    Spacer()
                    HmmButton("square.and.arrow.up", label: "Share \(url.lastPathComponent)", size: 32) { sharing = [url] }
                }
            }
            HmmSectionHeader("This iPad")
            Text(DiagnosticsCenter.deviceSummary).font(.hmm(.footnote)).foregroundStyle(theme.text2).textSelection(.enabled)
            Text((try? RenderDevice.sharedDevice().capabilities.summary) ?? "No Metal GPU").font(.hmm(.footnote)).foregroundStyle(theme.text2)
            HmmPillButton("Export logs", systemName: "stethoscope") {
                if let url = app.diagnostics.exportArchive(summary: summary) { sharing = [url] }
            }
            .accessibilityIdentifier("export-logs")
        }
        .onAppear(perform: loadReports)
        .fullScreenCover(isPresented: $runningBenchmark, onDismiss: loadReports) { BenchmarkRunView(diagnostics: app.diagnostics) }
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) { ShareSheet(items: sharing) }
    }

    private var summary: String {
        var lines = ["Projects: \(app.projects.count) · Library: \(app.library.manifest.assets.count) models, \(app.library.manifest.prefabs.count) builds"]
        if let editor {
            lines.append("Open scene: \(editor.baseScene.objects.count) objects, \(editor.timeline.tracks.count) tracks, \(editor.timeline.audio.count) sounds")
        }
        return lines.joined(separator: "\n")
    }

    private func loadReports() {
        let files = (try? FileManager.default.contentsOfDirectory(at: app.diagnostics.benchmarksFolder, includingPropertiesForKeys: nil)) ?? []
        reports = files.filter { $0.lastPathComponent.hasPrefix("benchmark-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

/// The Performance HUD in a corner of the stage.
struct PerformanceHUDOverlay: View {
    let monitor: PerformanceMonitor

    var body: some View {
        PerformanceHUD(monitor.snapshot)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 76)
            .padding(.leading, 72)
            .allowsHitTesting(false)
            .accessibilityIdentifier("performance-hud")
    }
}
