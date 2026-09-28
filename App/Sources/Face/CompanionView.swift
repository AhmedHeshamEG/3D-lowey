import SwiftUI

/// What 3D-lowey shows on an iPhone: the face companion. With Face ID, the iPhone tracks your face (ARKit) and
/// streams it to the iPad over the local network, where it drives your character's face.
struct CompanionView: View {
    @State private var sender = FaceLinkSender()
    @State private var status = "Starting…"
    @State private var running = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "face.smiling")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Face companion").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("On the iPad: select your character → Animate → Face → “Use my iPhone”. Keep this phone in front of you, looking at your face.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 28)
            Text(status)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier("companion-status")
            PillButton(title: running ? "Stop" : "Start", systemName: running ? "stop.fill" : "play.fill", prominent: !running) {
                if running {
                    sender.stop()
                    status = "Stopped"
                } else {
                    sender.start()
                }
                running.toggle()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            sender.onStatus = { status = $0 }
            if FaceLinkSender.isSupported {
                sender.start()
                running = true
            } else {
                status = "This iPhone has no Face ID camera — the iPad can read your face with its own camera instead."
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            sender.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
