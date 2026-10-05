import Foundation
import HmmDesign
import LoweyCore

/// How the open project shows (`workspace.json`): the timeline on call and its height, snapping, the grid, the
/// starter template's first panel. Written moments after it changes; it isn't the project, so it's never undone.
extension EditorModel {
    func loadWorkspace() {
        workspace = store.loadWorkspace(at: projectURL)
        timelinePresence = workspace.timeline
        timelineHeight = workspace.timelineHeight
        snap = workspace.snap
        showsGrid = workspace.showsGrid
        units = workspace.units
        precision.section = workspace.section
        precision.printBed = workspace.printBed
        precision.showsDimensions = workspace.showsDimensions
        if let first = workspace.firstPanel.flatMap(ClusterPanel.init(rawValue:)) {
            openPanel = first
            workspace.firstPanel = nil
            saveWorkspace()
        }
    }

    /// Something shown changed: write the workspace shortly (a resize or a run of toggles is one write).
    func workspaceChanged() {
        workspaceSaveTask?.cancel()
        workspaceSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard let self, !Task.isCancelled else { return }
            saveWorkspace()
        }
    }

    func saveWorkspace() {
        workspaceSaveTask?.cancel()
        workspace.timeline = timelinePresence
        workspace.timelineHeight = timelineHeight
        workspace.snap = snap
        workspace.showsGrid = showsGrid
        workspace.units = units
        workspace.section = precision.section
        workspace.printBed = precision.printBed
        workspace.showsDimensions = precision.showsDimensions
        do {
            try store.saveWorkspace(workspace, at: projectURL)
        } catch {
            logger.error("Couldn't save the workspace: \(error.localizedDescription)")
        }
    }

    // MARK: The timeline on call

    /// The corner control: calls the slim transport, or sends the timeline away.
    func toggleTimeline() {
        HmmHaptics.play(.selection)
        timelinePresence = timelinePresence == .hidden ? .transport : .hidden
    }

    /// Animate: the whole timeline (again: it goes back to the transport).
    func toggleAnimate() {
        HmmHaptics.play(.selection)
        openPanel = nil
        timelinePresence = timelinePresence == .full ? .transport : .full
    }

    /// The divider was dragged to a new height (points).
    func setTimelineHeight(_ height: Double) {
        let range = ProjectWorkspace.timelineHeightRange
        timelineHeight = min(max(height, range.lowerBound), range.upperBound)
        workspaceChanged()
    }

    /// New shapes are this many metres (the starter template's size; 1 m otherwise).
    var newShapeScale: Double { workspace.shapeSize }
}
