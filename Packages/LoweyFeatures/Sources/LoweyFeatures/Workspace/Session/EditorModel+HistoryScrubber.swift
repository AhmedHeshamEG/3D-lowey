import Foundation
import HmmDesign
import HmmDocuments
import LoweyCore

/// What the history scrubber shows (Actions ▸ History).
struct HistoryScrubState: Equatable {
    /// 0 = before the oldest step kept, `count` = now.
    var position: Int
    var count: Int
    /// The step that leads to `position`.
    var label: String?
    var versions: [HistoryVersion] = []

    var isNow: Bool { position == count }
}

/// The history scrubber: drag back through every step, see the stage as it was, restore that moment (the future you
/// leave is kept as a version, so going back never loses anything), name a version, restore one.
extension EditorModel {
    func openHistory() {
        openPanel = nil
        pause()
        while journal.olderUndoCount > 0, let older = try? journal.loadOlderUndo(256), !older.isEmpty {
            session.prependUndo(older)
        }
        let cursor = HistoryCursor(document: session.document, steps: session.undoStack)
        historyCursor = cursor
        historyScrub = HistoryScrubState(position: cursor.position, count: cursor.count, label: cursor.label(at: cursor.position))
        refreshVersions()
    }

    /// Shows the stage as it was at `position`.
    func scrubHistory(to position: Int) {
        guard var cursor = historyCursor, position != cursor.position else { return }
        do {
            let changes = try cursor.move(to: position)
            historyCursor = cursor
            historyPreview = cursor.isNow ? nil : cursor.document
            historyScrub?.position = cursor.position
            historyScrub?.label = cursor.label(at: cursor.position)
            refreshDisplay(changes)
            HmmHaptics.play(.selection)
        } catch {
            logger.error("History step failed: \(String(describing: error))")
        }
    }

    /// Makes the scrubbed moment the present: the steps after it become redo, and the state you left is kept as a
    /// version first. The next edit starts a new branch from here.
    func restoreHistoryHere() {
        guard let cursor = historyCursor, !cursor.isNow else { return closeHistory() }
        let count = cursor.count - cursor.position
        saveAutomaticVersion(named: String(localized: "Before going back \(count) steps"))
        closeHistory()
        for _ in 0 ..< count {
            undo()
        }
        HmmHaptics.play(.commit)
        app.show("Back \(count) steps. Redo goes forward again until you change something.")
    }

    func closeHistory() {
        historyCursor = nil
        historyScrub = nil
        if historyPreview != nil {
            historyPreview = nil
        }
        refreshDisplay(.everything(in: session.document))
    }

    /// Editing while the scrubber shows an earlier moment branches from that moment.
    func settleHistoryBeforeEditing() {
        guard historyScrub != nil else { return }
        if historyCursor?.isNow == false { restoreHistoryHere() } else { closeHistory() }
    }

    // MARK: Versions

    func nameVersion(_ name: String) {
        let versions = journal.versions
        let document = historyPreview ?? session.document
        let title = name.isEmpty ? String(localized: "Version of \(Date().formatted(date: .abbreviated, time: .shortened))") : name
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { _ = try versions.save(document, name: title, automatic: false) }.value
                app.show("Saved “\(title)”")
                refreshVersions()
            } catch {
                app.show("Couldn't save the version: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    /// Replaces the scene with a version (one undo step); the current state is kept as a version first.
    func restoreVersion(_ version: HistoryVersion) {
        let versions = journal.versions
        Task {
            do {
                let document = try await Task.detached(priority: .userInitiated) { try versions.load(version.id) }.value
                closeHistory()
                saveAutomaticVersion(named: String(localized: "Before restoring “\(version.name)”"))
                if perform(.replaceScene(document.scene)) { app.show("Restored “\(version.name)”") }
            } catch {
                app.show("Couldn't open that version: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func refreshVersions() {
        let versions = journal.versions
        Task {
            let list = await Task.detached(priority: .utility) { versions.list() }.value
            historyScrub?.versions = list
        }
    }
}
