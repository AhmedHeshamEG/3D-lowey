import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// The four haptic moments of every hmm. app.
public enum HmmHapticEvent: Sendable, CaseIterable {
    /// Selection changed.
    case selection
    /// Something committed: a drop, a snap, a key set.
    case commit
    /// Undo or redo.
    case undo
    /// Something failed.
    case error
}

/// Plays haptics (can be turned off in Settings: `HmmHaptics.isEnabled`).
@MainActor
public enum HmmHaptics {
    /// The Settings key.
    public static let storageKey = "hmm.haptics"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    public static func play(_ event: HmmHapticEvent) {
        guard isEnabled else { return }
        #if canImport(UIKit) && !os(watchOS)
            switch event {
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            case .commit:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .undo:
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        #endif
    }
}
