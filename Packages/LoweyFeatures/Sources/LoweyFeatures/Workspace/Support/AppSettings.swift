import Foundation

/// Preferences kept on this device. Each default is the calm choice.
public enum AppSettings {
    /// Show where the Apple Pencil will land while it hovers (off: it would follow the Pencil everywhere).
    public static let pencilHoverPreview = "pencilHoverPreview"
    /// Draw the stage at the screen's full pixel density and never lower the render scale (off: dynamic scale).
    public static let fullResolutionStage = "fullResolutionStage"
    /// Off: the inspector floats beside the selection (the default). On: it stays docked at the side.
    public static let inspectorDocked = "inspectorDocked"
    /// How fast the joystick moves, turns and sizes things (1 = normal).
    public static let joystickSpeed = "joystickSpeed"
    public static let joystickSpeedRange = 0.25 ... 3.0
    /// The on-screen joystick under a selection (on by default; its own × or Settings ▸ Stage hides it).
    public static let showsJoystick = "showsJoystick"
    /// How fast fingers move around the scene: orbit, pan, pinch zoom (1 = normal).
    public static let navigationSpeed = "navigationSpeed"
    public static let navigationSpeedRange = 0.25 ... 3.0
    /// The left sidebar on the right edge (left-handed use).
    public static let sidebarOnRight = "sidebarOnRight"
    /// The Performance HUD over the stage.
    public static let showsPerformanceHUD = "showsPerformanceHUD"
    /// Projects in iCloud Drive (when the build is entitled and the user is signed in) or on this iPad.
    public static let storeInICloud = "storeInICloud"
    /// The 60-second tour was seen (it never comes back by itself; Settings replays it).
    public static let tourSeen = "tourSeen"

    /// The navigation speed, clamped (read when a gesture starts).
    public static var navigationFactor: Double {
        clamped(UserDefaults.standard.object(forKey: navigationSpeed) as? Double ?? 1, to: navigationSpeedRange)
    }

    public static var joystickFactor: Double {
        clamped(UserDefaults.standard.object(forKey: joystickSpeed) as? Double ?? 1, to: joystickSpeedRange)
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
