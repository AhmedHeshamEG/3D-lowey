import LoweyCore
import SwiftUI

/// The 60-second tour: a few cards pointing at the parts of the editor, doing one thing each on the welcome island.
struct TourOverlay: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var step = 0

    struct Step {
        var title: String
        var text: String
        var systemImage: String
        var alignment: Alignment
        var action: ((EditorModel) -> Void)?
    }

    private let steps: [Step] = [
        Step(title: "This is the stage", text: "One finger orbits. Two fingers pan and pinch to zoom. Double-tap something to frame it.",
             systemImage: "hand.draw", alignment: .center, action: { $0.mode = .build }),
        Step(title: "Build with the rail", text: "Add shapes, characters, text and effects, draw in 3D, scatter a forest in one drag.",
             systemImage: "square.stack.3d.up", alignment: .leading, action: { $0.railPanel = .add }),
        Step(title: "Five modes", text: "Build · Animate · Camera · Look · Export. Everything is one tap away up here.",
             systemImage: "rectangle.3.group", alignment: .topTrailing, action: { $0.railPanel = nil }),
        Step(title: "Watch the shot", text: "Camera mode looks through the shot camera. It's flying over the island now.",
             systemImage: "video", alignment: .topTrailing, action: { editor in
                 editor.mode = .camera
                 editor.setTime(0)
                 editor.play()
             }),
        Step(title: "Animate by touch", text: "Select anything: tap a preset, set keys, or press Record and move it while the timeline plays.",
             systemImage: "record.circle", alignment: .bottom, action: { editor in
                 editor.pause()
                 editor.mode = .animate
             }),
        Step(title: "Your voice drives the timing", text: "The waveform button records or imports your voiceover. Its words become markers you sync to.",
             systemImage: "waveform", alignment: .bottom, action: nil),
        Step(title: "Claude can help", text: "Scene menu → AI & laptop bridge. Claude proposes a shot; you see it first and decide.",
             systemImage: "sparkles", alignment: .topLeading, action: nil),
        Step(title: "Export both shapes at once", text: "Export mode renders 16:9 and 9:16 videos with sound, captions and effects. Have fun!",
             systemImage: "square.and.arrow.up", alignment: .topTrailing, action: { $0.mode = .export })
    ]

    var body: some View {
        let current = steps[min(step, steps.count - 1)]
        ZStack(alignment: current.alignment) {
            Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: current.systemImage).font(.system(size: 22)).foregroundStyle(Theme.accent)
                    Text(current.title).font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(step + 1)/\(steps.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                }
                Text(current.text).font(.system(size: 15)).foregroundStyle(Theme.text)
                HStack {
                    PillButton(title: "Skip tour") { finish() }
                    Spacer()
                    PillButton(title: step == steps.count - 1 ? "Start creating" : "Next", systemName: "arrow.right", prominent: true) {
                        if step == steps.count - 1 {
                            finish()
                        } else {
                            advance()
                        }
                    }
                    .accessibilityIdentifier("tour-next")
                }
            }
            .padding(20)
            .frame(width: 400)
            .panelStyle()
            .padding(.horizontal, 110)
            .padding(.vertical, 96)
        }
        .onAppear { current.action?(editor) }
        .transition(.opacity)
    }

    private func advance() {
        step += 1
        Haptics.tap()
        steps[step].action?(editor)
    }

    private func finish() {
        editor.pause()
        editor.mode = .build
        app.showTour = false
    }
}
