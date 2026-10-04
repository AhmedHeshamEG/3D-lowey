import HmmDesign
import LoweyCore
import SwiftUI

/// Seconds, the loop region, the end of the timeline, markers; drag to scrub (snapping to words); the band over
/// several selected keys, whose ends stretch their timing.
struct TimelineRuler: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let width: CGFloat
    let renameMarker: (Marker) -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in draw(in: &context, size: size) }
            selectionBand
            ForEach(editor.timeline.markers) { marker in
                if layout.x(marker.time) >= -4, layout.x(marker.time) <= width {
                    MarkerFlag(marker: marker)
                        .offset(x: layout.x(marker.time) - 2)
                        .onTapGesture { editor.setTime(marker.time) }
                        .accessibilityAddTraits(.isButton)
                        .onLongPressGesture { renameMarker(marker) }
                }
            }
        }
        .frame(width: width, height: TimelineLayout.rulerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            editor.pause()
            let before = editor.time
            editor.setTime(editor.wordSnapped(layout.time(at: value.location.x), tolerance: 8 / layout.pps))
            if editor.time != before { editor.audioPlayback.scrub(editor.timeline.audio, at: editor.time) }
        })
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(TimeFormat.clock(editor.time))
        .accessibilityAdjustableAction { direction in editor.step(frames: direction == .increment ? 1 : -1) }
        .accessibilityIdentifier("timeline-ruler")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let timeline = editor.timeline
        if let loop = timeline.loop {
            context.fill(Path(CGRect(x: layout.x(loop.start), y: 0, width: CGFloat(loop.duration * layout.pps), height: size.height)),
                         with: .color(theme.accent.opacity(0.18)))
        }
        let end = layout.x(timeline.duration)
        context.fill(Path(CGRect(x: end, y: 0, width: max(size.width - end, 0), height: size.height)), with: .color(.black.opacity(0.3)))
        let step = TimeFormat.tickStep(pointsPerSecond: layout.pps)
        var time = (layout.visibleStart / step).rounded(.down) * step
        while layout.x(time) < size.width {
            let x = layout.x(time)
            if x >= 0 {
                let major = abs((time / (step * 5)).rounded() * step * 5 - time) < 1e-6
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height))
                tick.addLine(to: CGPoint(x: x, y: size.height - (major ? 12 : 6)))
                context.stroke(tick, with: .color(theme.text.opacity(major ? 0.5 : 0.25)), lineWidth: 1)
                if major {
                    context.draw(Text(TimeFormat.short(time)).font(.system(size: 10, weight: .medium)).foregroundColor(theme.text2),
                                 at: CGPoint(x: x + 3, y: 9), anchor: .leading)
                }
            }
            time += step
        }
    }

    @ViewBuilder private var selectionBand: some View {
        if editor.timelineMode != .compose, editor.selectedKeys.count > 1, let span = KeySelection.span(of: editor.selectedKeys), span.duration > 0 {
            let shown = layout.stretch.map { layout.stretchTarget(span: span, stretch: $0) }
                ?? TimeRange(start: layout.previewTime(span.start), end: layout.previewTime(span.end))
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(theme.text.opacity(0.35))
                    .frame(width: max(CGFloat(shown.duration * layout.pps), 4), height: 5)
                    .offset(x: layout.x(shown.start), y: TimelineLayout.rulerHeight - 7)
                    .allowsHitTesting(false)
                handle(.start, at: shown.start, span: span)
                handle(.end, at: shown.end, span: span)
            }
            .frame(width: width, height: TimelineLayout.rulerHeight, alignment: .topLeading)
        }
    }

    private func handle(_ edge: TimelineLayout.StretchEdge, at time: Double, span: TimeRange) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: 16, height: 16)
            .frame(width: 34, height: TimelineLayout.rulerHeight)
            .contentShape(Rectangle())
            .offset(x: layout.x(time) - 17, y: 4)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = edge == .start ? span.start : span.end
                        layout.stretch = (edge, editor.timeline.snapped(base + Double(value.translation.width) / layout.pps))
                    }
                    .onEnded { _ in
                        if let stretch = layout.stretch { editor.stretchSelectedKeys(to: layout.stretchTarget(span: span, stretch: stretch)) }
                        layout.stretch = nil
                    }
            )
            .accessibilityLabel(edge == .start ? "Stretch the selected keys from the start" : "Stretch the selected keys from the end")
    }
}

private struct MarkerFlag: View {
    let marker: Marker

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Rectangle().fill(Color.yellow).frame(width: 2, height: TimelineLayout.rulerHeight)
            Text(marker.name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.yellow))
                .frame(maxWidth: 120, alignment: .leading)
        }
        .accessibilityLabel("Marker \(marker.name)")
    }
}
