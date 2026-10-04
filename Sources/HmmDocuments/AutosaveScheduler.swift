import Foundation

/// Debounced autosave. Every edit reports the document's revision; the save runs `delay` after the last one, off
/// the main actor, and never twice for the same revision. `flush()` saves right away (going to the background,
/// closing the document).
public actor AutosaveScheduler {
    public typealias Save = @Sendable (_ revision: Int) async throws -> Void

    public let delay: Duration
    public private(set) var savedRevision: Int
    public private(set) var lastError: String?
    private var pendingRevision: Int?
    private var pendingSave: Save?
    private var timer: Task<Void, Never>?

    public init(delay: Duration = .milliseconds(1200), savedRevision: Int = 0) {
        self.delay = delay
        self.savedRevision = savedRevision
    }

    /// The document changed; `save` writes `revision` (it runs later, unless another change comes first).
    public func documentChanged(revision: Int, save: @escaping Save) {
        guard revision != savedRevision else { return }
        pendingRevision = revision
        pendingSave = save
        timer?.cancel()
        let delay = delay
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    /// Whether a change is waiting to be written.
    public var hasPendingChanges: Bool { pendingRevision != nil }

    /// Writes any pending change now.
    public func flush() async {
        timer?.cancel()
        timer = nil
        await saveNow()
    }

    /// Marks a revision as saved (after a save done elsewhere, e.g. "Save a copy").
    public func markSaved(_ revision: Int) {
        savedRevision = max(savedRevision, revision)
        if let pendingRevision, pendingRevision <= savedRevision {
            self.pendingRevision = nil
            pendingSave = nil
        }
    }

    private func saveNow() async {
        guard let revision = pendingRevision, let save = pendingSave else { return }
        pendingRevision = nil
        pendingSave = nil
        do {
            try await save(revision)
            savedRevision = max(savedRevision, revision)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            // Keep it pending so the next change (or flush) tries again.
            if pendingRevision == nil {
                pendingRevision = revision
                pendingSave = save
            }
        }
    }
}
