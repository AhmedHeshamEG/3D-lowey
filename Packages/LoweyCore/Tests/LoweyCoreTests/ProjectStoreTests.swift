import Foundation
@testable import LoweyCore
import XCTest

final class ProjectStoreTests: XCTestCase {
    func testCreateSaveCloseReopenIsIdentical() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, created) = try store.createProject(name: "My Video")
        XCTAssertEqual(url.pathExtension, "maquette")
        for folder in ["scenes", "assets", "audio", "renders"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent(folder).path))
        }
        // Build something, save, "close", reopen.
        var session = EditSession(document: created)
        var ops = Operations(ids: .sequential("t"))
        var factory = ObjectFactory(ids: .sequential("f"))
        try session.perform(ops.add(factory.primitive(.cube, at: Vec3(1, 0, 0))))
        try session.perform(ops.add(factory.light(.point, at: Vec3(0, 2, 0))))
        if let (dup, _) = ops.duplicate(["f-1"], in: session.document.scene) { try session.perform(dup) }
        try session.perform(.setLook(MoodPresets.look(for: .dusk), scope: .scene))
        session.setViewpoint(Viewpoint(target: Vec3(1, 2, 3), yaw: 10, pitch: 20, distance: 4))
        try store.save(session.document, to: url, touch: false)

        let reopened = try store.openDocument(at: url)
        XCTAssertEqual(reopened, session.document)
    }

    func testListRenameDuplicateDelete() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (first, _) = try store.createProject(name: "Alpha")
        let (second, _) = try store.createProject(name: "Alpha")
        XCTAssertNotEqual(first, second, "names are made unique")
        XCTAssertEqual(store.listProjects().count, 2)
        let renamed = try store.renameProject(at: first, to: "Beta: the sequel")
        XCTAssertTrue(renamed.lastPathComponent.hasPrefix("Beta- the sequel"))
        XCTAssertEqual(try store.loadProjectInfo(at: renamed).info.name, "Beta: the sequel")
        let same = try store.renameProject(at: renamed, to: "Beta: the sequel")
        XCTAssertNotEqual(same.lastPathComponent, "")
        let copy = try store.duplicateProject(at: second)
        let copyInfo = try store.loadProjectInfo(at: copy).info
        XCTAssertEqual(copyInfo.name, "Alpha copy")
        XCTAssertNotEqual(copyInfo.id, try store.loadProjectInfo(at: second).info.id)
        try store.deleteProject(at: copy)
        XCTAssertEqual(store.listProjects().count, 2)
        XCTAssertThrowsError(try store.loadProjectInfo(at: copy))
    }

    func testScenesInAProject() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, document) = try store.createProject(name: "Scenes")
        let second = try store.addScene(named: "Shot 2", to: url)
        let copy = try store.duplicateScene(second.id, in: url)
        var info = try store.loadProjectInfo(at: url).info
        XCTAssertEqual(info.sceneOrder, [document.scene.id, second.id, copy.id])
        XCTAssertEqual(info.sceneNames[copy.id], "Shot 2 copy")
        let opened = try store.openDocument(at: url, scene: second.id)
        XCTAssertEqual(opened.scene.name, "Shot 2")
        try store.deleteScene(second.id, in: url)
        info = try store.loadProjectInfo(at: url).info
        XCTAssertEqual(info.sceneOrder, [document.scene.id, copy.id])
        XCTAssertThrowsError(try store.loadScene(second.id, in: url)) { error in
            XCTAssertEqual(error as? ProjectStoreError, .sceneMissing(second.id))
        }
        try store.deleteScene(copy.id, in: url)
        XCTAssertThrowsError(try store.deleteScene(document.scene.id, in: url)) { error in
            XCTAssertEqual(error as? ProjectStoreError, .lastScene)
        }
        for error in [ProjectStoreError.notAProject("x"), .sceneMissing("s"), .lastScene] {
            XCTAssertFalse(error.description.isEmpty)
        }
    }

    func testRecoveryFromDamagedSceneFile() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, document) = try store.createProject(name: "Crashy")
        var session = EditSession(document: document)
        try session.perform(.renameScene("First save"))
        try store.save(session.document, to: url)
        try session.perform(.renameScene("Second save"))
        try store.save(session.document, to: url)
        // Crash mid-write damages the scene file.
        try Data("{ broken".utf8).write(to: ProjectLayout.sceneURL(document.scene.id, in: url))
        let (scene, recovered) = try store.loadScene(document.scene.id, in: url)
        XCTAssertTrue(recovered)
        XCTAssertEqual(scene.name, "First save")
    }

    func testWriteProjectAndThumbnail() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (info, scenes) = try EnigmaSample.build()
        let url = try store.writeProject(info: info, scenes: scenes)
        let loadedInfo = try store.loadProjectInfo(at: url).info
        XCTAssertEqual(loadedInfo.sceneOrder, scenes.map(\.id))
        for scene in scenes {
            XCTAssertEqual(try store.loadScene(scene.id, in: url).scene, scene)
        }
        try store.writeThumbnail(Data([1, 2, 3]), for: url)
        let summary = try XCTUnwrap(store.listProjects().first)
        XCTAssertEqual(try Data(contentsOf: summary.thumbnailURL), Data([1, 2, 3]))
        XCTAssertEqual(summary.id, info.id)
    }

    func testNotAProject() throws {
        let root = try temporaryDirectory()
        let store = ProjectStore(root: root)
        let fake = root.appendingPathComponent("Fake.lowey")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.loadProjectInfo(at: fake))
        XCTAssertTrue(store.listProjects().isEmpty)
        XCTAssertTrue(ProjectStore(root: root.appendingPathComponent("nope")).listProjects().isEmpty)
    }

    func testSanitize() {
        XCTAssertEqual(ProjectStore.sanitize("a/b:c"), "a-b-c")
        XCTAssertEqual(ProjectStore.sanitize("   "), "Untitled")
        XCTAssertEqual(ProjectStore.sanitize(String(repeating: "x", count: 200)).count, 80)
    }

    func testDocumentSaverSkipsStaleRevisions() async throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, document) = try store.createProject(name: "Saver")
        let saver = DocumentSaver(store: store)
        await saver.markSaved(0, for: url)
        let wrote = try await saver.save(document, revision: 3, to: url)
        XCTAssertTrue(wrote)
        let skipped = try await saver.save(document, revision: 2, to: url)
        XCTAssertFalse(skipped)
    }
}
