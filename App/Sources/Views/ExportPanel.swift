import LoweyCore
import LoweyRender
import SwiftUI

/// Export mode: videos (16:9 and 9:16 in one go), PNG sequences, frames, and 3D files.
struct ExportPanel: View {
    @Bindable var editor: EditorModel
    @State private var landscape = true
    @State private var portrait = true
    @State private var square = false
    @State private var longSide = 1920
    @State private var codec: VideoCodec = .h264
    @State private var format: ExportFormat = .video
    @State private var transparent = false
    @State private var useLoop = false
    @State private var working = false
    @State private var shareItems: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Export").font(.system(size: 22, weight: .bold, design: .rounded))
                video
                Divider().overlay(Theme.panelStroke)
                frame
                Divider().overlay(Theme.panelStroke)
                model
            }
            .padding(18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .panelStyle()
        .sheet(isPresented: Binding(get: { !shareItems.isEmpty }, set: { if !$0 { shareItems = [] } })) {
            ShareSheet(items: shareItems)
        }
    }

    // MARK: Video

    private var framings: [Framing] {
        [landscape ? Framing.landscape : nil, portrait ? .portrait : nil, square ? .square : nil].compactMap { $0 }
    }

    private var range: TimeRange {
        useLoop ? (editor.timeline.loop ?? TimeRange(start: 0, end: editor.timeline.duration)) : TimeRange(start: 0, end: editor.timeline.duration)
    }

    private var video: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Video")
            HStack {
                Toggle("16:9", isOn: $landscape).toggleStyle(.button)
                Toggle("9:16", isOn: $portrait).toggleStyle(.button)
                Toggle("1:1", isOn: $square).toggleStyle(.button)
            }
            .font(.system(size: 14, weight: .semibold))
            Picker("Size", selection: $longSide) {
                Text("HD").tag(1920)
                Text("4K").tag(3840)
            }
            .pickerStyle(.segmented)
            Picker("Format", selection: $format) {
                Text("Video").tag(ExportFormat.video)
                Text("PNG frames").tag(ExportFormat.pngSequence)
            }
            .pickerStyle(.segmented)
            if format == .video, !transparent {
                Picker("Codec", selection: $codec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Text(codec.title).tag(codec)
                    }
                }
                .pickerStyle(.segmented)
            }
            Toggle("Transparent background", isOn: $transparent).font(.system(size: 13))
            if editor.timeline.loop != nil {
                Toggle("Only the loop region", isOn: $useLoop).font(.system(size: 13))
            }
            let frames = Int((range.duration * Double(editor.timeline.fps)).rounded())
            Text("\(NumberFormat.short(range.duration)) s · \(editor.timeline.fps) fps · \(frames) frames × \(framings.count) framing\(framings.count == 1 ? "" : "s")"
                + (transparent && format == .video ? " · HEVC with alpha (.mov)" : ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            if let progress = editor.exportProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                    HStack {
                        Text("Rendering \(Int(progress * 100))% — keep working, it runs in the background")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        PillButton(title: "Cancel", destructive: true) { editor.cancelExport() }
                    }
                }
                .accessibilityIdentifier("export-progress")
            } else {
                PillButton(title: "Export video", systemName: "film", prominent: true) {
                    editor.exportVideo(VideoExportSettings(framings: framings, longSide: longSide, range: range, fps: editor.timeline.fps,
                                                           codec: codec, format: format, transparent: transparent))
                }
                .disabled(framings.isEmpty)
                .accessibilityIdentifier("export-video")
            }
            if !editor.exportResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(editor.exportResults, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "film")
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    HStack {
                        PillButton(title: "Share", systemName: "square.and.arrow.up") { shareItems = editor.exportResults }
                        if editor.exportResults.contains(where: { ["mp4", "mov"].contains($0.pathExtension) }) {
                            PillButton(title: "Save to Photos", systemName: "photo.on.rectangle") { editor.saveToPhotos(editor.exportResults) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Frame

    private var frame: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Single frame (PNG)")
            Picker("Framing", selection: $editor.snapshotFraming) {
                ForEach(Framing.allCases) { framing in
                    Text(framing.rawValue).tag(framing)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                PillButton(title: working ? "Rendering…" : "What I see", systemName: "camera.aperture") { snapshot(throughCamera: false) }
                    .accessibilityIdentifier("take-snapshot")
                if editor.shotCamera != nil {
                    PillButton(title: "Through the camera", systemName: "video") { snapshot(throughCamera: true) }
                }
            }
        }
    }

    private func snapshot(throughCamera: Bool) {
        guard !working else { return }
        working = true
        Task {
            if let url = await editor.exportSnapshot(framing: editor.snapshotFraming, longSide: longSide, throughCamera: throughCamera) {
                shareItems = [url]
            }
            working = false
        }
    }

    // MARK: 3D

    private var model: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "3D model")
            Text(editor.selection.isEmpty ? "The whole scene" : "The selection")
                .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            HStack {
                ForEach(ModelExportFormat.allCases) { format in
                    PillButton(title: format.title, systemName: "cube") {
                        if let url = editor.exportModel(format, selectionOnly: !editor.selection.isEmpty) { shareItems = [url] }
                    }
                }
            }
        }
    }
}
