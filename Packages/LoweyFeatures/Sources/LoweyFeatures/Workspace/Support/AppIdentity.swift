import Foundation

/// Every user-visible app name and version string comes from here (the product name is not final; the bundle's
/// display name is set once in Config/Branding.xcconfig).
public enum AppIdentity {
    public static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Maquette"
    }

    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public static var version: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(build))"
    }

    public static let subsystem = "studio.h.maquette"
    /// The iCloud Drive container (only the App Store build is entitled to it).
    public static let iCloudContainer = "iCloud.studio.h.maquette"
    /// Shared with the widget extension (and Cutaway later).
    public static let appGroup = "group.studio.h"

    /// Unit / render tests hosted in the app and UI tests: no bridge, no notifications, a clean sandbox.
    public static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    public static let isTestingTour = ProcessInfo.processInfo.arguments.contains("-ui-testing-tour")
    /// App Store screenshots: UI testing without the debug overlays.
    public static let isTakingScreenshots = ProcessInfo.processInfo.arguments.contains("-ui-testing-screenshots")
    public static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
