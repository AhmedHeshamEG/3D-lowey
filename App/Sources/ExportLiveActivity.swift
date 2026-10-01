import ActivityKit
import Foundation
import LoweyFeatures
import UserNotifications

/// Shows a running export on the Lock Screen and in the Dynamic Island, and posts a notification when it finishes
/// (or fails) while the app is away.
@MainActor
final class ExportLiveActivity: ExportProgressReporting {
    /// Export id → Live Activity id (the activities themselves aren't Sendable; they are looked up where they're used).
    private var activities: [String: String] = [:]
    private var lastUpdate: [String: Date] = [:]

    func exportStarted(id: String, title: String) {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ExportActivityAttributes(title: title, project: "")
        let state = ExportActivityAttributes.ContentState(fraction: 0, waiting: false, finished: false)
        activities[id] = (try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil)))?.id
    }

    func exportProgressed(id: String, fraction: Double, waiting: Bool) {
        guard let activityID = activities[id] else { return }
        // A few updates a second at most: the system throttles anyway.
        let now = Date()
        if let last = lastUpdate[id], now.timeIntervalSince(last) < 0.5, !waiting { return }
        lastUpdate[id] = now
        let state = ExportActivityAttributes.ContentState(fraction: fraction, waiting: waiting, finished: false)
        Task { await Self.apply(state, to: activityID, ending: false) }
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
        guard let activityID = activities.removeValue(forKey: id) else { return }
        lastUpdate[id] = nil
        let state = ExportActivityAttributes.ContentState(fraction: fraction, waiting: false, finished: true)
        Task { await Self.apply(state, to: activityID, ending: true) }
    }

    /// Updates or ends a Live Activity, found by its id here so no `Activity` value crosses actors.
    private nonisolated static func apply(_ state: ExportActivityAttributes.ContentState, to activityID: String, ending: Bool) async {
        guard let activity = Activity<ExportActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if ending {
            await activity.end(content, dismissalPolicy: .after(.now + 60))
        } else {
            await activity.update(content)
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in }
    }
}
