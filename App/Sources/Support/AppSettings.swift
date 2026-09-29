import Foundation

/// Preferences kept on the device (UserDefaults keys). Each one's default is the calm choice.
enum AppSettings {
    /// Show where the Apple Pencil will touch while it hovers (off by default: it follows the Pencil everywhere).
    static let pencilHoverPreview = "pencilHoverPreview"
    /// Draw the stage at the screen's full pixel density (off: 1.75×, about a quarter fewer pixels to shade every frame,
    /// hard to tell apart on a Retina screen; exports always render at full quality).
    static let fullResolutionStage = "fullResolutionStage"
}
