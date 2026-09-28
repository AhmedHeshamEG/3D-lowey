import Foundation

/// Reads "stored" (uncompressed) zip archives — the ones `ZipWriter` makes (.lowey packages, diagnostics).
public enum ZipReader {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAZip
        case compressed(String)
        case damaged(String)

        public var description: String {
            switch self {
            case .notAZip: "That isn't a zip archive"
            case let .compressed(name): "\(name) is compressed — export the project from 3D-lowey (packages are stored, not compressed)"
            case let .damaged(name): "\(name) is damaged (checksum)"
            }
        }
    }

    public static func entries(_ data: Data) throws -> [(name: String, data: Data)] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        // End of central directory: scan back from the end (comment ≤ 64 KB).
        var end = -1
        var index = bytes.count - 22
        while index >= max(0, bytes.count - 65558) {
            if u32(index) == 0x0605_4B50 {
                end = index
                break
            }
            index -= 1
        }
        guard end >= 0 else { throw Failure.notAZip }
        let count = u16(end + 10)
        var cursor = u32(end + 16)
        var result: [(String, Data)] = []
        for _ in 0 ..< count {
            guard cursor + 46 <= bytes.count, u32(cursor) == 0x0201_4B50 else { throw Failure.notAZip }
            let method = u16(cursor + 10)
            let crc = UInt32(truncatingIfNeeded: u32(cursor + 16))
            let size = u32(cursor + 20)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let local = u32(cursor + 42)
            let name = String(bytes: bytes[cursor + 46 ..< cursor + 46 + nameLength], encoding: .utf8) ?? ""
            guard method == 0 else { throw Failure.compressed(name) }
            guard local + 30 <= bytes.count, u32(local) == 0x0403_4B50 else { throw Failure.notAZip }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + size <= bytes.count else { throw Failure.damaged(name) }
            let content = Data(bytes[start ..< start + size])
            guard CRC32.checksum(content) == crc else { throw Failure.damaged(name) }
            result.append((name, content))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }
}

/// `.lowey` packages: a whole project (scenes, audio, renders, embedded assets) in one file to share or back up.
public enum ProjectPackage {
    public static let fileExtension = "loweypack"

    /// Every file of the project folder, paths relative to it. Renders are left out unless asked (they're big).
    public static func archive(_ project: URL, includeRenders: Bool = false) throws -> Data {
        let fileManager = FileManager.default
        let base = project.standardizedFileURL.path
        var files: [(name: String, data: Data)] = []
        guard let walker = fileManager.enumerator(at: project, includingPropertiesForKeys: [.isDirectoryKey]) else { return Data() }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            var relative = url.standardizedFileURL.path
            guard relative.hasPrefix(base) else { continue }
            relative = String(relative.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !includeRenders, relative.hasPrefix(ProjectLayout.rendersFolder + "/") { continue }
            if relative.hasSuffix(".bak") { continue }
            try files.append((relative, Data(contentsOf: url)))
        }
        files.sort { $0.name < $1.name }
        return ZipWriter.storedArchive(files)
    }

    /// Unpacks into `store` as a new project (fresh id, unique folder name). Returns its URL.
    public static func unpack(_ data: Data, into store: ProjectStore) throws -> URL {
        let entries = try ZipReader.entries(data)
        guard let projectFile = entries.first(where: { $0.name == ProjectLayout.projectFile }) else {
            throw ProjectStoreError.notAProject("the package")
        }
        var info = try store.coder.decode(ProjectInfo.self, kind: .project, from: projectFile.data)
        info.id = .make()
        info.modified = Date()
        let url = store.uniqueURL(for: info.name)
        let fileManager = FileManager.default
        for folder in [ProjectLayout.scenesFolder, ProjectLayout.assetsFolder, ProjectLayout.audioFolder, ProjectLayout.rendersFolder] {
            try fileManager.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for entry in entries where entry.name != ProjectLayout.projectFile {
            // Never write outside the project folder.
            guard !entry.name.contains(".."), !entry.name.hasPrefix("/") else { continue }
            let target = url.appendingPathComponent(entry.name)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: target, options: .atomic)
        }
        try SafeFileWriter.write(store.coder.encode(info, kind: .project), to: url.appendingPathComponent(ProjectLayout.projectFile))
        return url
    }
}

public extension ProjectStore {
    static let archiveFolder = "Archive"

    var archiveRoot: URL { root.appendingPathComponent(Self.archiveFolder) }

    /// Moves a project out of the way (kept, not deleted).
    func archiveProject(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        var target = archiveRoot.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = archiveRoot.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(counter).\(ProjectLayout.fileExtension)")
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    func listArchived() -> [ProjectSummary] {
        ProjectStore(root: archiveRoot, coder: coder).listProjects()
    }

    func unarchiveProject(at url: URL) throws -> URL {
        let target = uniqueURL(for: url.deletingPathExtension().lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// Copies a scene into another project (new scene id; audio files it uses come along).
    func copyScene(_ id: SceneID, from source: URL, to destination: URL) throws -> Scene {
        var (scene, _) = try loadScene(id, in: source)
        scene.id = .make()
        var (info, _) = try loadProjectInfo(at: destination)
        let names = Set(info.sceneNames.values)
        var name = scene.name
        var counter = 2
        while names.contains(name) {
            name = "\(scene.name) \(counter)"
            counter += 1
        }
        scene.name = name
        try SafeFileWriter.write(coder.encode(scene, kind: .scene), to: ProjectLayout.sceneURL(scene.id, in: destination))
        let fileManager = FileManager.default
        for clip in scene.timeline.audio {
            let from = source.appendingPathComponent(ProjectLayout.audioFolder).appendingPathComponent(clip.file)
            let to = destination.appendingPathComponent(ProjectLayout.audioFolder).appendingPathComponent(clip.file)
            if fileManager.fileExists(atPath: from.path), !fileManager.fileExists(atPath: to.path) {
                try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: from, to: to)
            }
        }
        info.sceneOrder.append(scene.id)
        info.sceneNames[scene.id] = scene.name
        info.modified = Date()
        try SafeFileWriter.write(coder.encode(info, kind: .project), to: destination.appendingPathComponent(ProjectLayout.projectFile))
        return scene
    }
}
