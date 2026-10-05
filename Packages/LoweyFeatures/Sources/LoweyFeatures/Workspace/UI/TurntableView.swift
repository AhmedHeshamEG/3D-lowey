import HmmDesign
import ImageIO
import SwiftUI
import UIKit

/// A Home card's picture: the model slowly turning in its Look while the card is on screen, the still otherwise.
/// The turntable is read from its cached GIF one frame at a time (nothing decoded is kept but the frame shown), it
/// pauses while the gallery scrolls or a project is open, and Reduce Motion keeps the still.
struct TurntableView: View {
    let url: URL
    let still: UIImage?
    let revision: Int
    let playing: Bool
    @State private var source: CGImageSource?
    @State private var frameCount = 0
    @State private var onScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hmmTheme) private var theme

    static let fps = 8.0

    var body: some View {
        Group {
            if let source, frameCount > 1, playing, onScreen, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / Self.fps)) { context in
                    if let frame = frame(source, at: context.date) {
                        Image(decorative: frame, scale: 1).resizable().scaledToFill()
                    } else {
                        stillView
                    }
                }
            } else {
                stillView
            }
        }
        .onAppear { onScreen = true }
        .onDisappear {
            onScreen = false
            source = nil
            frameCount = 0
        }
        .task(id: TaskKey(revision: revision, onScreen: onScreen)) {
            guard onScreen, !reduceMotion else { return }
            // Opening a source reads only the GIF's header; frames are decoded as they're shown.
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
            frameCount = source.map(CGImageSourceGetCount) ?? 0
        }
    }

    private struct TaskKey: Equatable {
        var revision: Int
        var onScreen: Bool
    }

    @ViewBuilder private var stillView: some View {
        if let still {
            Image(uiImage: still).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [theme.surface2, theme.surface], startPoint: .top, endPoint: .bottom)
                Image(systemName: "cube.transparent").font(.system(size: 40)).foregroundStyle(theme.text3)
            }
        }
    }

    private func frame(_ source: CGImageSource, at date: Date) -> CGImage? {
        let index = Int(date.timeIntervalSinceReferenceDate * Self.fps) % max(frameCount, 1)
        return CGImageSourceCreateImageAtIndex(source, index, nil)
    }
}
