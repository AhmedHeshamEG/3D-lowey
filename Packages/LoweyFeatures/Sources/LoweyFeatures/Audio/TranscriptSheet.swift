import HmmDesign
import LoweyCore
import SwiftUI

/// The transcript: tap a word to jump there; touch and hold one word, then tap another, to pick a phrase and attach
/// something to it (an animation, a camera move, a cut, a marker, a loop) or fix its words without losing timing.
struct TranscriptSheet: View {
    @Bindable var editor: EditorModel
    @State private var anchor: Int?
    @State private var fixing = false
    @State private var fixText = ""
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let words = editor.words
        let current = WordSnap.word(at: editor.time, in: words)
        HmmSheet("Transcript") {
            HStack {
                HmmButton(editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play", size: 40) { editor.togglePlay() }
                Hint(anchor == nil ? "Tap a word to jump there. Touch and hold a word, then tap another, to pick a phrase." : "Now tap the phrase's last word.")
            }
            if words.isEmpty {
                Hint("Transcribe a voiceover (Sound & words) and its words appear here.")
            } else {
                ScrollViewReader { proxy in
                    FlowLayout(spacing: 4) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            chip(word, index: index, isCurrent: word.id == current?.id).id(word.id)
                        }
                    }
                    .onChange(of: current?.id) { _, id in
                        if editor.isPlaying, let id { withAnimation(.hmmStandard) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
                if editor.wordSelection != nil { PhraseActions(editor: editor, fix: { fixText = editor.selectedWordText; fixing = true }) }
            }
        }
        .alert("Fix words", isPresented: $fixing) {
            TextField("What was said", text: $fixText)
            Button("Save") { if let range = editor.wordSelection { editor.correctWords(range, to: fixText) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The new words keep the timing of the old ones.")
        }
    }

    private func chip(_ word: TimelineWord, index: Int, isCurrent: Bool) -> some View {
        let selected = editor.wordSelection?.contains(index) ?? false
        return Text(word.text)
            .font(.hmm(.headline, weight: isCurrent ? .semibold : .regular))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .foregroundStyle(selected ? theme.onAccent : theme.text)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? theme.accent : (isCurrent ? theme.surface2 : .clear)))
            .contentShape(Rectangle())
            .onTapGesture {
                if let first = anchor {
                    editor.wordSelection = min(first, index) ... max(first, index)
                    anchor = nil
                    HmmHaptics.play(.selection)
                } else {
                    editor.wordSelection = index ... index
                    editor.jump(to: word)
                }
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                anchor = index
                editor.wordSelection = index ... index
                HmmHaptics.play(.selection)
            }
            .accessibilityLabel(word.text)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Attach to words: what to do at the picked phrase.
private struct PhraseActions: View {
    let editor: EditorModel
    let fix: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Text("“\(editor.selectedWordText)”").font(.hmm(.body, weight: .semibold)).lineLimit(2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    if !editor.selection.isEmpty {
                        Menu {
                            ForEach(AnimationPreset.allCases, id: \.self) { preset in
                                Button(preset.title) { editor.attachToWords { $0.applyPreset(preset) } }
                            }
                        } label: { Label("Animate the selection here", systemImage: "sparkles") }
                    }
                    Menu {
                        ForEach(CameraMove.allCases, id: \.self) { move in
                            Button(move.title) { editor.attachToWords { $0.applyCameraMove(move, duration: $0.presetDuration ?? 1, strength: 1) } }
                        }
                    } label: { Label("Camera move here", systemImage: "video") }
                    if !editor.cameras.isEmpty {
                        Menu {
                            ForEach(editor.cameras, id: \.self) { id in
                                Button(editor.baseScene.objects[id]?.name ?? "Camera") { editor.attachToWords { $0.cutToCamera(id) } }
                            }
                        } label: { Label("Cut here to…", systemImage: "scissors") }
                    }
                    HmmPillButton("Marker", systemName: "flag") { editor.addMarkersForSelectedWords() }
                    HmmPillButton("Loop this", systemName: "repeat") {
                        if let range = editor.selectedWordRange { editor.updateTimeline("Loop") { $0.loop = range } }
                    }
                    HmmPillButton("Fix words", systemName: "pencil", action: fix)
                }
                .font(.hmm(.body, weight: .semibold))
            }
        }
        .padding(HmmSpacing.s)
        .background(RoundedRectangle(cornerRadius: HmmRadius.card).fill(theme.surface2))
    }
}

/// Wrapping layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
