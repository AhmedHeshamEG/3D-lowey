import Foundation

/// The first file of every hmm. document package: which app wrote it, what it is, and its schema.
public struct DocumentManifest: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    /// The writing app ("lowey", "retake", "editoro").
    public var app: String
    /// What the package holds ("project", "take", "template"…).
    public var kind: String
    public var created: Date
    public var modified: Date

    public init(schemaVersion: Int, app: String, kind: String, created: Date = Date(), modified: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.kind = kind
        self.created = created
        self.modified = modified
    }
}

public enum DocumentPackageError: Error, Equatable, CustomStringConvertible {
    case notAPackage(String)
    case wrongApp(expected: String, found: String)
    case newerThanApp(found: Int, supported: Int)
    case missingMigration(from: Int)

    public var description: String {
        switch self {
        case let .notAPackage(name): "\(name) isn't a document this app can open."
        case let .wrongApp(expected, found): "This document belongs to \(found), not \(expected)."
        case let .newerThanApp(found, supported):
            "This document was saved by a newer version of the app (format \(found); this one reads up to \(supported)). Update the app."
        case let .missingMigration(from): "No way to upgrade documents from format \(from)."
        }
    }
}

/// An hmm. document on disk: a folder (a package in Files) holding
///
///     manifest.json      {schemaVersion, app, kind, created, modified}
///     <payload files>    the app's own JSON files, written crash-safe with .bak recovery
///     assets/            media the document owns
///     thumbnail.png      the gallery picture
///
/// Synchronous file IO: call it off the main thread.
public struct DocumentPackage: Sendable, Hashable {
    public static let manifestFile = "manifest.json"
    public static let assetsFolder = "assets"
    public static let thumbnailFile = "thumbnail.png"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var manifestURL: URL { url.appendingPathComponent(Self.manifestFile) }
    public var assetsURL: URL { url.appendingPathComponent(Self.assetsFolder, isDirectory: true) }
    public var thumbnailURL: URL { url.appendingPathComponent(Self.thumbnailFile) }

    /// Creates the folder, `assets/` and the manifest.
    @discardableResult
    public static func create(at url: URL, manifest: DocumentManifest) throws -> DocumentPackage {
        let package = DocumentPackage(url: url)
        try FileManager.default.createDirectory(at: package.assetsURL, withIntermediateDirectories: true)
        try package.writeManifest(manifest)
        return package
    }

    /// The manifest, or nil for a package written before manifests existed (a legacy document to migrate).
    public func readManifest() throws -> DocumentManifest? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let (data, _) = try SafeFileWriter.read(manifestURL) { data in
            _ = try HmmJSON.decode(DocumentManifest.self, from: data)
        }
        return try HmmJSON.decode(DocumentManifest.self, from: data)
    }

    public func writeManifest(_ manifest: DocumentManifest) throws {
        try SafeFileWriter.write(HmmJSON.encode(manifest), to: manifestURL)
    }

    /// Bumps `modified` in the manifest.
    public func touch(_ date: Date = Date()) throws {
        guard var manifest = try readManifest() else { return }
        manifest.modified = date
        try writeManifest(manifest)
    }

    public func fileURL(_ relativePath: String) -> URL {
        url.appendingPathComponent(relativePath)
    }

    /// Writes a payload file crash-safe (atomic, previous good version kept as .bak).
    public func write(_ data: Data, to relativePath: String, keepBackup: Bool = true) throws {
        try SafeFileWriter.write(data, to: fileURL(relativePath), keepBackup: keepBackup)
    }

    /// Reads a payload file, recovering from its .bak when it's damaged.
    public func read(_ relativePath: String, validate: (Data) throws -> Void) throws -> (data: Data, recoveredFromBackup: Bool) {
        try SafeFileWriter.read(fileURL(relativePath), validate: validate)
    }

    public func writeThumbnail(_ png: Data) throws {
        try png.write(to: thumbnailURL, options: .atomic)
    }

    public var thumbnail: Data? {
        try? Data(contentsOf: thumbnailURL)
    }
}

/// One upgrade step of a whole package (files can be added, renamed or rewritten).
public struct PackageMigration: Sendable {
    public let from: Int
    public let migrate: @Sendable (DocumentPackage) throws -> Void

    public init(from: Int, migrate: @escaping @Sendable (DocumentPackage) throws -> Void) {
        self.from = from
        self.migrate = migrate
    }
}

/// Opens packages of one app and kind, upgrading older ones in place.
///
/// Before the first step runs, the package is copied next to itself as `<Name>.v<version>.bak` (never overwritten),
/// so an upgrade can always be undone by hand. Packages without a manifest are legacy documents: `legacyVersion`
/// says which format they are (or nil when the folder isn't one of ours at all).
public struct PackageMigrator: Sendable {
    public var app: String
    public var kind: String
    public var currentVersion: Int
    public var migrations: [PackageMigration]
    public var legacyVersion: @Sendable (DocumentPackage) -> Int?

    public init(app: String, kind: String, currentVersion: Int, migrations: [PackageMigration] = [],
                legacyVersion: @escaping @Sendable (DocumentPackage) -> Int? = { _ in nil }) {
        self.app = app
        self.kind = kind
        self.currentVersion = currentVersion
        self.migrations = migrations
        self.legacyVersion = legacyVersion
    }

    public struct Result: Sendable, Equatable {
        public var manifest: DocumentManifest
        /// The version the package had before it was opened (== current when nothing was done).
        public var upgradedFrom: Int
        /// Where the pre-upgrade copy went.
        public var backup: URL?
    }

    /// The backup folder for a package at a version.
    public static func backupURL(for url: URL, version: Int) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent("\(name).v\(version).bak", isDirectory: true)
    }

    /// Makes sure the package at `url` is at `currentVersion`, upgrading it if needed.
    @discardableResult
    public func open(_ url: URL, now: Date = Date()) throws -> Result {
        let package = DocumentPackage(url: url)
        let existing = try package.readManifest()
        if let existing, existing.app != app { throw DocumentPackageError.wrongApp(expected: app, found: existing.app) }
        guard let version = existing?.schemaVersion ?? legacyVersion(package) else {
            throw DocumentPackageError.notAPackage(url.lastPathComponent)
        }
        if version > currentVersion { throw DocumentPackageError.newerThanApp(found: version, supported: currentVersion) }
        var manifest = existing ?? DocumentManifest(schemaVersion: version, app: app, kind: kind, created: Self.created(url) ?? now,
                                                    modified: Self.modified(url) ?? now)
        guard version < currentVersion || existing == nil else {
            return Result(manifest: manifest, upgradedFrom: version, backup: nil)
        }
        var backup: URL?
        if version < currentVersion {
            let destination = Self.backupURL(for: url, version: version)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: url, to: destination)
            }
            backup = destination
        }
        var step = version
        while step < currentVersion {
            guard let migration = migrations.first(where: { $0.from == step }) else {
                throw DocumentPackageError.missingMigration(from: step)
            }
            try migration.migrate(package)
            step += 1
        }
        manifest.schemaVersion = currentVersion
        try FileManager.default.createDirectory(at: package.assetsURL, withIntermediateDirectories: true)
        try package.writeManifest(manifest)
        return Result(manifest: manifest, upgradedFrom: version, backup: backup)
    }

    private static func created(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
