import Foundation

/// The product name lives in ONE place: `Config/Branding.xcconfig` (APP_DISPLAY_NAME).
/// Info.plist reads it, and the app reads it back from the bundle.
enum Branding {
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "3D-lowey"
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
}
