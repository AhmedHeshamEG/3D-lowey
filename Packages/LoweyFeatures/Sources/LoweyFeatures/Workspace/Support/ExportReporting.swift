import Foundation

/// Someone who shows an export's progress outside the app (the app's Live Activity and the "finished" notification).
/// The app target sets one on `AppModel` at launch (the Live Activity's attributes live with the widget extension).
@MainActor
public protocol ExportProgressReporting: AnyObject {
    func exportStarted(id: String, title: String)
    func exportProgressed(id: String, fraction: Double, waiting: Bool)
    func exportFinished(id: String, title: String, files: [URL])
    func exportFailed(id: String, title: String, message: String)
}
