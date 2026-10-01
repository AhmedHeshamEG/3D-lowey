import ActivityKit
import Foundation
import LoweyFeatures
import UserNotifications

/// Shows a running export on the Lock Screen and in the Dynamic Island, and posts a notification when it finishes
/// (or fails) while the app is away.
@MainActor
final class ExportLiveActivity: ExportProgressReporting {
    private var activities: [String: Activity<ExportActivityAttributes>] = [:]
    private var lastUpdate: [String: Date] = [:]

    func exportStarted(id: String, title: String) {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ExportActivityAttributes(title: title, project: "")
        let state = ExportActivityAttributes.ContentState(fraction: 0, waiting: false, finished: false)
        activities[id] = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
    }

    func exportProgressed(id: String, fraction: Double, waiting: Bool) {
        guard let activity = activities[id] else { return }
        // A few updates a second at most: the system throttles anyway.
        let now = Date()
        if let last = lastUpdate[id], now.timeIntervalSince(last) < 0.5, !waiting { return }
        lastUpdate[id] = now
        let state = ExportActivityAttributes.ContentState(fraction: fraction, waiting: waiting, finished: false)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func exportFinished(id: String, title: String, files: [URL]) {
        end(id, fraction: 1)
        notify(title: "Export finished", body: "\(title): \(files.first?.lastPathComponent ?? "done")")
    }

    func exportFailed(id: String, title: String, message: String) {
        end(id, fraction: 0)
        notify(title: "Export stopped", body: "\(title): \(message)")
    }

    private func end(_ id: String, fraction: Double) {
        guard let activity = activities.removeValue(forKey: id) else { return }
        lastUpdate[id] = nil
        let state = ExportActivityAttributes.ContentState(fraction: fraction, waiting: false, finished: true)
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 60)) }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in }
    }
}
