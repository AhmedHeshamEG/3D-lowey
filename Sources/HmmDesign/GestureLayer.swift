/// The universal gestures of every hmm. app (listed identically in each Settings ▸ Gesture guide).
public enum HmmUniversalGesture: String, Sendable, CaseIterable, Identifiable {
    case undo, redo, rapidUndo, toggleChrome, zoom, options

    public var id: String { rawValue }

    public var gesture: String {
        switch self {
        case .undo: "Two-finger tap"
        case .redo: "Three-finger tap"
        case .rapidUndo: "Two-finger touch and hold"
        case .toggleChrome: "Four-finger tap"
        case .zoom: "Pinch"
        case .options: "Touch and hold on anything"
        }
    }

    public var meaning: String {
        switch self {
        case .undo: "Undo"
        case .redo: "Redo"
        case .rapidUndo: "Undo again and again, until you lift"
        case .toggleChrome: "Hide or show everything but the canvas"
        case .zoom: "Zoom the canvas"
        case .options: "Its options"
        }
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
    import SwiftUI
    import UIKit

    /// What the universal gestures do in one screen.
    @MainActor
    public struct HmmGestureActions {
        public var undo: () -> Void
        public var redo: () -> Void
        public var toggleChrome: () -> Void
        /// Seconds between steps while two fingers are held.
        public var rapidUndoInterval: Double

        public init(undo: @escaping () -> Void, redo: @escaping () -> Void, toggleChrome: @escaping () -> Void,
                    rapidUndoInterval: Double = 0.12) {
            self.undo = undo
            self.redo = redo
            self.toggleChrome = toggleChrome
            self.rapidUndoInterval = rapidUndoInterval
        }
    }

    /// Installs the universal finger gestures on the window that shows this view, next to (never instead of) the
    /// canvas's own gestures: touches still reach everything below, and the Pencil is never involved.
    public struct HmmGestureLayer: UIViewRepresentable {
        private let actions: HmmGestureActions

        public init(_ actions: HmmGestureActions) {
            self.actions = actions
        }

        public func makeUIView(context _: Context) -> InstallerView {
            let view = InstallerView()
            view.actions = actions
            view.isUserInteractionEnabled = false
            return view
        }

        public func updateUIView(_ view: InstallerView, context _: Context) {
            view.actions = actions
        }

        /// A zero-size view that owns the recognizers and moves them with its window.
        public final class InstallerView: UIView, UIGestureRecognizerDelegate {
            var actions: HmmGestureActions?
            private var recognizers: [UIGestureRecognizer] = []
            private weak var installedOn: UIWindow?
            private var repeatTimer: Timer?

            override public func didMoveToWindow() {
                super.didMoveToWindow()
                uninstall()
                if let window { install(on: window) }
            }

            private func install(on window: UIWindow) {
                let undo = tap(touches: 2, action: #selector(undoTapped))
                let redo = tap(touches: 3, action: #selector(redoTapped))
                let chrome = tap(touches: 4, action: #selector(chromeTapped))
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
                hold.numberOfTouchesRequired = 2
                hold.minimumPressDuration = 0.55
                hold.allowableMovement = 12
                recognizers = [undo, redo, chrome, hold]
                for recognizer in recognizers {
                    recognizer.cancelsTouchesInView = false
                    recognizer.delaysTouchesEnded = false
                    recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                    recognizer.delegate = self
                    window.addGestureRecognizer(recognizer)
                }
                installedOn = window
            }

            private func uninstall() {
                stopRepeating()
                for recognizer in recognizers {
                    installedOn?.removeGestureRecognizer(recognizer)
                }
                recognizers.removeAll()
                installedOn = nil
            }

            private func tap(touches: Int, action: Selector) -> UITapGestureRecognizer {
                let recognizer = UITapGestureRecognizer(target: self, action: action)
                recognizer.numberOfTouchesRequired = touches
                return recognizer
            }

            @objc private func undoTapped() {
                HmmHaptics.play(.undo)
                actions?.undo()
            }

            @objc private func redoTapped() {
                HmmHaptics.play(.undo)
                actions?.redo()
            }

            @objc private func chromeTapped() {
                HmmHaptics.play(.selection)
                actions?.toggleChrome()
            }

            @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
                switch recognizer.state {
                case .began:
                    undoTapped()
                    let interval = actions?.rapidUndoInterval ?? 0.12
                    repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.undoTapped() }
                    }
                case .ended, .cancelled, .failed:
                    stopRepeating()
                default:
                    break
                }
            }

            private func stopRepeating() {
                repeatTimer?.invalidate()
                repeatTimer = nil
            }

            public func gestureRecognizer(_: UIGestureRecognizer,
                                          shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
                true
            }

            /// Text fields and sliders keep their own touches.
            public func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
                !(touch.view is UITextField || touch.view is UITextView)
            }
        }
    }

    public extension View {
        /// Adds the universal gestures (two-finger tap undo, three-finger tap redo, two-finger hold rapid undo,
        /// four-finger tap hides the chrome) to this screen.
        func hmmUniversalGestures(_ actions: HmmGestureActions) -> some View {
            background(HmmGestureLayer(actions).frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }
#endif
