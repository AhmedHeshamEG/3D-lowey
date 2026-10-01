import HmmDesign
import LoweyEngine
import SwiftUI
import UIKit

/// What the app shows on an iPhone: the face companion. With Face ID, the iPhone tracks your face (ARKit) and arms
/// (Vision) and streams them to the iPad over the local network, where they drive your character.
public struct CompanionView: View {
    @State private var sender = FaceLinkSender()
    @State private var status = "Starting…"
    @State private var running = false
    @State private var monitor = FaceMonitor()
    @Environment(\.hmmTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: HmmSpacing.l) {
            Text("Face companion").font(.hmm(.title2, weight: .semibold))
            ZStack {
                if let picture = monitor.picture {
                    Image(decorative: picture, scale: 1).resizable().scaledToFill()
                } else {
                    Rectangle().fill(theme.surface2)
                    Image(systemName: "face.smiling").font(.system(size: 60, weight: .light)).foregroundStyle(theme.accent)
                }
                Canvas { context, size in
                    for (a, b) in monitor.bones {
                        var path = Path()
                        path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
                        path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
                        context.stroke(path, with: .color(theme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    for dot in monitor.dots {
                        context.fill(Path(ellipseIn: CGRect(x: dot.x * size.width - 2, y: dot.y * size.height - 2, width: 4, height: 4)), with: .color(.green))
                    }
                }
            }
            .frame(width: 240, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.panel, style: .continuous))
            Text("On the iPad: select your character, Cast ▸ My iPhone. Prop this phone up facing you, far enough to see your shoulders and hands.")
                .font(.hmm(.body)).multilineTextAlignment(.center).foregroundStyle(theme.text2).padding(.horizontal, HmmSpacing.l)
            Text(status).font(.hmm(.headline, weight: .semibold)).accessibilityIdentifier("companion-status")
            HmmPillButton(running ? "Stop" : "Start", systemName: running ? "stop.fill" : "play.fill", prominent: !running) {
                if running {
                    sender.stop()
                    status = "Stopped"
                    monitor.clear()
                } else {
                    sender.start()
                }
                running.toggle()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .onAppear(perform: begin)
        .onDisappear {
            sender.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func begin() {
        sender.onStatus = { status = $0 }
        sender.onPreview = { picture, dots, bones in
            if let picture { monitor.picture = picture }
            monitor.dots = dots
            monitor.bones = bones
        }
        if FaceLinkSender.isSupported {
            sender.start()
            running = true
        } else {
            status = "This iPhone has no Face ID camera. The iPad can read your face with its own camera instead."
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
