import LoweyCore
import SwiftUI

// MARK: Per-frame pieces

// These read the playhead. Keeping them in their own small views means playback redraws only them,
// not every row and key of the timeline (SwiftUI re-evaluates whichever body reads `editor.time`).

/// The time readout in the header.
struct TimelineClock: View {
    let editor: EditorModel

    var body: some View {
        Text(TimelineDrawer.format(editor.time))
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.text)
            .frame(minWidth: 70, alignment: .leading)
            .accessibilityIdentifier("timeline-time")
    }
}

/// The playhead line over the lanes.
struct PlayheadLine: View {
    let editor: EditorModel
    let visibleStart: Double
    let pps: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let px = CGFloat((editor.time - visibleStart) * pps)
        Rectangle()
            .fill(Theme.accent)
            .frame(width: 2, height: height)
            .offset(x: TimelineDrawer.labelWidth + px - 1)
            .opacity(px >= 0 && px <= width ? 1 : 0)
            .allowsHitTesting(false)
    }
}

/// The spoken words as chips, the one under the playhead lit.
struct WordsLaneCanvas: View {
    let editor: EditorModel
    let words: [TimelineWord]
    let visibleStart: Double
    let pps: Double

    var body: some View {
        let current = WordSnap.word(at: editor.time, in: words)?.id
        Canvas { context, size in
            var lastEnd: CGFloat = -1000
            for word in words {
                let start = CGFloat((word.start - visibleStart) * pps)
                let end = CGFloat((word.end - visibleStart) * pps)
                guard end > 0, start < size.width else { continue }
                let rect = CGRect(x: start, y: 3, width: max(end - start - 1, 2), height: size.height - 6)
                let isCurrent = word.id == current
                context.fill(Path(roundedRect: rect, cornerRadius: 4),
                             with: .color(isCurrent ? Theme.accent.opacity(0.9) : Color.yellow.opacity(0.22)))
                // Labels only where there's room (zoom in to read every word).
                if start > lastEnd + 2 {
                    let label = context.resolve(Text(word.text).font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isCurrent ? .black : .white.opacity(0.85)))
                    let labelSize = label.measure(in: CGSize(width: 200, height: size.height))
                    context.draw(label, at: CGPoint(x: start + 3, y: size.height / 2), anchor: .leading)
                    lastEnd = start + labelSize.width + 3
                }
            }
        }
    }
}

/// Compose · Perform · Keyframe as icons, the current one labelled (like the mode switcher up top).
struct TimelineModePicker: View {
    @Binding var mode: TimelineMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TimelineMode.allCases) { item in
                Button {
                    Haptics.select()
                    mode = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.systemImage)
                        if item == mode { Text(item.title) }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, item == mode ? 12 : 10)
                    .frame(height: 34)
                    .foregroundStyle(item == mode ? Color.black : Theme.text)
                    .background(Capsule().fill(item == mode ? Theme.accent : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("timeline-mode-\(item.rawValue)")
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.raised))
        .animation(.spring(duration: 0.25), value: mode)
        .accessibilityIdentifier("timeline-mode")
    }
}
