import Foundation

/// A project on disk, as listed on the Home screen.
public struct ProjectSummary: Hashable, Sendable, Identifiable {
    public var url: URL
    public var info: ProjectInfo
    public var id: ProjectID { info.id }
    public var thumbnailURL: URL { url.appendingPathComponent(ProjectLayout.thumbnail) }
}

/// The `.lowey` project folder format (visible in the Files app):
///
///     MyVideo.lowey/
///       project.json
///       scenes/<scene-id>.json
///       assets/          copies of library assets (written by "Export project")
///       audio/
///       renders/
///       thumbnail.png
public enum ProjectLayout {
    public static let fileExtension = "lowey"
    public static let projectFile = "project.json"
    public static let scenesFolder = "scenes"
    public static let assetsFolder = "assets"
    public static let audioFolder = "audio"
    public static let rendersFolder = "renders"
    public static let thumbnail = "thumbnail.png"

    public static func sceneURL(_ id: SceneID, in project: URL) -> URL {
        project.appendingPathComponent(scenesFolder).appendingPathComponent("\(id.raw).json")
    }
}

public enum ProjectStoreError: Error, Equatable, CustomStringConvertible {
    case notAProject(String)
    case sceneMissing(SceneID)
    case lastScene

    public var description: String {
        switch self {
        case let .notAProject(path): "\(path) is not a 3D-lowey project"
        case let .sceneMissing(id): "Scene \(id) is missing from the project"
        case .lastScene: "A project needs at least one scene"
        }
    }
}

/// Reads and writes projects. Synchronous file IO: call it off the main thread.
public struct ProjectStore: Sendable {
    public let root: URL
    public var coder: SchemaCoder

    public init(root: URL, coder: SchemaCoder = .shared) {
        self.root = root
        self.coder = coder
    }

    // MARK: Listing

    public func listProjects() -> [ProjectSummary] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == ProjectLayout.fileExtension }
            .compactMap { url in (try? loadProjectInfo(at: url)).map { ProjectSummary(url: url, info: $0.info) } }
            .sorted { $0.info.modified > $1.info.modified }
    }

    // MARK: Create / delete / duplicate / rename

    /// Creates a project with one empty scene and returns its URL and first document.
    public func createProject(name: String, look: Look = .default, firstSceneName: String = "Scene 1") throws -> (URL, Document) {
        let url = uniqueURL(for: name)
        let fileManager = FileManager.default
        for folder in [ProjectLayout.scenesFolder, ProjectLayout.assetsFolder, ProjectLayout.audioFolder, ProjectLayout.rendersFolder] {
            try fileManager.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let scene = Scene(id: .make(), name: firstSceneName)
        let info = ProjectInfo(
            id: .make(), name: name, look: look,
            sceneOrder: [scene.id], sceneNames: [scene.id: scene.name], lastOpenedScene: scene.id
        )
        let document = Document(project: info, scene: scene)
        try save(document, to: url)
        return (url, document)
    }

    /// Writes a complete, already-built project (used by samples and imports).
    public func writeProject(info: ProjectInfo, scenes: [Scene]) throws -> URL {
        let url = uniqueURL(for: info.name)
        let fileManager = FileManager.default
        for folder in [ProjectLayout.scenesFolder, ProjectLayout.assetsFolder, ProjectLayout.audioFolder, ProjectLayout.rendersFolder] {
            try fileManager.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        var info = info
        info.sceneOrder = scenes.map(\.id)
        info.sceneNames = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0.name) })
        if info.lastOpenedScene == nil { info.lastOpenedScene = scenes.first?.id }
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
        for scene in scenes {
            try SafeFileWriter.write(coder.encode(scene, kind: .scene), to: ProjectLayout.sceneURL(scene.id, in: url))
        }
        return url
    }

    public func deleteProject(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func duplicateProject(at url: URL) throws -> URL {
        let (info, _) = try loadProjectInfo(at: url)
        let copyURL = uniqueURL(for: "\(info.name) copy")
        try FileManager.default.copyItem(at: url, to: copyURL)
        var copy = info
        copy.id = .make()
        copy.name = "\(info.name) copy"
        copy.created = Date()
        copy.modified = Date()
        try SafeFileWriter.write(coder.encode(copy, kind: .project), to: copyURL.appendingPathComponent(ProjectLayout.projectFile))
        return copyURL
    }

    /// Renames the project and its folder. Returns the new URL.
    public func renameProject(at url: URL, to name: String) throws -> URL {
        var (info, _) = try loadProjectInfo(at: url)
        info.name = name
        info.modified = Date()
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
        let target = uniqueURL(for: name)
        guard target.lastPathComponent != url.lastPathComponent else { return url }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    // MARK: Load

    public func loadProjectInfo(at url: URL) throws -> (info: ProjectInfo, recovered: Bool) {
        let file = url.appendingPathComponent(ProjectLayout.projectFile)
        guard FileManager.default.fileExists(atPath: file.path)
            || FileManager.default.fileExists(atPath: SafeFileWriter.backupURL(for: file).path)
        else {
            throw ProjectStoreError.notAProject(url.lastPathComponent)
        }
        var info: ProjectInfo?
        let result = try SafeFileWriter.read(file) { data in
            info = try coder.decode(ProjectInfo.self, kind: .project, from: data)
        }
        guard let info else { throw ProjectStoreError.notAProject(url.lastPathComponent) }
        return (info, result.recoveredFromBackup)
    }

    public func loadScene(_ id: SceneID, in url: URL) throws -> (scene: Scene, recovered: Bool) {
        let file = ProjectLayout.sceneURL(id, in: url)
        var scene: Scene?
        let result: (data: Data, recoveredFromBackup: Bool)
        do {
            result = try SafeFileWriter.read(file) { data in
                scene = try coder.decode(Scene.self, kind: .scene, from: data)
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw ProjectStoreError.sceneMissing(id)
        }
        guard let scene else { throw ProjectStoreError.sceneMissing(id) }
        return (scene, result.recoveredFromBackup)
    }

    /// Opens a project on its last scene (or first).
    public func openDocument(at url: URL, scene sceneID: SceneID? = nil) throws -> Document {
        let (info, _) = try loadProjectInfo(at: url)
        guard let target = sceneID ?? info.lastOpenedScene ?? info.sceneOrder.first else {
            throw ProjectStoreError.sceneMissing(SceneID(raw: "none"))
        }
        let (scene, _) = try loadScene(target, in: url)
        return Document(project: info, scene: scene)
    }

    // MARK: Save

    /// Saves project info and the document's scene atomically (each file).
    public func save(_ document: Document, to url: URL, touch: Bool = true) throws {
        var info = document.project
        if touch { info.modified = Date() }
        info.sceneNames[document.scene.id] = document.scene.name
        if !info.sceneOrder.contains(document.scene.id) { info.sceneOrder.append(document.scene.id) }
        info.lastOpenedScene = document.scene.id
        try SafeFileWriter.write(coder.encode(document.scene, kind: .scene), to: ProjectLayout.sceneURL(document.scene.id, in: url))
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
    }

    /// Adds a new empty scene (inheriting the project look) and returns it.
    public func addScene(named name: String, to url: URL) throws -> Scene {
        var (info, _) = try loadProjectInfo(at: url)
        let scene = Scene(id: .make(), name: name)
        info.sceneOrder.append(scene.id)
        info.sceneNames[scene.id] = name
        try SafeFileWriter.write(coder.encode(scene, kind: .scene), to: ProjectLayout.sceneURL(scene.id, in: url))
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
        return scene
    }

    /// Copies a scene inside the project.
    public func duplicateScene(_ id: SceneID, in url: URL) throws -> Scene {
        var (info, _) = try loadProjectInfo(at: url)
        var (scene, _) = try loadScene(id, in: url)
        scene.id = .make()
        scene.name = "\(scene.name) copy"
        if let index = info.sceneOrder.firstIndex(of: id) {
            info.sceneOrder.insert(scene.id, at: index + 1)
        } else {
            info.sceneOrder.append(scene.id)
        }
        info.sceneNames[scene.id] = scene.name
        try SafeFileWriter.write(coder.encode(scene, kind: .scene), to: ProjectLayout.sceneURL(scene.id, in: url))
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
        return scene
    }

    public func deleteScene(_ id: SceneID, in url: URL) throws {
        var (info, _) = try loadProjectInfo(at: url)
        guard info.sceneOrder.count > 1 else { throw ProjectStoreError.lastScene }
        info.sceneOrder.removeAll { $0 == id }
        info.sceneNames[id] = nil
        if info.lastOpenedScene == id { info.lastOpenedScene = info.sceneOrder.first }
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
        let file = ProjectLayout.sceneURL(id, in: url)
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: SafeFileWriter.backupURL(for: file))
    }

    public func writeThumbnail(_ png: Data, for url: URL) throws {
        try png.write(to: url.appendingPathComponent(ProjectLayout.thumbnail), options: .atomic)
    }

    // MARK: Helpers

    /// A folder name derived from the project name, unique inside `root`.
    public func uniqueURL(for name: String) -> URL {
        let base = Self.sanitize(name)
        var candidate = root.appendingPathComponent("\(base).\(ProjectLayout.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base) \(counter).\(ProjectLayout.fileExtension)")
            counter += 1
        }
        return candidate
    }

    public static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) }
        let result = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Untitled" : String(result.prefix(80))
    }
}

/// Serializes saves off the main thread, one at a time, always writing the newest document.
public actor DocumentSaver {
    private let store: ProjectStore
    private var lastSavedRevision: [URL: Int] = [:]

    public init(store: ProjectStore) {
        self.store = store
    }

    /// Saves if `revision` is newer than what was last saved for `url`. Returns true if written.
    @discardableResult
    public func save(_ document: Document, revision: Int, to url: URL) throws -> Bool {
        if let saved = lastSavedRevision[url], saved >= revision { return false }
        try store.save(document, to: url)
        lastSavedRevision[url] = revision
        return true
    }

    public func markSaved(_ revision: Int, for url: URL) {
        lastSavedRevision[url] = revision
    }
}
