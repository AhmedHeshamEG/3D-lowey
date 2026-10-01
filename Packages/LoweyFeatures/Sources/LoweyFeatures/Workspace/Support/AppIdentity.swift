import Foundation

/// Every user-visible app name and version string comes from here (the product name is not final; the bundle's
/// display name is set once in Config/Branding.xcconfig).
public enum AppIdentity {
    public static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "3D-lowey"
    }

    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public static var version: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(build))"
    }

    public static let subsystem = "studio.hmm.lowey"
    /// The iCloud Drive container (only the App Store build is entitled to it).
    public static let iCloudContainer = "iCloud.studio.hmm.lowey"

    /// Unit / render tests hosted in the app and UI tests: no bridge, no notifications, a clean sandbox.
    public static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    public static let isTestingTour = ProcessInfo.processInfo.arguments.contains("-ui-testing-tour")
    public static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
