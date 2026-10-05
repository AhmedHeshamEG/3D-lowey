import HmmDesign
import LoweyCore
import SwiftUI

/// The 60-second tour on the welcome island: a card per part of the screen, each doing one thing.
struct TourOverlay: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var step = 0

    struct Step {
        var title: String
        var text: String
        var systemImage: String
        var alignment: Alignment
        var action: (@MainActor (EditorModel) -> Void)?
    }

    private let steps: [Step] = [
        Step(title: "This is the stage", text: "One finger orbits, two pan and pinch. Double-tap something to frame it. Tap to select.",
             systemImage: "hand.draw", alignment: .center, action: { $0.openPanel = nil }),
        Step(title: "Make things, top right", text: "Model adds shapes, lights, words and the Kit's models; Draw, Paint, Animate and Cast do the rest.",
             systemImage: "cube", alignment: .topTrailing, action: { $0.openPanel = .model }),
        Step(title: "The look, top left", text: "Ink, Comic, Sketch, Clay or Low-poly, the mood and the palette. Actions and select live here too.",
             systemImage: "paintpalette", alignment: .topLeading, action: { $0.openPanel = .look }),
        Step(title: "Two sliders, and undo", text: "The sidebar's sliders change with what you're doing. Two-finger tap undoes, three redoes.",
             systemImage: "slider.vertical.3", alignment: .leading, action: { $0.openPanel = nil }),
        Step(title: "Watch the shot", text: "The Director view looks through the shot camera. It's flying over the island now.",
             systemImage: "video", alignment: .bottomTrailing, action: { editor in
                 editor.setDirectorView(true)
                 editor.setTime(0)
                 editor.play()
             }),
        Step(title: "Time comes when called", text: "Animate opens the timeline: Compose slides animations, Perform records your moves, Keyframe sets keys.",
             systemImage: "timeline.selection", alignment: .bottom, action: { editor in
                 editor.pause()
                 editor.directorView = false
                 editor.timelinePresence = .full
             }),
        Step(title: "Share it", text: "Actions ▸ Export: YouTube, Shorts, GIF, stills. It renders in the background. Every gesture is in Settings ▸ Gestures.",
             systemImage: "square.and.arrow.up", alignment: .topLeading, action: { editor in
                 editor.timelinePresence = .hidden
                 editor.openPanel = .actions
             })
    ]

    var body: some View {
        let current = steps[min(step, steps.count - 1)]
        ZStack(alignment: current.alignment) {
            Color.black.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                HStack {
                    Image(systemName: current.systemImage).font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    Text(current.title).font(.hmm(.title3, weight: .semibold))
                    Spacer()
                    Text("\(step + 1)/\(steps.count)").font(.hmmNumbers(.footnote))
                }
                Text(current.text).font(.hmm(.body))
                HStack {
                    HmmPillButton("Skip the tour", action: finish)
                    Spacer()
                    HmmPillButton(step == steps.count - 1 ? "Start making" : "Next", systemName: "arrow.right", prominent: true) {
                        if step == steps.count - 1 {
                            finish()
                        } else {
                            advance()
                        }
                    }
                    .accessibilityIdentifier("tour-next")
                }
            }
            .padding(HmmSpacing.l)
            .frame(width: 400)
            .hmmPanelBackground()
            .padding(.horizontal, 100)
            .padding(.vertical, 110)
        }
        .onAppear { current.action?(editor) }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour")
    }

    private func advance() {
        step += 1
        HmmHaptics.play(.selection)
        steps[step].action?(editor)
    }

    private func finish() {
        editor.pause()
        editor.directorView = false
        editor.openPanel = nil
        app.showTour = false
        UserDefaults.standard.set(true, forKey: AppSettings.tourSeen)
    }
}
