import SwiftUI

/// What 3D-lowey shows on an iPhone: the face companion. With Face ID, the iPhone tracks your face (ARKit) and your arms
/// (Vision) and streams them to the iPad over the local network, where they drive your character.
struct CompanionView: View {
    @State private var sender = FaceLinkSender()
    @State private var status = "Starting…"
    @State private var running = false
    @State private var monitor = FaceMonitor()

    var body: some View {
        VStack(spacing: 20) {
            Text("Face companion").font(.system(size: 26, weight: .bold, design: .rounded))
            ZStack {
                if let picture = monitor.picture {
                    Image(decorative: picture, scale: 1).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.raised)
                    Image(systemName: "face.smiling").font(.system(size: 60, weight: .light)).foregroundStyle(Theme.accent)
                }
                Canvas { context, size in
                    for (a, b) in monitor.bones {
                        var path = Path()
                        path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
                        path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
                        context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    for dot in monitor.dots {
                        context.fill(Path(ellipseIn: CGRect(x: dot.x * size.width - 2, y: dot.y * size.height - 2, width: 4, height: 4)),
                                     with: .color(.green))
                    }
                }
            }
            .frame(width: 240, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(
                "On the iPad: select your character, Animate, Face, “Use my iPhone”. Prop this phone up facing you, far enough to see your shoulders and hands."
            )
            .font(.system(size: 14))
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
                    monitor.clear()
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
        .onDisappear {
            sender.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
