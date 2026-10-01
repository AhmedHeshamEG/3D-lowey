import BackgroundTasks
import Foundation
import os

/// Keeps an export running when 3D-lowey leaves the screen: an iPadOS 26 continued-processing task with the system's
/// progress UI, and the GPU when the device lets background work use it. Without GPU access the export waits (it
/// resumes by itself when the app is back), exactly as before.
@MainActor
final class BackgroundExport {
    static let identifierPrefix = "studio.hmm.lowey.export"
    private var task: BGContinuedProcessingTask?
    private let logger = Logger(subsystem: AppIdentity.subsystem, category: "export")
    /// Called when the system stops the task (the user cancelled it from the system UI, or time ran out).
    var onExpired: (() -> Void)?

    /// Whether this device lets a continued task render on the GPU in the background.
    static var backgroundGPU: Bool {
        BGTaskScheduler.supportedResources.contains(.gpu)
    }

    func begin(title: String, subtitle: String) {
        let identifier = "\(Self.identifierPrefix).\(UUID().uuidString)"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated { self?.started(continued) }
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        if Self.backgroundGPU { request.requiredResources = .gpu }
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.notice("Continued processing unavailable: \(error.localizedDescription)")
        }
    }

    private func started(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.progress.totalUnitCount = 1000
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.onExpired?() }
        }
    }

    func progress(_ fraction: Double) {
        task?.progress.completedUnitCount = Int64(min(max(fraction, 0), 1) * 1000)
    }

    func end(success: Bool) {
        task?.setTaskCompleted(success: success)
        task = nil
    }
}
