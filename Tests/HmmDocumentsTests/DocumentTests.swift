import Foundation
@testable import HmmDocuments
import XCTest

final class DocumentTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: SafeFileWriter

    func testWriteKeepsAGoodBackupAndRecovers() throws {
        let url = folder.appendingPathComponent("a.json")
        try SafeFileWriter.write(Data(#"{"v":1}"#.utf8), to: url)
        try SafeFileWriter.write(Data(#"{"v":2}"#.utf8), to: url)
        try Data("garbage".utf8).write(to: url)
        let (data, recovered) = try SafeFileWriter.read(url) { _ = try HmmJSON.decode(JSONValue.self, from: $0) }
        XCTAssertTrue(recovered)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"v":1}"#)
    }

    func testDamagedFileNeverOverwritesAGoodBackup() throws {
        let url = folder.appendingPathComponent("b.json")
        try SafeFileWriter.write(Data(#"{"v":1}"#.utf8), to: url)
        try SafeFileWriter.write(Data(#"{"v":2}"#.utf8), to: url)
        try Data("garbage".utf8).write(to: url)
        try SafeFileWriter.write(Data(#"{"v":3}"#.utf8), to: url)
        let backup = try Data(contentsOf: SafeFileWriter.backupURL(for: url))
        XCTAssertEqual(String(decoding: backup, as: UTF8.self), #"{"v":1}"#)
    }

    func testReadWithoutFileOrBackupThrows() {
        XCTAssertThrowsError(try SafeFileWriter.read(folder.appendingPathComponent("none.json")) { _ in })
    }

    // MARK: SchemaCoder

    private struct Payload: Codable, Equatable {
        var name: String
        var size: Int
    }

    private var coder: SchemaCoder {
        SchemaCoder(appName: "Test", currentVersion: 2, migrations: [
            Migration(kind: "thing", from: 0) { payload in
                var payload = payload
                payload["name"] = payload["title"]
                return payload
            },
            Migration(kind: "thing", from: 1) { payload in
                var payload = payload
                if payload["size"] == nil { payload["size"] = .number(1) }
                return payload
            }
        ])
    }

    func testRoundTrip() throws {
        let data = try coder.encode(Payload(name: "a", size: 3), kind: "thing")
        XCTAssertEqual(try coder.decode(Payload.self, kind: "thing", from: data), Payload(name: "a", size: 3))
    }

    func testVersionZeroIsWrappedAndMigrated() throws {
        let legacy = Data(#"{"title":"old"}"#.utf8)
        XCTAssertEqual(try coder.decode(Payload.self, kind: "thing", from: legacy), Payload(name: "old", size: 1))
    }

    func testNewerFilesAreRefused() throws {
        let future = Data(#"{"schemaVersion":9,"kind":"thing","payload":{}}"#.utf8)
        XCTAssertThrowsError(try coder.decode(Payload.self, kind: "thing", from: future)) { error in
            XCTAssertEqual(error as? SchemaError, .newerThanApp(app: "Test", found: 9, supported: 2))
            XCTAssertTrue(String(describing: error).contains("newer Test"))
        }
    }

    func testMissingMigrationAndMalformed() {
        XCTAssertThrowsError(try coder.decode(Payload.self, kind: "other", from: Data(#"{"a":1}"#.utf8))) { error in
            XCTAssertEqual(error as? SchemaError, .missingMigration(kind: "other", from: 0))
        }
        XCTAssertThrowsError(try coder.decode(Payload.self, kind: "thing", from: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? SchemaError, .malformed("not valid JSON"))
        }
        XCTAssertEqual(SchemaCoder.version(of: .object([:])), 0)
    }

    // MARK: Packages

    func testCreateAndReadPackage() throws {
        let url = folder.appendingPathComponent("Film.lowey")
        let manifest = DocumentManifest(schemaVersion: 4, app: "lowey", kind: "project")
        let package = try DocumentPackage.create(at: url, manifest: manifest)
        XCTAssertEqual(try package.readManifest(), manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetsURL.path))
        try package.write(Data(#"{"x":1}"#.utf8), to: "project.json")
        XCTAssertEqual(try package.read("project.json") { _ in }.data, Data(#"{"x":1}"#.utf8))
        try package.writeThumbnail(Data([1, 2, 3]))
        XCTAssertEqual(package.thumbnail, Data([1, 2, 3]))
        let later = Date(timeIntervalSinceReferenceDate: 9_999_999)
        try package.touch(later)
        XCTAssertEqual(try package.readManifest()?.modified, later)
    }

    func testMigratorUpgradesLegacyPackagesWithABackup() throws {
        let url = folder.appendingPathComponent("Old.lowey")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(#"{"v":1}"#.utf8).write(to: url.appendingPathComponent("project.json"))
        let migrator = PackageMigrator(app: "lowey", kind: "project", currentVersion: 2, migrations: [
            PackageMigration(from: 1) { package in
                try Data(#"{"v":2}"#.utf8).write(to: package.fileURL("project.json"))
            }
        ], legacyVersion: { package in
            FileManager.default.fileExists(atPath: package.fileURL("project.json").path) ? 1 : nil
        })
        let result = try migrator.open(url)
        XCTAssertEqual(result.upgradedFrom, 1)
        XCTAssertEqual(result.manifest.schemaVersion, 2)
        let backup = try XCTUnwrap(result.backup)
        XCTAssertEqual(backup.lastPathComponent, "Old.v1.bak")
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("project.json")), Data(#"{"v":1}"#.utf8))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("project.json")), Data(#"{"v":2}"#.utf8))
        // Opening again does nothing.
        let again = try migrator.open(url)
        XCTAssertEqual(again.upgradedFrom, 2)
        XCTAssertNil(again.backup)
    }

    func testMigratorRefusesOtherAppsNewerAndUnknownFolders() throws {
        let migrator = PackageMigrator(app: "lowey", kind: "project", currentVersion: 2)
        let other = folder.appendingPathComponent("Other.pkg")
        try DocumentPackage.create(at: other, manifest: DocumentManifest(schemaVersion: 1, app: "retake", kind: "take"))
        XCTAssertThrowsError(try migrator.open(other)) { error in
            XCTAssertEqual(error as? DocumentPackageError, .wrongApp(expected: "lowey", found: "retake"))
        }
        let newer = folder.appendingPathComponent("New.lowey")
        try DocumentPackage.create(at: newer, manifest: DocumentManifest(schemaVersion: 7, app: "lowey", kind: "project"))
        XCTAssertThrowsError(try migrator.open(newer))
        let empty = folder.appendingPathComponent("Empty.lowey")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try migrator.open(empty)) { error in
            XCTAssertEqual(error as? DocumentPackageError, .notAPackage("Empty.lowey"))
        }
        XCTAssertFalse(DocumentPackageError.missingMigration(from: 1).description.isEmpty)
    }

    // MARK: Autosave

    func testAutosaveDebouncesAndSavesTheLatestRevision() async throws {
        let scheduler = AutosaveScheduler(delay: .milliseconds(80))
        let saved = SavedRevisions()
        for revision in 1 ... 5 {
            await scheduler.documentChanged(revision: revision) { await saved.append($0) }
        }
        try await Task.sleep(for: .milliseconds(400))
        let revisions = await saved.values
        XCTAssertEqual(revisions, [5])
        let current = await scheduler.savedRevision
        XCTAssertEqual(current, 5)
    }

    func testFlushSavesImmediatelyAndFailuresStayPending() async throws {
        let scheduler = AutosaveScheduler(delay: .seconds(60))
        let saved = SavedRevisions()
        await scheduler.documentChanged(revision: 1) { _ in throw CocoaError(.fileWriteNoPermission) }
        await scheduler.flush()
        let pending = await scheduler.hasPendingChanges
        XCTAssertTrue(pending)
        let error = await scheduler.lastError
        XCTAssertNotNil(error)
        await scheduler.documentChanged(revision: 2) { await saved.append($0) }
        await scheduler.flush()
        let values = await saved.values
        XCTAssertEqual(values, [2])
        await scheduler.markSaved(3)
        let stillPending = await scheduler.hasPendingChanges
        XCTAssertFalse(stillPending)
    }

    // MARK: Storage & conflicts

    func testLocatorFallsBackToLocalAndUniqueNames() async throws {
        let locator = DocumentLocator(containerIdentifier: nil, subfolder: "Projects", localRoot: folder)
        let storage = await locator.resolve()
        XCTAssertFalse(storage.isICloud)
        XCTAssertEqual(storage.folder.lastPathComponent, "Projects")
        let first = DocumentLocator.uniqueURL(for: "Film.lowey", in: storage.folder)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        XCTAssertEqual(DocumentLocator.uniqueURL(for: "Film.lowey", in: storage.folder).lastPathComponent, "Film 2.lowey")
    }

    func testConflictCopyName() {
        let url = URL(fileURLWithPath: "/tmp/Film.lowey")
        XCTAssertEqual(ConflictNaming.copyName(for: url, device: "Hesham's iPhone"), "Film (from Hesham's iPhone).lowey")
        XCTAssertEqual(ConflictChoice.allCases.count, 3)
        XCTAssertEqual(ConflictChoice.keepBoth.title, "Keep Both")
    }
}

private actor SavedRevisions {
    var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}
