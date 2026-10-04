import Foundation

/// Where an app keeps its documents: the iCloud Drive container (synced between the user's devices, visible in
/// Files under the app's name) or the app's own Documents folder (on this device, also visible in Files).
public enum DocumentStorage: Sendable, Hashable {
    case iCloud(URL)
    case local(URL)

    public var folder: URL {
        switch self {
        case let .iCloud(url), let .local(url): url
        }
    }

    public var isICloud: Bool {
        if case .iCloud = self { return true }
        return false
    }
}

/// Finds the documents folder. iCloud Drive is the default; the local folder is used when iCloud is off, signed
/// out, not entitled (sideloaded builds) or when the user chose "On this iPad".
public struct DocumentLocator: Sendable {
    /// e.g. "iCloud.studio.hmm.lowey".
    public var containerIdentifier: String?
    /// The folder name inside Documents (e.g. "Projects").
    public var subfolder: String
    public var localRoot: URL

    public init(containerIdentifier: String?, subfolder: String, localRoot: URL = DocumentLocator.defaultLocalRoot) {
        self.containerIdentifier = containerIdentifier
        self.subfolder = subfolder
        self.localRoot = localRoot
    }

    public static var defaultLocalRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }

    public var localFolder: URL { localRoot.appendingPathComponent(subfolder, isDirectory: true) }

    /// Resolves the storage. The ubiquity lookup can block for a while on first use, so this runs off the main actor.
    public func resolve(preferICloud: Bool = true) async -> DocumentStorage {
        let local = localFolder
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        guard preferICloud, let containerIdentifier else { return .local(local) }
        let ubiquity = await Task.detached(priority: .utility) {
            Self.ubiquityDocuments(containerIdentifier)
        }.value
        guard let ubiquity else { return .local(local) }
        let folder = ubiquity.appendingPathComponent(subfolder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return .iCloud(folder)
        } catch {
            return .local(local)
        }
    }

    private static func ubiquityDocuments(_ identifier: String) -> URL? {
        #if canImport(Darwin)
            guard FileManager.default.ubiquityIdentityToken != nil,
                  let container = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else { return nil }
            return container.appendingPathComponent("Documents", isDirectory: true)
        #else
            _ = identifier
            return nil
        #endif
    }

    /// Moves a document into iCloud Drive or back to this device. The system coordinates the move; it can take a
    /// while, so never call it on the main actor.
    public static func move(_ url: URL, to storage: DocumentStorage) throws -> URL {
        let destination = uniqueURL(for: url.lastPathComponent, in: storage.folder)
        #if canImport(Darwin)
            try FileManager.default.setUbiquitous(storage.isICloud, itemAt: url, destinationURL: destination)
        #else
            try FileManager.default.moveItem(at: url, to: destination)
        #endif
        return destination
    }

    /// `name` in `folder`, or "name 2", "name 3"… when taken.
    public static func uniqueURL(for fileName: String, in folder: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}
