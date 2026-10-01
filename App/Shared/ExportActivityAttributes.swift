import ActivityKit
import Foundation

/// The export's Live Activity (shared by the app, which starts and updates it, and the widget extension, which draws
/// it on the Lock Screen and in the Dynamic Island).
struct ExportActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0…1.
        var fraction: Double
        /// Paused because the app can't use the GPU in the background right now.
        var waiting: Bool
        var finished: Bool
    }

    /// What is exporting ("YouTube 16:9 4K").
    var title: String
    var project: String
}
