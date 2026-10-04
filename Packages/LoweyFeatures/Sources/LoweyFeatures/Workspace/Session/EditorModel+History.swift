import Foundation
import HmmDocuments
import LoweyCore
import UIKit

/// The history journal of the open scene (CONTEXT §5): every change reaches the journal moments after it happens,
/// checkpoints come every 200 changes, after 5 s idle and when the app leaves the screen. There is no autosave delay
/// left to lose an edit in.
extension EditorModel {
    /// Undo steps kept in memory before older ones are read back from the journal.
    static let loadedUndoFloor = 16

    /// Hands the session's new ops to the journal; checkpoints when 200 have gathered at a quiet moment.
    func journalChanged() {
        let ops = session.takePendingOps()
        if !ops.isEmpty {
            journal.record(ops)
            if checkpointPolicy.recorded(ops.count, quiet: session.isQuiet) {
                checkpoint()
            }
        }
        scheduleIdleCheckpoint()
    }

    /// A checkpoint once nothing has changed for `ProjectHistory.idleCheckpoint` seconds.
    func scheduleIdleCheckpoint() {
        idleCheckpointTask?.cancel()
        idleCheckpointTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ProjectHistory.idleCheckpoint))
            guard let self, !Task.isCancelled else { return }
            if checkpointPolicy.dueAfterIdle(seconds: ProjectHistory.idleCheckpoint, quiet: session.isQuiet) || hasUncheckpointedState {
                checkpoint()
            }
            noteWorkTime()
        }
    }

    /// Navigation and project info aren't journaled; a checkpoint keeps them.
    var hasUncheckpointedState: Bool { session.revision != checkpointedRevision && session.isQuiet }

    /// Writes a checkpoint and the readable files without waiting.
    func checkpoint() {
        Task { await checkpointNow() }
    }

    /// Writes a checkpoint (the document, the undo history, `project.json` and the scene file) and waits for it.
    func checkpointNow() async {
        guard session.isQuiet else { return }
        journalChanged()
        idleCheckpointTask?.cancel()
        session.updateProjectInfo { $0.modified = Date() }
        checkpointPolicy.checkpointed()
        checkpointedRevision = session.revision
        isSaving = true
        let failure: Error? = await withCheckedContinuation { continuation in
            ProjectHistory.checkpoint(session.document, history: session.history, journal: journal, store: store, project: projectURL) { error in
                continuation.resume(returning: error)
            }
        }
        isSaving = false
        if let failure {
            logger.error("Checkpoint failed: \(String(describing: failure))")
            app.show("Couldn't save: \(failure.localizedDescription)", kind: .error)
        } else {
            lastSaved = Date()
        }
    }

    /// A checkpoint, the journal pushed to storage, the restoration state and (optionally) a fresh Home card.
    func saveNow(thumbnail: Bool) async {
        await checkpointNow()
        let journal = journal
        await Task.detached(priority: .userInitiated) { journal.flush() }.value
        SessionRestoration(self).save()
        if thumbnail { await writeProjectThumbnail() }
    }

    /// Reads older undo steps back from the journal when undo gets near the bottom of what's loaded.
    func loadOlderUndoIfNeeded() {
        guard session.undoStack.count < Self.loadedUndoFloor, journal.olderUndoCount > 0 else { return }
        do {
            session.prependUndo(try journal.loadOlderUndo(64))
        } catch {
            logger.error("Older undo steps unreadable: \(String(describing: error))")
            journal.discardOlderUndo()
        }
    }

    /// Switches the editor to a scene opened through its journal.
    func adopt(_ opened: ProjectHistory.Opened) {
        journal.flush()
        journal = opened.journal
        session = opened.session
        checkpointPolicy = CheckpointPolicy()
        checkpointedRevision = session.revision
        workStarted = Date()
        saveAutomaticVersion(named: String(localized: "Opened \(Date().formatted(date: .abbreviated, time: .shortened))"))
        if opened.replayed > 0 {
            logger.info("Recovered \(opened.replayed) changes from the journal")
        }
    }

    // MARK: Automatic versions

    /// Every hour of work leaves an automatic version (the opening of each session leaves one too).
    func noteWorkTime() {
        guard Date().timeIntervalSince(workStarted) >= 3600 else { return }
        workStarted = Date()
        saveAutomaticVersion(named: String(localized: "An hour of work, \(Date().formatted(date: .omitted, time: .shortened))"))
    }

    func saveAutomaticVersion(named name: String) {
        let versions = journal.versions
        let document = session.document
        Task.detached(priority: .utility) {
            _ = try? versions.save(document, name: name, automatic: true)
        }
    }
}
