import HmmDesign
import HmmMedia
import LoweyCore
import LoweyEngine
import SwiftUI

/// Export: pick a preset (YouTube 4K, 1080p, Shorts / Reels, Square, Transparent, PNG still, GIF loop, 3D, captions)
/// or set your own. It renders in the background with the stage still usable, carries on when you leave the app, and
/// every video is checked before it counts as done.
struct ExportSheet: View {
    @Bindable var editor: EditorModel
    @State private var preset: ExportPreset = .hd1080
    @State private var custom = false
    @State private var settings = ExportPreset.hd1080.settings(range: TimeRange(start: 0, end: 1), fps: 30)
    @State private var onlyLoop = false
    @State private var sharing: [URL] = []
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("Export") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: HmmSpacing.xs)], spacing: HmmSpacing.xs) {
                ForEach(ExportPreset.allCases) { item in
                    TileButton(title: item.title, systemName: item.systemImage, identifier: "export-\(item.rawValue)") { choose(item) }
                        .overlay(RoundedRectangle(cornerRadius: HmmRadius.card).stroke(theme.accent, lineWidth: preset == item ? 2 : 0))
                }
            }
            if preset.kind == .video || preset.kind == .gif {
                Toggle("Custom size, frame rate and quality", isOn: $custom)
                if custom { customControls }
                if editor.timeline.loop != nil { Toggle("Only the loop", isOn: $onlyLoop) }
            }
            Text(LocalizedStringKey(summary)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            progressOrStart
            results
        }
        .onAppear { choose(preset) }
        .onChange(of: onlyLoop) { _, _ in settings.range = range }
        .sheet(isPresented: Binding(get: { !sharing.isEmpty }, set: { if !$0 { sharing = [] } })) { ShareSheet(items: sharing) }
    }

    private var range: TimeRange {
        onlyLoop ? (editor.timeline.loop ?? TimeRange(start: 0, end: editor.timeline.duration)) : TimeRange(start: 0, end: editor.timeline.duration)
    }

    private func choose(_ item: ExportPreset) {
        preset = item
        settings = item.settings(range: range, fps: editor.timeline.fps)
        settings.framing = item == .vertical ? .portrait : (item == .square ? .square : settings.framing)
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Picker("Shape", selection: $settings.framing) {
                ForEach(Framing.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Size", selection: $settings.longSide) {
                Text("720p").tag(1280)
                Text("1080p").tag(1920)
                Text("4K").tag(3840)
            }
            .pickerStyle(.segmented)
            Picker("Frame rate", selection: $settings.fps) {
                ForEach(ExportSettings.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .pickerStyle(.segmented)
            if !settings.transparent {
                Picker("Codec", selection: $settings.codec) {
                    Text("H.264").tag(VideoCodecKind.h264)
                    Text("HEVC").tag(VideoCodecKind.hevc)
                }
                .pickerStyle(.segmented)
            }
            LabeledSlider(title: "Quality", value: settings.quality, range: 0.1 ... 1, format: NumberFormat.percent) { settings.quality = $0 }
        }
    }

    private var summary: String {
        switch preset.kind {
        case .video, .gif:
            let size = settings.size
            return "\(size.width) × \(size.height) · \(settings.fps) fps · \(NumberFormat.short(settings.range.duration)) s · \(settings.frameCount) frames"
                + (settings.transparent ? " · HEVC with alpha (.mov)" : "")
        case .still: return "The frame at the playhead, through the shot camera, as a PNG."
        case .model: return editor.selection.isEmpty ? "The whole scene as a glTF (.glb)." : "The selection as a glTF (.glb)."
        case .captions: return "Subtitles (.srt and .vtt) from the transcript."
        }
    }

    @ViewBuilder private var progressOrStart: some View {
        if let progress = editor.exportProgress {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                ProgressView(value: progress)
                HStack {
                    Text(editor.exportWaiting ? "Waiting while the app is in the background. It carries on when you're back."
                        : "Rendering \(Int(progress * 100))%. You can keep working.")
                        .font(.hmm(.footnote)).foregroundStyle(editor.exportWaiting ? theme.accent : theme.text2)
                    Spacer()
                    HmmPillButton("Cancel", role: .destructive) { editor.cancelExport() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("export-progress")
        } else {
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Export", systemName: "square.and.arrow.up", prominent: true) {
                    editor.startExport(preset.kind, settings: settings, title: preset.title)
                }
                .accessibilityIdentifier("export-start")
                if preset.kind == .video {
                    HmmPillButton("PNG frames instead", systemName: "photo.stack") { editor.exportPNGSequence(settings) }
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if !editor.exportResults.isEmpty {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                ForEach(editor.exportResults, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "doc").font(.hmm(.footnote)).lineLimit(1)
                }
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Share", systemName: "square.and.arrow.up") { sharing = editor.exportResults }
                    HmmPillButton("Save to Photos", systemName: "photo.on.rectangle") { editor.saveToPhotos(editor.exportResults) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("export-results")
        }
    }
}
