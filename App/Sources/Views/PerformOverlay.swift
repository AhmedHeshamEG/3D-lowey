import LoweyCore
import SwiftUI

/// Perform mode feedback: the "Ready 3-2-1" countdown and a recording badge.
struct PerformOverlay: View {
    let editor: EditorModel

    var body: some View {
        ZStack {
            switch editor.performPhase {
            case let .countdown(count):
                VStack(spacing: 6) {
                    Text("Ready").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(count)").font(.system(size: 96, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(editor.virtualCameraActive ? "Move the iPad when it plays" : "Touch and move when it plays")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(Theme.text)
                .padding(30)
                .panelStyle(cornerRadius: 30)
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("perform-countdown")
            case .recording:
                VStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 12, height: 12)
                        Text("REC").font(.system(size: 14, weight: .heavy))
                        Text(editor.performTouching ? "recording" : "lift = paused").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .panelStyle(cornerRadius: 20)
                    .padding(.top, 70)
                    Spacer()
                }
                .accessibilityIdentifier("perform-recording")
            case .idle:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.25), value: editor.performPhase)
    }
}
