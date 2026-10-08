import HmmDesign
import LoweyCore
import SwiftUI

/// The timeline under the stage (Procreate Dreams grammar): transport and timecode, Compose · Perform · Keyframe,
/// the ruler with markers and loop, the camera's shots, sound and words, effects, one row per animated object
/// (unfolding into property rows). Pinch to zoom time.
struct TimelinePane: View {
    @Bindable var editor: EditorModel
    @State private var layout: TimelineLayout?
    @State private var renamingMarker: Marker?
    @State private var markerName = ""
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            TimelineHeader(editor: editor, fit: { layout?.fit(width: layout?.laneWidth ?? 600) })
                .padding(.horizontal, HmmSpacing.s)
                .padding(.vertical, HmmSpacing.xs)
            Divider().overlay(theme.line)
            if let layout {
                GeometryReader { geometry in
                    let width = max(geometry.size.width - TimelineLayout.labelWidth, 50)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text(editor.timelineMode == .compose ? "Animations" : "Tracks")
                                .font(.hmm(.caption, weight: .semibold))
                                .foregroundStyle(theme.text2)
                                .frame(width: TimelineLayout.labelWidth)
                            TimelineRuler(editor: editor, layout: layout, width: width) { marker in
                                markerName = marker.name
                                renamingMarker = marker
                            }
                        }
                        .frame(height: TimelineLayout.rulerHeight)
                        let takes = TakesStrip.height(for: editor)
                        if takes > 0 { TakesStrip(editor: editor, width: width).frame(height: takes) }
                        TimelineLanes(editor: editor, layout: layout, width: width,
                                      height: max(geometry.size.height - TimelineLayout.rulerHeight - takes, 0))
                    }
                    .overlay(alignment: .topLeading) {
                        PlayheadLine(editor: editor, width: width, height: geometry.size.height)
                    }
                    .gesture(zoomGesture(layout, width: width))
                    .onAppear {
                        layout.laneWidth = width
                        layout.fit(width: width)
                    }
                    .onChange(of: width) { _, newWidth in layout.laneWidth = newWidth }
                    .onDisappear {
                        layout.momentum.stop()
                        layout.rowMomentum.stop()
                    }
                }
            }
        }
        .background(theme.surface)
        .onAppear { if layout == nil { layout = TimelineLayout(editor: editor) } }
        .sheet(item: Binding(get: { editor.graphKey.map(IdentifiedKey.init) }, set: { editor.graphKey = $0?.key })) { item in
            GraphEditorSheet(editor: editor, key: item.key).presentationDetents([.medium, .large])
        }
        .alert("Marker", isPresented: Binding(get: { renamingMarker != nil }, set: { if !$0 { renamingMarker = nil } })) {
            TextField("Name (a word from the script)", text: $markerName)
            Button("Save") {
                if let marker = renamingMarker { editor.renameMarker(marker.id, to: markerName) }
                renamingMarker = nil
            }
            Button("Delete", role: .destructive) {
                if let marker = renamingMarker { editor.removeMarker(marker.id) }
                renamingMarker = nil
            }
            Button("Cancel", role: .cancel) { renamingMarker = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline")
    }

    /// Pinch: the moment under the fingers stays under the fingers.
    private func zoomGesture(_ layout: TimelineLayout, width: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if layout.zoomStart == nil {
                    layout.momentum.stop()
                    layout.zoomStart = editor.timelineZoom
                    let anchorX = max(value.startLocation.x - TimelineLayout.labelWidth, 0)
                    layout.zoomAnchor = (layout.time(at: anchorX), anchorX)
                }
                let minimum = Double(width) / max(editor.timeline.duration, 1) * 0.5
                editor.timelineZoom = min(max((layout.zoomStart ?? editor.timelineZoom) * value.magnification, minimum), 1200)
                if let anchor = layout.zoomAnchor { editor.timelineStart = max(0, anchor.time - Double(anchor.x) / editor.timelineZoom) }
            }
            .onEnded { _ in
                layout.zoomStart = nil
                layout.zoomAnchor = nil
            }
    }
}

private struct IdentifiedKey: Identifiable {
    let key: KeyRef
    var id: String { "\(key.track.raw)@\(key.time)" }
}

/// The playhead over the lanes (its own view: playback redraws only it).
struct PlayheadLine: View {
    let editor: EditorModel
    let width: CGFloat
    let height: CGFloat
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let x = CGFloat((editor.time - editor.timelineStart) * editor.timelineZoom)
        Rectangle()
            .fill(theme.accent)
            .frame(width: 2, height: height)
            .offset(x: TimelineLayout.labelWidth + x - 1)
            .opacity(x >= 0 && x <= width ? 1 : 0)
            .allowsHitTesting(false)
    }
}

/// The timecode (its own view, for the same reason).
struct TimelineClock: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Text(TimeFormat.clock(editor.time))
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.text)
            .frame(minWidth: 76, alignment: .leading)
            .accessibilityIdentifier("timeline-time")
    }
}

/// The slim transport: play, the time, the way to the whole timeline (or away).
struct TransportBar: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.s) {
            Transport(editor: editor)
            TimelineClock(editor: editor)
            Spacer()
            HmmButton("chevron.up", label: "Show the timeline", size: 36) { editor.timelinePresence = .full }
            HmmButton("xmark", label: "Hide the timeline", size: 36) { editor.timelinePresence = .hidden }
                .accessibilityIdentifier("hide-timeline")
        }
        .padding(.horizontal, HmmSpacing.m)
        .frame(height: 56)
        .background(theme.surface)
    }
}

/// ⏮ ‹ ⏯ › and ±10 s.
struct Transport: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: 2) {
            HmmButton("backward.end.fill", label: "To start", size: 40) {
                editor.pause()
                editor.setTime(editor.playRange.start)
            }
            HmmButton("gobackward.10", label: "Back 10 seconds", size: 40) { editor.jump(seconds: -10) }
            HmmButton("chevron.left", label: "Previous frame", size: 40) { editor.step(frames: -1) }
            HmmButton(editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play", isOn: editor.isPlaying,
                      size: HmmTarget.primary) { editor.togglePlay() }
            HmmButton("chevron.right", label: "Next frame", size: 40) { editor.step(frames: 1) }
            HmmButton("goforward.10", label: "Forward 10 seconds", size: 40) { editor.jump(seconds: 10) }
        }
        .environment(\.hmmInsideGlass, true)
    }
}
