import Foundation
@testable import LoweyCore
import XCTest

/// glTF out and back in (the hierarchy, materials and animation survive), and OBJ out.
final class InteropTests: XCTestCase {
    /// A table (a group) with a top and a leg, a lamp, a camera, and the table sliding and turning.
    private func furnishedScene() -> Scene {
        var table = SceneObject(id: "table", name: "Table", kind: .group, children: ["top", "leg"],
                                transform: Transform(position: Vec3(1, 0, -2), rotation: Quat(angle: 0.3, axis: .unitY)))
        table[.visible] = .bool(true)
        var top = SceneObject(id: "top", name: "Top", kind: .mesh(.box(min: Vec3(-0.6, 0.72, -0.4), max: Vec3(0.6, 0.76, 0.4))), parent: "table")
        top[.color] = .color(.rgba(RGBA(0.8, 0.3, 0.1)))
        top[.roughness] = .float(0.4)
        top[.metallic] = .float(0.2)
        var leg = SceneObject(id: "leg", name: "Leg", kind: .primitive(.cylinder), parent: "table",
                              transform: Transform(position: Vec3(0, 0, 0), scale: Vec3(0.1, 0.72, 0.1)))
        leg[.color] = .color(.rgba(RGBA(0.2, 0.2, 0.25)))
        leg[.emissive] = .color(.rgba(RGBA(1, 0.8, 0.2)))
        leg[.emissiveIntensity] = .float(0.5)
        var lamp = SceneObject(id: "lamp", name: "Lamp", kind: .light(.spot), transform: Transform(position: Vec3(0, 3, 0)))
        lamp[.lightIntensity] = .float(2.5)
        lamp[.spotAngle] = .float(40)
        var camera = SceneObject(id: "cam", name: "Shot", kind: .camera, transform: Transform(position: Vec3(0, 1.6, 5)))
        camera[.fieldOfView] = .float(35)
        let note = SceneObject(id: "dim", name: "Dimension", kind: .dimension(DimensionRecipe(start: .zero, end: .unitX)))
        let slide = Track(id: "slide", target: "table", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(1, 0, -2)), easing: .linear), Keyframe(time: 2, value: .vec3(Vec3(3, 0, -2)), easing: .linear)
        ])
        let turn = Track(id: "turn", target: "table", property: .rotation, keyframes: [
            Keyframe(time: 0, value: .quat(.identity), easing: .easeInOut), Keyframe(time: 1, value: .quat(Quat(angle: 1.5, axis: .unitY)))
        ])
        return Scene(id: "s", name: "Room", objects: ["table": table, "top": top, "leg": leg, "lamp": lamp, "cam": camera, "dim": note],
                     roots: ["table", "lamp", "cam", "dim"], timeline: Timeline(fps: 30, duration: 4, tracks: [slide, turn]))
    }

    private func roundTrip(_ scene: Scene) throws -> GLTFSceneReader.Result {
        let glb = GLTFScene.glb(nil, in: scene, look: Look())
        var ids = IDFactory.sequential("in")
        return try GLTFSceneReader.read(glb, ids: &ids)
    }

    /// Acceptance: a glTF round trip keeps the hierarchy, the materials and the animation.
    func testGLTFRoundTripKeepsHierarchyMaterialsAndAnimation() throws {
        let scene = furnishedScene()
        let result = try roundTrip(scene)
        let objects = Dictionary(uniqueKeysWithValues: result.fragment.objects.map { ($0.name, $0) })
        // Hierarchy: the table holds the top and the leg; the dimension stays behind.
        XCTAssertEqual(Set(result.fragment.roots.compactMap { id in result.fragment.objects.first { $0.id == id }?.name }), ["Table", "Lamp", "Shot"])
        let table = try XCTUnwrap(objects["Table"])
        XCTAssertEqual(Set(table.children.compactMap { id in result.fragment.objects.first { $0.id == id }?.name }), ["Top", "Leg"])
        XCTAssertNil(objects["Dimension"])
        XCTAssertTrue(table.transform.isApproximately(scene.objects["table"]?.transform ?? .identity, tolerance: 1e-6))
        // Materials.
        let top = try XCTUnwrap(objects["Top"])
        let color = try XCTUnwrap(top.color?.resolved(in: .empty))
        // Colours are kept in 8-bit steps; they come back to the same step.
        XCTAssertEqual(color, RGBA(0.8, 0.3, 0.1))
        XCTAssertEqual(top[.roughness]?.floatValue ?? 0, 0.4, accuracy: 1e-6)
        XCTAssertEqual(top[.metallic]?.floatValue ?? 0, 0.2, accuracy: 1e-6)
        let leg = try XCTUnwrap(objects["Leg"])
        XCTAssertEqual(leg.emissiveIntensity, 0.5, accuracy: 1e-5)
        // Shapes come back as editable meshes the same size.
        guard case let .mesh(topMesh) = top.kind else { return XCTFail("the top is a mesh") }
        XCTAssertEqual(topMesh.faces.count, 6)
        XCTAssertEqual(topMesh.volume, 1.2 * 0.04 * 0.8, accuracy: 1e-6)
        // Cameras and lights.
        let shot = try XCTUnwrap(objects["Shot"])
        XCTAssertEqual(shot.kind, .camera)
        XCTAssertEqual(shot[.fieldOfView]?.floatValue ?? 0, 35, accuracy: 1e-6)
        let lamp = try XCTUnwrap(objects["Lamp"])
        XCTAssertEqual(lamp.kind, .light(.spot))
        XCTAssertEqual(lamp[.lightIntensity]?.floatValue ?? 0, 2.5, accuracy: 1e-6)
        XCTAssertEqual(lamp[.spotAngle]?.floatValue ?? 0, 40, accuracy: 1e-4)
        // Animation: the same motion at every moment.
        XCTAssertEqual(result.tracks.count, 2)
        let original = scene.timeline.tracks
        for property in [PropertyKey.position, .rotation] {
            let before = try XCTUnwrap(original.first { $0.property == property })
            let after = try XCTUnwrap(result.tracks.first { $0.property == property })
            XCTAssertEqual(after.target, table.id)
            for time in stride(from: 0.0, through: 2.0, by: 0.1) {
                switch (before.value(at: time), after.value(at: time)) {
                case let (.vec3(a)?, .vec3(b)?):
                    XCTAssertTrue(a.isApproximately(b, tolerance: 1e-5), "position at \(time)")
                case let (.quat(a)?, .quat(b)?):
                    XCTAssertGreaterThan(abs(a.dot(b)), 1 - 1e-4, "rotation at \(time)")
                default:
                    XCTFail("values at \(time)")
                }
            }
        }
        XCTAssertEqual(result.tracks.first { $0.property == .position }?.keyframes.count, 2, "linear keys stay keys")
    }

    func testImportingAGLTFSceneIsOneStepThatStretchesTheTimeline() throws {
        let result = try roundTrip(furnishedScene())
        let empty = Scene(id: "e", name: "E", timeline: Timeline(duration: 1))
        var document = Document(project: ProjectInfo(id: "p", name: "P", created: Date(timeIntervalSince1970: 0),
                                                     modified: Date(timeIntervalSince1970: 0), sceneOrder: ["e"], sceneNames: ["e": "E"]),
                                scene: empty)
        let command = ModelingOperations.importScene(result, in: empty)
        XCTAssertEqual(command.label, "Import")
        _ = try command.apply(to: &document)
        XCTAssertEqual(document.scene.roots.count, 3)
        XCTAssertEqual(document.scene.timeline.tracks.count, 2)
        XCTAssertEqual(document.scene.timeline.duration, 2, accuracy: 1e-6)
    }

    func testASelectionUnderAParentExportsWhereItIs() throws {
        let scene = furnishedScene()
        let glb = GLTFScene.glb(["top"], in: scene, look: Look())
        var ids = IDFactory.sequential("t")
        let result = try GLTFSceneReader.read(glb, ids: &ids)
        XCTAssertEqual(result.fragment.objects.count, 1)
        let placed = try XCTUnwrap(result.fragment.objects.first).transform
        XCTAssertTrue(placed.isApproximately(scene.worldTransform(of: "top"), tolerance: 1e-6))
    }

    func testTooManyTrianglesStayALibraryModel() throws {
        var dense = MeshData()
        for index in 0 ..< 70000 {
            let x = Float(index)
            let a = dense.addVertex(SIMD3(x, 0, 0), normal: SIMD3(0, 1, 0), uv: .zero)
            let b = dense.addVertex(SIMD3(x + 1, 0, 0), normal: SIMD3(0, 1, 0), uv: .zero)
            let c = dense.addVertex(SIMD3(x, 0, 1), normal: SIMD3(0, 1, 0), uv: .zero)
            dense.addTriangle(a, b, c)
        }
        let glb = SceneExport.glb(Array(repeating: ExportMesh(name: "Dense", transform: .identity, mesh: dense, color: .white), count: 3))
        var ids = IDFactory.sequential("d")
        XCTAssertThrowsError(try GLTFSceneReader.read(glb, ids: &ids)) {
            XCTAssertEqual($0 as? GLTFSceneReader.Failure, .tooBig(210_000))
        }
    }
}

/// OBJ out, and the new library formats.
final class OBJAndFormatTests: XCTestCase {
    func testOBJHasEveryCornerFaceAndMaterial() throws {
        let box = EditableMesh.box(min: .zero, max: Vec3(1, 2, 3))
        let item = ExportMesh(name: "Crate box", transform: Transform(position: Vec3(10, 0, 0)), mesh: box.renderMesh(), color: RGBA(1, 0, 0))
        let (obj, mtl) = OBJFile.text([item, item], materialFile: "crate.mtl")
        XCTAssertTrue(obj.hasPrefix("# Exported from Maquette\nmtllib crate.mtl"))
        let lines = obj.split(separator: "\n")
        XCTAssertEqual(lines.count { $0.hasPrefix("f ") }, 2 * 12)
        XCTAssertEqual(lines.count { $0.hasPrefix("o ") }, 2)
        XCTAssertTrue(lines.contains { $0 == "v 10 0 0" }, "placed in the world")
        XCTAssertTrue(mtl.contains("newmtl Crate_box_1\nKd 1 0 0"))
        // The second object's faces point at its own corners.
        let lastFace = try XCTUnwrap(lines.last { $0.hasPrefix("f ") })
        let firstCorner = try XCTUnwrap(Int(lastFace.dropFirst(2).split(separator: "/").first ?? ""))
        XCTAssertGreaterThan(firstCorner, box.renderMesh().positions.count)
    }

    func testPrintFormatsImportIntoTheLibrary() {
        XCTAssertEqual(AssetFormat(fileExtension: "STL"), .stl)
        XCTAssertEqual(AssetFormat(fileExtension: "3mf"), .threeMF)
        XCTAssertEqual(AssetFormat.threeMF.rawValue, "3mf")
    }
}

/// "Render on your computer": the Blender package.
final class BlenderPackageTests: XCTestCase {
    func testThePackageHoldsTheSceneTheSettingsAndTheScript() throws {
        var table = SceneObject(id: "table", name: "Table", kind: .mesh(.box(min: Vec3(-0.6, 0, -0.4), max: Vec3(0.6, 0.75, 0.4))))
        table[.color] = .color(.rgba(RGBA(0.85, 0.45, 0.2)))
        let camera = SceneObject(id: "cam", name: "Wide", kind: .camera, transform: Transform(position: Vec3(2, 1.5, 4),
                                                                                              rotation: Quat(angle: 0.45, axis: .unitY)))
        let close = SceneObject(id: "close", name: "Close", kind: .camera, transform: Transform(position: Vec3(0.5, 1, 1.5)))
        let slide = Track(id: "t", target: "table", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero), easing: .linear), Keyframe(time: 1, value: .vec3(Vec3(0.5, 0, 0)), easing: .linear)
        ])
        let timeline = Timeline(fps: 24, duration: 2, tracks: [slide], cuts: [CameraCut(time: 0, camera: "cam"), CameraCut(time: 1, camera: "close")])
        let scene = Scene(id: "s", name: "Studio desk", objects: ["table": table, "cam": camera, "close": close], roots: ["table", "cam", "close"],
                          activeCamera: "cam", timeline: timeline)
        let look = Look(presetID: LookPreset.ink.id)
        let zip = BlenderPackage.archive(scene, look: look, preset: .ink, render: .init(width: 1280, height: 720))
        let entries = try Dictionary(uniqueKeysWithValues: ZipReader.entries(zip).map { ($0.name, $0.data) })
        XCTAssertEqual(Set(entries.keys), ["scene.glb", "maquette.json", "setup_maquette.py", "README.txt"])
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(entries["maquette.json"])) as? [String: Any])
        let render = try XCTUnwrap(settings["render"] as? [String: Any])
        XCTAssertEqual(render["fps"] as? Int, 24)
        XCTAssertEqual(render["frameEnd"] as? Int, 47)
        XCTAssertEqual(render["camera"] as? String, "Wide")
        XCTAssertEqual((render["cuts"] as? [[String: Any]])?.last?["frame"] as? Int, 24)
        XCTAssertEqual((settings["look"] as? [String: Any])?["preset"] as? String, LookPreset.ink.id)
        let script = try XCTUnwrap(String(data: XCTUnwrap(entries["setup_maquette.py"]), encoding: .utf8))
        XCTAssertTrue(script.hasPrefix("# Builds a ready-to-render Blender scene"), "the script isn't indented")
        XCTAssertTrue(script.contains("import_scene.gltf"))
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("blender-package")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, data) in entries {
                try data.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
