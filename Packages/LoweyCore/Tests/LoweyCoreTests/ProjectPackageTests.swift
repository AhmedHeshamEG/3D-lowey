@testable import LoweyCore
import XCTest

final class ProjectPackageTests: XCTestCase {
    func testZipRoundTripAndErrors() throws {
        let files: [(name: String, data: Data)] = [("a.txt", Data("hello".utf8)), ("dir/b.bin", Data([0, 1, 2, 255])), ("empty", Data())]
        let archive = ZipWriter.storedArchive(files)
        let back = try ZipReader.entries(archive)
        XCTAssertEqual(back.map(\.name), files.map(\.name))
        XCTAssertEqual(back.map(\.data), files.map(\.data))
        XCTAssertThrowsError(try ZipReader.entries(Data("not a zip at all, sorry".utf8))) { XCTAssertEqual($0 as? ZipReader.Failure, .notAZip) }
        var damaged = [UInt8](archive)
        damaged[30 + 5] ^= 0xFF // flip a byte of a.txt's content
        XCTAssertThrowsError(try ZipReader.entries(Data(damaged))) { XCTAssertEqual($0 as? ZipReader.Failure, .damaged("a.txt")) }
    }

    func testPackageArchiveCopyScene() throws {
        let root = try temporaryDirectory()
        let store = ProjectStore(root: root)
        let (url, document) = try store.createProject(name: "Enigma")
        try Data("RIFF".utf8).write(to: url.appendingPathComponent("audio/vo.wav"))
        try Data("big".utf8).write(to: url.appendingPathComponent("renders/shot.mp4"))
        var doc = document
        doc.scene.timeline.audio = [AudioClip(id: "vo", role: .voiceover, name: "VO", file: "vo.wav", duration: 1)]
        try store.save(doc, to: url)
        // Package → unpack: a new, independent project with the same scenes and audio (renders left out).
        let package = try ProjectPackage.archive(url)
        let copy = try ProjectPackage.unpack(package, into: store)
        XCTAssertNotEqual(copy, url)
        let reopened = try store.openDocument(at: copy)
        XCTAssertEqual(reopened.scene, doc.scene)
        XCTAssertNotEqual(reopened.project.id, doc.project.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent("audio/vo.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.appendingPathComponent("renders/shot.mp4").path))
        XCTAssertEqual(store.listProjects().count, 2)
        // Copy a scene into another project.
        let (other, _) = try store.createProject(name: "Other")
        let copied = try store.copyScene(doc.scene.id, from: url, to: other)
        let info = try store.loadProjectInfo(at: other).info
        XCTAssertEqual(info.sceneOrder.count, 2)
        XCTAssertEqual(info.sceneNames[copied.id], "Scene 1 2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.appendingPathComponent("audio/vo.wav").path))
        // Archive and back.
        let archived = try store.archiveProject(at: other)
        XCTAssertEqual(store.listProjects().count, 2)
        XCTAssertEqual(store.listArchived().count, 1)
        _ = try store.unarchiveProject(at: archived)
        XCTAssertEqual(store.listProjects().count, 3)
        XCTAssertTrue(store.listArchived().isEmpty)
    }
}

final class IslandSampleTests: XCTestCase {
    func testWelcomeIslandBuildsAndFliesThrough() throws {
        let (info, scenes) = try IslandSample.build()
        XCTAssertEqual(info.name, IslandSample.projectName)
        let scene = try XCTUnwrap(scenes.first)
        XCTAssertTrue(scene.validate().isEmpty)
        let names = Set(scene.objects.values.map(\.name))
        for name in ["Sea", "Grass", "Cabin", "Campfire", "Fly camera", "Title", "Forest"] {
            XCTAssertTrue(names.contains(name), name)
        }
        let camera = try XCTUnwrap(scene.activeCamera)
        let document = Document(project: info, scene: scene)
        let start = Animator.evaluate(document, at: 0).scene.worldTransform(of: camera).position
        let end = Animator.evaluate(document, at: 9.5).scene.worldTransform(of: camera).position
        XCTAssertGreaterThan(start.distance(to: end), 3, "the camera flies")
        XCTAssertGreaterThan(scene.objects.values.filter { $0.name.hasPrefix("Pine") }.count, 10)
    }
}
