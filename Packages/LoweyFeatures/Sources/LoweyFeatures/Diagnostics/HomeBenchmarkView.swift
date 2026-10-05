import HmmDesign
import HmmDiagnostics
import LoweyCore
import LoweyEngine
import QuartzCore
import SwiftUI
import UIKit

/// The Home benchmark: a hundred projects in a scratch folder (clones of the welcome island and its card, so they
/// take no space), the real gallery grid scrolled to the bottom and back at a steady speed for 20 s with every card
/// on screen turning, every presented frame recorded. The pass rule is the Night Market's: no dropped frame in 19 of
/// 20, no hitch. The JSON sits beside the Night Market's.
struct HomeBenchmarkView: View {
    let diagnostics: DiagnosticsCenter
    @State private var gallery: AppModel?
    @State private var scratch: URL?
    @State private var outcome: Outcome?
    @State private var position = ScrollPosition(edge: .top)
    @State private var driver = HomeScrollDriver()
    @State private var range: CGFloat = 0
    @State private var sharing = false
    @Namespace private var zoom
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    static let projects = 100

    enum Outcome {
        case finished(BenchmarkReport, URL?)
        case failed(String)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let outcome {
                result(outcome)
            } else if let gallery {
                ScrollView {
                    GalleryGrid(entries: gallery.gallery.entries(gallery.galleryItems), zoom: zoom, playing: true, selected: nil,
                                projectMenu: { _ in EmptyView() }, stackMenu: { _ in EmptyView() })
                        .padding(HmmSpacing.xl)
                }
                .scrollPosition($position)
                .scrollDisabled(true)
                .onScrollGeometryChange(for: CGFloat.self) { max($0.contentSize.height - $0.containerSize.height, 0) } action: { _, value in
                    range = value
                }
                .environment(gallery)
                .overlay(alignment: .top) { banner("Home benchmark running… keep your hands off for 20 seconds") }
                .onAppear(perform: run)
            } else {
                ProgressView("Making \(Self.projects) projects…").accessibilityIdentifier("home-benchmark-preparing")
            }
        }
        .task { await prepare() }
        .onDisappear(perform: cleanUp)
        .sheet(isPresented: $sharing) {
            if case let .finished(_, file?) = outcome { ShareSheet(items: [file]) }
        }
        .statusBarHidden()
    }

    private func banner(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.hmm(.footnote, weight: .semibold))
            .padding(HmmSpacing.s)
            .hmmGlass(in: Capsule(), interactive: false)
            .padding(.top, HmmSpacing.l)
    }

    /// One real project with its card, then clones of it.
    private func prepare() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("home-benchmark-\(UUID().uuidString)")
        scratch = folder
        let model = AppModel(projects: folder.appendingPathComponent("Projects"), library: folder.appendingPathComponent("Library"))
        model.library.load()
        do {
            let (info, scenes) = try Showcase.island(kit: model.library.manifest.kit, ids: .random)
            let url = try model.projectStore.writeProject(info: info, scenes: scenes)
            let document = try model.projectStore.openDocument(at: url)
            await model.drawCard(EditorModel.CardJob(document: document, viewpoint: document.scene.viewpoint, projectURL: url))
            for _ in 1 ..< Self.projects {
                _ = try model.projectStore.duplicateProject(at: url)
            }
            model.refreshProjects()
            gallery = model
        } catch {
            outcome = .failed(String(describing: error))
        }
    }

    private func run() {
        let fps = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.maximumFramesPerSecond ?? 60
        driver.start(fps: fps) { progress in
            // Down to the bottom and back up, at one steady speed.
            let along = progress < 0.5 ? progress * 2 : (1 - progress) * 2
            position.scrollTo(y: range * along)
        } finished: { recorder in
            let report = recorder.report(app: AppIdentity.displayName, appVersion: AppIdentity.shortVersion, scene: "Home, \(Self.projects) projects",
                                         device: DiagnosticsCenter.deviceModel, system: "iPadOS \(UIDevice.current.systemVersion)",
                                         sceneFacts: ["projects": Double(Self.projects), "fps": Double(fps)])
            let file = try? Self.write(report, to: diagnostics.benchmarksFolder)
            diagnostics.log("Home benchmark: p95 \(String(format: "%.2f", report.p95)) ms, passed \(report.passed)")
            outcome = .finished(report, file)
            cleanUp()
        }
    }

    static func write(_ report: BenchmarkReport, to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(report.fileName.replacingOccurrences(of: "benchmark-", with: "benchmark-home-"))
        try report.json().write(to: url, options: .atomic)
        return url
    }

    private func cleanUp() {
        driver.stop()
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
    }

    private func result(_ outcome: Outcome) -> some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            switch outcome {
            case let .finished(report, file):
                Text(report.passed ? "Passed" : "Not there yet").font(.hmm(.title1, weight: .semibold))
                    .foregroundStyle(report.passed ? theme.success : theme.warning)
                Text(String(format: "p50 %.2f ms · p95 %.2f ms · p99 %.2f ms · worst %.1f ms", report.p50, report.p95, report.p99, report.worst))
                    .font(.hmmNumbers(.body, weight: .regular))
                Text("\(report.frames) frames in \(String(format: "%.1f", report.seconds)) s · \(report.hitches) hitches · \(report.dropped) dropped")
                    .font(.hmmNumbers(.body, weight: .regular))
                    .accessibilityIdentifier("home-benchmark-frames")
                HmmPillButton("Share the report", systemName: "square.and.arrow.up", prominent: true) { sharing = true }
                    .disabled(file == nil)
            case let .failed(message):
                Text("The benchmark couldn't run").font(.hmm(.title2, weight: .semibold))
                Text(message).font(.hmm(.body)).foregroundStyle(theme.text2)
            }
            HmmPillButton("Done") { dismiss() }
                .accessibilityIdentifier("home-benchmark-done")
        }
        .padding(HmmSpacing.xl)
        .frame(maxWidth: 560)
        .hmmPanelBackground()
        .padding(HmmSpacing.l)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-benchmark-result")
    }
}

/// Moves the gallery once per display refresh and records the time between presented frames.
@MainActor
final class HomeScrollDriver: NSObject {
    private var link: CADisplayLink?
    private var started: CFTimeInterval?
    private var last: CFTimeInterval?
    private var recorder = BenchmarkRecorder(target: BenchmarkTarget(p95Milliseconds: 10, minimumRenderScale: 0))
    private var step: (Double) -> Void = { _ in }
    private var finished: (BenchmarkRecorder) -> Void = { _ in }
    static let duration = 20.0

    func start(fps: Int, step: @escaping (Double) -> Void, finished: @escaping (BenchmarkRecorder) -> Void) {
        stop()
        let budget = 1 / Double(max(fps, 30))
        // The Night Market's rule: a frame within 1.2 refreshes at the 95th percentile, no hitch.
        let target = BenchmarkTarget(p95Milliseconds: (budget * 1.2 * 10000).rounded() / 10, minimumRenderScale: 0)
        recorder = BenchmarkRecorder(duration: Self.duration, budget: budget, target: target)
        self.step = step
        self.finished = finished
        started = nil
        last = nil
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(min(fps, 80)), maximum: Float(fps), preferred: Float(fps))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if started == nil { started = now }
        let elapsed = now - (started ?? now)
        step(min(elapsed / Self.duration, 1))
        defer { last = now }
        guard let last else { return }
        let done = recorder.frame(duration: now - last, at: now, renderScale: 1, thermal: .current, memoryMB: MarketBenchmark.memoryFootprintMB())
        if done {
            stop()
            finished(recorder)
        }
    }
}
