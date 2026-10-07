import Foundation

/// Pencil or hand, automatic: who makes and who moves the view.
///
/// Until an Apple Pencil has touched this device, one finger makes (draws, paints, sculpts) and two fingers move the
/// view. From the first Pencil touch on, the Pencil makes and fingers only move the view. One switch in Settings
/// (`fingersAlwaysMake`) lets a finger make even with a Pencil around. Nobody is asked anything at first launch and
/// there's no toggle on the canvas.
public struct HmmPencilOrHand: Sendable, Equatable {
    /// `UserDefaults` keys (shared by every studio app on the device through the app group, when one is given).
    public static let pencilSeenKey = "hmm.pencilSeen"
    public static let fingersAlwaysMakeKey = "hmm.fingersAlwaysMake"

    /// A Pencil has touched this device at least once.
    public private(set) var pencilSeen: Bool
    /// Settings ▸ "Draw with a finger too".
    public var fingersAlwaysMake: Bool

    public init(pencilSeen: Bool = false, fingersAlwaysMake: Bool = false) {
        self.pencilSeen = pencilSeen
        self.fingersAlwaysMake = fingersAlwaysMake
    }

    public init(defaults: UserDefaults) {
        self.init(pencilSeen: defaults.bool(forKey: Self.pencilSeenKey), fingersAlwaysMake: defaults.bool(forKey: Self.fingersAlwaysMakeKey))
    }

    /// One finger makes (two fingers always move the view).
    public var fingerMakes: Bool { fingersAlwaysMake || !pencilSeen }

    /// A Pencil touched. Returns true the first time, when the answer changes and is worth saving.
    @discardableResult
    public mutating func pencilTouched() -> Bool {
        guard !pencilSeen else { return false }
        pencilSeen = true
        return true
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(pencilSeen, forKey: Self.pencilSeenKey)
        defaults.set(fingersAlwaysMake, forKey: Self.fingersAlwaysMakeKey)
    }
}
