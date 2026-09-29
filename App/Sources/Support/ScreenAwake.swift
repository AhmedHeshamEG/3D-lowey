import UIKit

/// Keeps the iPad from auto-locking while something needs it awake (an export, the laptop bridge). Each reason holds
/// the screen on independently, so an export finishing doesn't let the bridge go to sleep.
@MainActor
enum ScreenAwake {
    private static var reasons = Set<String>()

    static func hold(_ reason: String, _ on: Bool) {
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        UIApplication.shared.isIdleTimerDisabled = !reasons.isEmpty
    }
}
