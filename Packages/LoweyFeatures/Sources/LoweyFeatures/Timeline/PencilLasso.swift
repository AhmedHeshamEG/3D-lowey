import SwiftUI
import UIKit

/// A Pencil-only drag (fingers keep scrolling and panning): reports where the Pencil is in the view.
struct PencilLasso: UIGestureRecognizerRepresentable {
    let update: (CGPoint, UIGestureRecognizer.State) -> Void

    func makeUIGestureRecognizer(context _: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        update(context.converter.localLocation, recognizer.state)
    }
}
