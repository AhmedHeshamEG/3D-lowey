import UIKit

/// Keeps the iPad from auto-locking while something needs it (an export, an open project). Each reason holds the
/// screen on independently.
@MainActor
enum ScreenAwake {
    private static var reasons = Set<String>()

    static func hold(_ reason: String, _ on: Bool) {
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        UIApplication.shared.isIdleTimerDisabled = !reasons.isEmpty
    }
}
