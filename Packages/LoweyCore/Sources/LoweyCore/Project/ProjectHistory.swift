import Foundation
import HmmCommands
import HmmDocuments

/// Maquette's history journal (CONTEXT §5): one per scene, in `<project>/history/<scene-id>/`.
///
/// Every command is a line in the journal moments after it happens; a checkpoint (every 200 changes, after 5 s idle,
/// when the app leaves the screen or the scene closes) writes the document and the undo history, then `project.json`
/// and the scene file, which stay the readable surface of the project (`docs/PROJECT_FORMAT.md`). Opening a scene
/// is its latest checkpoint plus the changes after it, so a killed app loses nothing and undo survives a relaunch.
public enum ProjectHistory {
    public static let folder = "history"
    /// Changes between checkpoints.
    public static let checkpointEvery = 200
    /// Seconds without a change before a checkpoint.
    public static let idleCheckpoint: Double = 5
    /// Undo steps a scene keeps.
    public static let historyLimit = 500

    public static func url(scene: SceneID, in project: URL) -> URL {
        project.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(scene.raw, isDirectory: true)
    }

    /// Recorded ops use the document schema (`LoweySchema`): a schema change that alters a command's JSON adds an
    /// op migration here, keyed by the version it upgrades from (a Core test fails when one is missing).
    public static let opMigrations: [Int: HistoryJournalFormat<EditCommand>.Migration] = [
        // 4 → 5 only adds object kinds (`mesh`, `sketch`): schema-4 commands read as they are.
        4: { $0 },
        // 5 → 6 only adds an object kind (`dimension`).
        5: { $0 },
        // 6 → 7 only adds optional brush fields and the `setBrushes` command.
        6: { $0 },
        // 7 → 8 only adds the optional paint field and the `setPaint` and `paintTiles` commands.
        7: { $0 },
        // 8 → 9 only adds the optional rig field and the `setRig` command.
        8: { $0 },
        // 9 → 10 only adds the `bounce` and `swing` behaviours (inside `setTimeline`).
        9: { $0 },
        // 10 → 11 only adds the optional takes field and the `setTakes` command.
        10: { $0 }
    ]
    /// The first schema journals were written with (Maquette 0.1).
    public static let firstJournalSchema = 4

    public static func format(coder: SchemaCoder = .shared) -> HistoryJournalFormat<EditCommand> {
        HistoryJournalFormat(
            schemaVersion: coder.currentVersion, migrations: opMigrations, eagerUndo: 64,
            encodeDocument: { try encodeSnapshot($0, coder: coder) }, decodeDocument: { try decodeSnapshot($0, coder: coder) }
        )
    }

    // MARK: Snapshots

    /// A checkpoint's document: `{schemaVersion, kind: "document", payload: {project, scene}}`.
    public static func encodeSnapshot(_ document: Document, coder: SchemaCoder = .shared) throws -> Data {
        try coder.encode(document, kind: "document")
    }

    /// Reads a snapshot; one from an older schema migrates its project and scene through their own chains.
    public static func decodeSnapshot(_ data: Data, coder: SchemaCoder = .shared) throws -> Document {
        if let file = try? HmmJSON.decode(VersionedFile<Document>.self, from: data), file.schemaVersion == coder.currentVersion {
            return file.payload
        }
        let raw = try HmmJSON.decode(JSONValue.self, from: data)
        let version = raw["schemaVersion"] ?? .number(0)
        func part(_ key: String, _ kind: FileKind) throws -> Data {
            let envelope = JSONValue.object(["schemaVersion": version, "kind": .string(kind.rawValue), "payload": raw["payload"]?[key] ?? .null])
            return try HmmJSON.encode(envelope)
        }
        return try Document(
            project: coder.decode(ProjectInfo.self, kind: .project, from: part("project", .project)),
            scene: coder.decode(Scene.self, kind: .scene, from: part("scene", .scene))
        )
    }

    // MARK: Opening

    /// A scene opened through its journal.
    public struct Opened: Sendable {
        public var journal: HistoryJournal<EditCommand>
        public var session: EditSession
        /// Changes replayed after the checkpoint (what a killed app hadn't checkpointed).
        public var replayed: Int
        /// Changes at the end that couldn't be read back (a write cut short).
        public var skipped: Int
        /// The journal began now (a 3D-lowey project, or a scene never opened in Maquette).
        public var isNew: Bool
    }

    /// Opens a scene (the last one opened by default) from its journal, or starts the journal from the scene file.
    /// Synchronous file IO: call it off the main thread.
    public static func open(
        _ project: URL, scene sceneID: SceneID? = nil, store: ProjectStore, onError: @escaping @Sendable (Error) -> Void = { _ in }
    ) throws -> Opened {
        try ProjectLayout.migrator.open(project)
        let (info, _) = try store.loadProjectInfo(at: project)
        guard let target = sceneID ?? info.lastOpenedScene ?? info.sceneOrder.first else {
            throw ProjectStoreError.sceneMissing(SceneID(raw: "none"))
        }
        let (journal, opened) = try HistoryJournal.open(
            at: url(scene: target, in: project), format: format(coder: store.coder), historyLimit: historyLimit, onError: onError
        ) {
            try store.openDocument(at: project, scene: target)
        }
        var document = opened.document
        document.project = merged(journal: document.project, file: info, replayed: opened.replayed, scene: target)
        return Opened(
            journal: journal, session: EditSession(document: document, history: opened.history),
            replayed: opened.replayed, skipped: opened.skipped, isNew: opened.source == .fresh
        )
    }

    /// The project info to edit with. `project.json` holds what other scenes and the Home screen changed (scene list,
    /// names, the project name); the journal holds this scene's own changes. When nothing was replayed and the file
    /// is newer (another scene changed the project look since), the file wins entirely.
    static func merged(journal: ProjectInfo, file: ProjectInfo, replayed: Int, scene: SceneID) -> ProjectInfo {
        if replayed == 0, file.modified >= journal.modified { return file }
        var info = journal
        info.name = file.name
        info.created = file.created
        info.sceneOrder = file.sceneOrder
        info.sceneNames = file.sceneNames.merging([scene: journal.sceneNames[scene] ?? file.sceneNames[scene] ?? ""]) { _, mine in mine }
        if !info.sceneOrder.contains(scene) { info.sceneOrder.append(scene) }
        return info
    }

    /// Writes a checkpoint, then `project.json` and the scene file from the same document (the readable surface).
    /// Stamp `document.project.modified` first: opening compares it with `project.json`'s. `done` runs on the journal's
    /// queue.
    public static func checkpoint(
        _ document: Document, history: CommandStack<EditCommand>, journal: HistoryJournal<EditCommand>, store: ProjectStore, project: URL,
        done: (@Sendable (Error?) -> Void)? = nil
    ) {
        journal.checkpoint(document, history: history) {
            do {
                try store.save(document, to: project, touch: false)
                done?(nil)
            } catch {
                done?(error)
            }
        }
    }

    /// Removes a deleted scene's journal.
    public static func remove(scene: SceneID, in project: URL) {
        try? FileManager.default.removeItem(at: url(scene: scene, in: project))
    }
}

/// When to checkpoint: every `ProjectHistory.checkpointEvery` changes, or after `idleCheckpoint` seconds without one,
/// and only at a quiet moment (no gesture or group still open).
public struct CheckpointPolicy: Sendable, Equatable {
    public var every: Int
    public var idle: Double
    public private(set) var changes = 0

    public init(every: Int = ProjectHistory.checkpointEvery, idle: Double = ProjectHistory.idleCheckpoint) {
        self.every = every
        self.idle = idle
    }

    /// Counts recorded changes; true when a checkpoint is due now.
    public mutating func recorded(_ count: Int, quiet: Bool) -> Bool {
        changes += count
        return quiet && changes >= every
    }

    /// True when changes are waiting and the document has been idle long enough.
    public func dueAfterIdle(seconds: Double, quiet: Bool) -> Bool {
        quiet && changes > 0 && seconds >= idle
    }

    public mutating func checkpointed() {
        changes = 0
    }
}
