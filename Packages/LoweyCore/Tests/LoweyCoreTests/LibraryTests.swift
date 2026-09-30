import Foundation
@testable import LoweyCore
import XCTest

final class LibraryTests: XCTestCase {
    private func sampleManifest() -> LibraryManifest {
        let now = Date(timeIntervalSince1970: 1000)
        return LibraryManifest(
            assets: [
                LibraryAsset(id: "tiger", name: "Tiger", tags: ["animal", "cat", "rigged"], format: .glb, file: "tiger.glb",
                             rig: .quadruped, clips: ["Walk", "Idle"], added: now, lastUsed: Date(timeIntervalSince1970: 5000)),
                LibraryAsset(id: "pine", name: "Pine Tree", tags: ["tree", "forest"], format: .gltf, file: "pine.gltf",
                             favorite: true, added: Date(timeIntervalSince1970: 2000)),
                LibraryAsset(id: "tree", name: "Oak tree", tags: ["tree"], format: .usdz, file: "oak.usdz",
                             added: Date(timeIntervalSince1970: 3000), lastUsed: Date(timeIntervalSince1970: 4000)),
                LibraryAsset(id: "desk", name: "Desk", tags: ["office", "furniture"], format: .obj, file: "desk.obj", added: now)
            ],
            prefabs: [Prefab(id: "lamp", name: "Warm desk lamp", tags: ["light"], fragment: SceneFragment(objects: [], roots: []))],
            looks: [SavedLook(id: "moody", name: "Moody night", look: MoodPresets.look(for: .night))]
        )
    }

    func testSearchRanking() {
        let manifest = sampleManifest()
        XCTAssertEqual(LibrarySearch.search("tiger", in: manifest).first?.name, "Tiger")
        let trees = LibrarySearch.search("tree", in: manifest).map(\.name)
        XCTAssertEqual(Set(trees.prefix(2)), ["Pine Tree", "Oak tree"])
        XCTAssertEqual(LibrarySearch.search("animal", in: manifest).map(\.name), ["Tiger"])
        XCTAssertEqual(LibrarySearch.search("warm lamp", in: manifest).map(\.name), ["Warm desk lamp"])
        XCTAssertTrue(LibrarySearch.search("zebra", in: manifest).isEmpty)
        XCTAssertEqual(LibrarySearch.search("tgr", in: manifest).map(\.name), ["Tiger"], "fuzzy subsequence")
        XCTAssertEqual(LibrarySearch.search("", in: manifest).count, 6)
        XCTAssertEqual(LibrarySearch.search("moody", in: manifest, filter: .looks).count, 1)
        XCTAssertEqual(LibrarySearch.search("desk", in: manifest).first?.name, "Desk", "exact name beats word match")
    }

    func testFilters() {
        let manifest = sampleManifest()
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .all).count, 6)
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .favorites).map(\.name), ["Pine Tree"])
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .recent).map(\.name), ["Tiger", "Oak tree"])
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .models).count, 4)
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .prefabs).count, 1)
        XCTAssertEqual(LibrarySearch.items(in: manifest, filter: .looks).count, 1)
        for filter in LibraryFilter.allCases {
            XCTAssertFalse(filter.displayName.isEmpty)
        }
        let items = LibrarySearch.items(in: manifest, filter: .all)
        for item in items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertTrue(item.thumbnailName.hasSuffix(".png"))
            _ = item.tags
            _ = item.lastUsed
        }
        XCTAssertEqual(manifest.asset("tiger")?.clips, ["Walk", "Idle"])
        XCTAssertNotNil(manifest.prefab("lamp"))
        XCTAssertNotNil(manifest.look("moody"))
        XCTAssertNil(manifest.asset("nope"))
    }

    func testRigClassifier() {
        XCTAssertEqual(RigClassifier.classify(jointNames: []), .none)
        let mixamo = ["mixamorig:Hips", "mixamorig:Spine", "mixamorig:Head", "mixamorig:LeftArm", "mixamorig:LeftHand",
                      "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot"]
        XCTAssertEqual(RigClassifier.classify(jointNames: mixamo), .humanoid)
        let quad = ["Root", "Spine", "Neck", "Head", "FrontLeg.L", "BackLeg.R", "Tail1", "Tail2"]
        XCTAssertEqual(RigClassifier.classify(jointNames: quad), .quadruped)
        let tailed = ["body", "leg_l", "leg_r", "tail_01", "head"]
        XCTAssertEqual(RigClassifier.classify(jointNames: tailed), .quadruped)
        XCTAssertEqual(RigClassifier.classify(jointNames: ["Body", "Wing.L", "Wing.R", "Head"]), .bird)
        XCTAssertEqual(RigClassifier.classify(jointNames: ["Bone001", "Bone002"]), .custom)
        XCTAssertTrue(RigType.humanoid.isRigged)
        XCTAssertFalse(RigType.none.isRigged)
    }

    func testAssetFormats() {
        XCTAssertEqual(AssetFormat(fileExtension: "GLB"), .glb)
        XCTAssertEqual(AssetFormat(fileExtension: "usdc"), .usdz)
        XCTAssertEqual(AssetFormat(fileExtension: "gltf"), .gltf)
        XCTAssertEqual(AssetFormat(fileExtension: "obj"), .obj)
        XCTAssertNil(AssetFormat(fileExtension: "fbx"))
    }

    func testNamesAndTags() {
        XCTAssertEqual(LibraryStore.displayName(for: URL(fileURLWithPath: "/x/tiger_walk-v2.glb")), "Tiger walk v2")
        XCTAssertEqual(LibraryStore.guessTags(from: "Pine tree pine big"), ["pine", "tree", "big"])
        XCTAssertEqual(LibraryStore.displayName(for: URL(fileURLWithPath: "/x/_.glb")), "Model")
    }

    func testImportSaveLoadAndGLTFDependencies() throws {
        let root = try temporaryDirectory()
        let store = LibraryStore(root: root.appendingPathComponent("Library"))
        XCTAssertEqual(try store.load(), LibraryManifest(), "missing library is empty")
        // A .gltf with an external buffer and texture in a subfolder.
        let source = root.appendingPathComponent("pack")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("tex"), withIntermediateDirectories: true)
        let gltf = """
        {"asset":{"version":"2.0"},"buffers":[{"uri":"fox.bin","byteLength":4}],"images":[{"uri":"tex/fur.png"}]}
        """
        try Data(gltf.utf8).write(to: source.appendingPathComponent("Fox_Low.gltf"))
        try Data([0, 1, 2, 3]).write(to: source.appendingPathComponent("fox.bin"))
        try Data([9]).write(to: source.appendingPathComponent("tex/fur.png"))
        let asset = try store.importModel(from: source.appendingPathComponent("Fox_Low.gltf"), id: "fox")
        XCTAssertEqual(asset.name, "Fox Low")
        XCTAssertEqual(asset.tags, ["fox", "low"])
        XCTAssertEqual(asset.format, .gltf)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: asset).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetFolder("fox").appendingPathComponent("fox.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetFolder("fox").appendingPathComponent("tex/fur.png").path))
        // Re-import over existing files works.
        _ = try store.importModel(from: source.appendingPathComponent("Fox_Low.gltf"), name: "Fox", tags: ["animal"], id: "fox")
        XCTAssertThrowsError(try store.importModel(from: source.appendingPathComponent("fox.bin")))

        var manifest = LibraryManifest(assets: [asset])
        try store.save(manifest)
        XCTAssertEqual(try store.load(), manifest)
        try store.writeThumbnail(Data([1]), named: "fox.png")
        XCTAssertEqual(try Data(contentsOf: store.thumbnailURL(for: .asset(asset))), Data([1]))
        store.removeAsset("fox")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetFolder("fox").path))
        manifest.assets.removeAll()
        try store.save(manifest)
        XCTAssertTrue(try store.load().assets.isEmpty)
    }

    func testProjectExportCopiesAssetsInAndAdoptsBack() throws {
        let root = try temporaryDirectory()
        let libraryStore = LibraryStore(root: root.appendingPathComponent("Library"))
        let modelSource = root.appendingPathComponent("Tree.obj")
        try Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8).write(to: modelSource)
        let tree = try libraryStore.importModel(from: modelSource, id: "tree")
        let rock = try libraryStore.importModel(from: modelSource, name: "Rock", id: "rock")
        let unused = try libraryStore.importModel(from: modelSource, name: "Unused", id: "unused")
        // A prefab that contains the rock asset.
        let prefabFragment = SceneFragment(object: SceneObject(id: "r", name: "Rock", kind: .asset("rock")))
        let prefab = Prefab(id: "rock-pile", name: "Rock pile", fragment: prefabFragment)
        var library = LibraryManifest(assets: [tree, rock, unused], prefabs: [prefab])

        var scene = makeDocument().scene
        scene.objects["t"] = SceneObject(id: "t", name: "Tree", kind: .asset("tree"))
        scene.objects["p"] = SceneObject(id: "p", name: "Pile", kind: .prefab("rock-pile"))
        scene.roots += ["t", "p"]
        XCTAssertEqual(ProjectAssets.assetIDs(in: scene, library: library), ["tree", "rock"])
        XCTAssertEqual(ProjectAssets.prefabIDs(in: scene, library: library), ["rock-pile"])

        let projectURL = root.appendingPathComponent("Export.lowey")
        let embedded = try ProjectAssets.embed(scenes: [scene], library: library, libraryStore: libraryStore, into: projectURL)
        XCTAssertEqual(Set(embedded.assets.map(\.id)), ["tree", "rock"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("assets/tree/Tree.obj").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("assets/unused").path))

        // Another library adopts the project's assets.
        let otherStore = LibraryStore(root: root.appendingPathComponent("OtherLibrary"))
        var other = LibraryManifest()
        XCTAssertEqual(try ProjectAssets.adopt(from: projectURL, into: &other, libraryStore: otherStore), 3)
        XCTAssertNotNil(other.asset("tree"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherStore.assetFolder("rock").path))
        XCTAssertEqual(try ProjectAssets.adopt(from: projectURL, into: &other, libraryStore: otherStore), 0, "no duplicates")
        XCTAssertEqual(try ProjectAssets.adopt(from: root, into: &library, libraryStore: libraryStore), 0, "no manifest")
    }

    func testRecursivePrefabsDoNotLoop() {
        let selfReferencing = Prefab(id: "loop", name: "Loop",
                                     fragment: SceneFragment(object: SceneObject(id: "x", name: "x", kind: .prefab("loop"))))
        let library = LibraryManifest(prefabs: [selfReferencing])
        var scene = Scene(id: "s", name: "s")
        scene.objects["i"] = SceneObject(id: "i", name: "i", kind: .prefab("loop"))
        scene.roots = ["i"]
        XCTAssertEqual(ProjectAssets.prefabIDs(in: scene, library: library), ["loop"])
        XCTAssertTrue(ProjectAssets.assetIDs(in: scene, library: library).isEmpty)
        let bounds = SceneBounds(library: library)
        _ = bounds.worldBounds(of: "i", in: scene)
    }
}
