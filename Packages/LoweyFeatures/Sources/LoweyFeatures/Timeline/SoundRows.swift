import HmmDesign
import LoweyCore
import SwiftUI

/// A sound in the timeline: its waveform (scaled by its gain), fades as slopes; drag to slide, tap to select.
struct AudioRow: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let clip: AudioClip
    let width: CGFloat
    @State private var drag: Double?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: clip.role.systemImage).font(.system(size: 11)).foregroundStyle(clip.role.tint)
                Text(clip.name).font(.hmm(.caption, weight: editor.selectedAudio == clip.id ? .semibold : .regular))
                    .foregroundStyle(clip.muted ? theme.text3 : theme.text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(width: TimelineLayout.labelWidth)
            .contentShape(Rectangle())
            .onTapGesture { editor.selectedAudio = clip.id }
            lane
        }
        .background(editor.selectedAudio == clip.id ? clip.role.tint.opacity(0.08) : .clear)
    }

    private var lane: some View {
        let peaks = editor.waveforms[clip.file] ?? []
        let offset = drag ?? 0
        return Canvas { context, size in
            let start = layout.x(clip.start + offset)
            let rect = CGRect(x: start, y: 2, width: max(layout.x(clip.end + offset) - start, 2), height: size.height - 4)
            guard rect.maxX > 0, rect.minX < size.width else { return }
            let color = clip.role.tint
            context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color.opacity(clip.muted ? 0.08 : 0.22)))
            if editor.selectedAudio == clip.id { context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(color), lineWidth: 1.5) }
            if !peaks.isEmpty { context.stroke(
                wave(peaks, rect: rect, start: start, width: size.width),
                with: .color(color.opacity(clip.muted ? 0.3 : 0.85)),
                lineWidth: 1.2
            ) }
            if clip.fadeIn > 0 {
                var fade = Path()
                fade.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                fade.addLine(to: CGPoint(x: rect.minX + CGFloat(clip.fadeIn * layout.pps), y: rect.minY))
                context.stroke(fade, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
            if clip.fadeOut > 0 {
                var fade = Path()
                fade.move(to: CGPoint(x: rect.maxX - CGFloat(clip.fadeOut * layout.pps), y: rect.minY))
                fade.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                context.stroke(fade, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isOnClip(value.startLocation.x) else { return }
                drag = max(Double(value.translation.width) / layout.pps, -clip.start)
            }
            .onEnded { _ in
                if let drag { editor.moveAudioClip(clip.id, by: drag) }
                drag = nil
            })
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if isOnClip(value.location.x) { editor.selectedAudio = clip.id }
            editor.setTime(max(0, layout.time(at: value.location.x)))
        })
        .onAppear { editor.loadWaveform(clip.file) }
        .accessibilityLabel("\(clip.role.title): \(clip.name)")
        .accessibilityIdentifier("audio-clip-\(clip.name)")
    }

    /// 100 peaks per second of the file, one line every two points, scaled by the clip's gain there.
    private func wave(_ peaks: [Float], rect: CGRect, start: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        let half = rect.height / 2 - 2
        var x = max(rect.minX, 0)
        while x < min(rect.maxX, width) {
            let time = clip.start + Double(x - start) / layout.pps
            if let fileTime = clip.fileTime(at: time) {
                let index = Int(fileTime * 100)
                let peak = peaks.indices.contains(index) ? CGFloat(peaks[index]) : 0
                let height = max(peak * CGFloat(min(clip.gain(at: time), 1.5)) * half, 0.5)
                path.move(to: CGPoint(x: x, y: rect.midY - height))
                path.addLine(to: CGPoint(x: x, y: rect.midY + height))
            }
            x += 2
        }
        return path
    }

    private func isOnClip(_ x: CGFloat) -> Bool { x >= layout.x(clip.start) - 4 && x <= layout.x(clip.end) + 4 }
}

/// The spoken words as chips, the one under the playhead lit; tap one to jump there.
struct WordsRow: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let width: CGFloat
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let words = editor.words
        let current = WordSnap.word(at: editor.time, in: words)?.id
        HStack(spacing: 0) {
            Label("Words", systemImage: "text.bubble").font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2)
                .padding(.leading, 10).frame(width: TimelineLayout.labelWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { editor.sheet = .transcript }
            Canvas { context, size in
                var lastEnd: CGFloat = -1000
                for word in words {
                    let start = layout.x(word.start)
                    let end = layout.x(word.end)
                    guard end > 0, start < size.width else { continue }
                    let isCurrent = word.id == current
                    context.fill(Path(roundedRect: CGRect(x: start, y: 3, width: max(end - start - 1, 2), height: size.height - 6), cornerRadius: 4),
                                 with: .color(isCurrent ? theme.accent.opacity(0.9) : Color.yellow.opacity(0.22)))
                    if start > lastEnd + 2 {
                        let label = context.resolve(Text(word.text).font(.system(size: 10, weight: .semibold)).foregroundColor(isCurrent ? .black : .white))
                        context.draw(label, at: CGPoint(x: start + 3, y: size.height / 2), anchor: .leading)
                        lastEnd = start + label.measure(in: CGSize(width: 200, height: size.height)).width + 3
                    }
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let tapped = layout.time(at: value.location.x)
                if let word = words.min(by: { abs(($0.start + $0.end) / 2 - tapped) < abs(($1.start + $1.end) / 2 - tapped) }) { editor.jump(to: word) }
            })
            .accessibilityIdentifier("words-lane")
        }
    }
}

/// Screen effects: drag a chip to retime it, tap to jump there, touch and hold to delete.
struct EffectsRow: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let width: CGFloat
    @State private var drag: (id: String, delta: Double)?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Label("Effects", systemImage: "bolt.fill").font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2)
                .padding(.leading, 10).frame(width: TimelineLayout.labelWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                ForEach(editor.timeline.effects) { effect in
                    let offset = drag?.id == effect.id ? drag?.delta ?? 0 : 0
                    Label(effect.kind.title, systemImage: effect.kind.systemImage)
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 5)
                        .frame(width: max(CGFloat(effect.duration * layout.pps), 18), height: TimelineLayout.wordsRowHeight - 4, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.pink.opacity(0.45)))
                        .offset(x: layout.x(effect.start + offset))
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { value in drag = (effect.id, Double(value.translation.width) / layout.pps) }
                            .onEnded { value in
                                let start = editor.wordSnapped(max(0, effect.start + Double(value.translation.width) / layout.pps), tolerance: 8 / layout.pps)
                                editor.updateScreenEffect(effect.id) { $0.start = start }
                                drag = nil
                            })
                        .onTapGesture { editor.setTime(effect.start) }
                        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { editor.removeScreenEffect(effect.id) } }
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
        }
    }
}
