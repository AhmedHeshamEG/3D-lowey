import Foundation
@testable import LoweyCore
import XCTest

/// Painted objects in every export that carries colour: glTF (and so the Blender package), USDZ, OBJ.
final class PaintExportTests: XCTestCase {
    /// A white cube with its first layer filled red and a blue square painted in the top left tile of a second
    /// layer; the files it needs.
    private func paintedCube() throws -> (Scene, Look, [String: Data]) {
        var cube = SceneObject(id: "cube", name: "Painted cube", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(1, 1, 1)))
        let mesh = try XCTUnwrap(PaintSource.mesh(of: cube))
        var (paint, _, files) = try PaintOperations.prepare(mesh: mesh, keepOwnUVs: false, size: 512)
        let fill = PaintOperations.fill(RGBA(0.9, 0.1, 0.1, 1), layer: paint.layers[0], surface: paint.surface, object: "cube")
        files.merge(fill.files) { _, new in new }
        guard case let .paintTiles(_, changes) = fill.command else { throw CommandError.empty }
        for change in changes {
            paint.layers[0].tiles[change.tile] = change.file
        }
        cube.paint = paint
        let scene = Scene(id: "s", name: "Paint", objects: ["cube": cube], roots: ["cube"])
        return (scene, Look(presetID: LookPreset.clay.id), files)
    }

    private func painted(_ files: [String: Data], look: Look) -> (SceneObject) -> PaintedExport? {
        { object in
            PaintExport.painted(object, source: PaintSource.mesh(of: object), base: object.color?.resolved(in: look.palette) ?? .blockout) {
                files[$0]
            }
        }
    }

    private func json(_ glb: Data) throws -> ([String: Any], Data) {
        let bytes = [UInt8](glb)
        func u32(_ offset: Int) -> Int {
            Int(UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }
        let jsonLength = u32(12)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes[20 ..< 20 + jsonLength])) as? [String: Any])
        let binaryStart = 20 + jsonLength + 8
        return (json, Data(bytes[binaryStart ..< binaryStart + u32(20 + jsonLength)]))
    }

    func testPaintedGLTFCarriesTheTextureAndUVs() throws {
        let (scene, look, files) = try paintedCube()
        let glb = GLTFScene.glb(nil, in: scene, look: look, painted: painted(files, look: look))
        let (json, binary) = try json(glb)
        let materials = try XCTUnwrap(json["materials"] as? [[String: Any]])
        let pbr = try XCTUnwrap(materials.first?["pbrMetallicRoughness"] as? [String: Any])
        XCTAssertEqual((pbr["baseColorTexture"] as? [String: Any])?["index"] as? Int, 0)
        XCTAssertEqual(pbr["baseColorFactor"] as? [Double], [1, 1, 1, 1], "the texture carries the colour")
        let mesh = try XCTUnwrap((json["meshes"] as? [[String: Any]])?.first)
        let attributes = try XCTUnwrap((mesh["primitives"] as? [[String: Any]])?.first?["attributes"] as? [String: Int])
        XCTAssertNotNil(attributes["TEXCOORD_0"])
        let image = try XCTUnwrap((json["images"] as? [[String: Any]])?.first)
        XCTAssertEqual(image["mimeType"] as? String, "image/png")
        let view = try XCTUnwrap((json["bufferViews"] as? [[String: Any]])?[XCTUnwrap(image["bufferView"] as? Int)])
        let offset = try XCTUnwrap(view["byteOffset"] as? Int), length = try XCTUnwrap(view["byteLength"] as? Int)
        let texture = try PNGCodec.decode(binary.subdata(in: offset ..< offset + length))
        XCTAssertEqual(texture.width, 512)
        let center = texture.pixel(texture.width / 2, texture.height / 2)
        XCTAssertEqual(center.a, 1, "flattened: opaque")
        XCTAssertNotNil(json["samplers"])
        // An unpainted scene writes no images.
        var plain = scene
        plain.objects["cube"]?.paint = nil
        XCTAssertNil(try self.json(GLTFScene.glb(nil, in: plain, look: look, painted: painted(files, look: look))).0["images"])
    }

    func testAChangedShapeStillExportsItsPaint() throws {
        let (scene, look, files) = try paintedCube()
        var cube = try XCTUnwrap(scene.objects["cube"])
        cube[.bevel] = .float(0.05)
        let source = try XCTUnwrap(PaintSource.mesh(of: cube))
        XCTAssertNotEqual(PaintMesh.fingerprint(source), cube.paint?.surface.mesh, "the shape changed under the paint")
        let export = try XCTUnwrap(painted(files, look: look)(cube))
        XCTAssertEqual(export.mesh.triangleCount, source.triangleCount)
        XCTAssertEqual(try XCTUnwrap(export.mesh.bounds).size.y, 1, accuracy: 1e-3, "in the object's space, like the plain cube")
        let texture = try PNGCodec.decode(export.texture)
        var red = 0, total = 0
        let coverage = try PaintRaster.coverage(XCTUnwrap(PaintUnwrap.unwrap(source)), size: texture.width)
        for index in 0 ..< texture.width * texture.height where coverage[index] != 0 {
            total += 1
            if texture.pixels[index * 4] > 200, texture.pixels[index * 4 + 1] < 60 { red += 1 }
        }
        XCTAssertGreaterThan(Double(red) / Double(max(total, 1)), 0.9, "the red came along onto the bevelled cube")
        XCTAssertNil(PaintExport.painted(cube, source: source, base: .white) { _ in nil }, "missing files: no paint, not a crash")
    }

    func testUSDZAndOBJCarryTheTexture() throws {
        let (scene, look, files) = try paintedCube()
        let meshes = SceneExport.meshes(nil, in: scene, look: look, painted: painted(files, look: look))
        XCTAssertNotNil(meshes.first?.texture)
        let usdz = SceneExport.usdz(meshes)
        let entries = try Dictionary(uniqueKeysWithValues: ZipReader.entries(usdz).map { ($0.name, $0.data) })
        XCTAssertNotNil(entries["textures/paint_0.png"])
        let usda = try XCTUnwrap(String(data: XCTUnwrap(entries["scene.usda"]), encoding: .utf8))
        XCTAssertTrue(usda.contains("UsdUVTexture"))
        XCTAssertTrue(usda.contains("@textures/paint_0.png@"))
        XCTAssertTrue(usda.contains("diffuseColor.connect"))
        XCTAssertTrue(usda.contains("primvars:st"))
        let (obj, mtl) = OBJFile.text(meshes, materialFile: "cube.mtl")
        XCTAssertTrue(obj.contains("\nvt "))
        XCTAssertTrue(obj.contains("/"))
        XCTAssertTrue(mtl.contains("map_Kd paint_1.png"))
        XCTAssertEqual(OBJFile.textures(meshes).map(\.name), ["paint_1.png"])
        // Without paint, nothing changes in the OBJ.
        let plain = SceneExport.meshes(nil, in: scene, look: look)
        XCTAssertFalse(OBJFile.text(plain, materialFile: "cube.mtl").obj.contains("vt "))
        XCTAssertTrue(OBJFile.textures(plain).isEmpty)
    }

    /// Acceptance (M6): the painted glTF opens with its paint elsewhere. CI validates `painted/painted.glb` with the
    /// Khronos validator and renders it (and a Blender package of it) in Blender, checking the paint's colour.
    func testWritesThePaintedFilesForTheInteropChecks() throws {
        let (scene, look, files) = try paintedCube()
        var camera = SceneObject(id: "cam", name: "Camera", kind: .camera,
                                 transform: Transform(position: Vec3(2.2, 1.8, 2.2),
                                                      // Turned 45° to face the cube, tipped down to its middle.
                                                      rotation: Quat(angle: .pi / 4, axis: .unitY) * Quat(angle: -0.4, axis: .unitX)))
        camera[.fieldOfView] = .float(40)
        var withCamera = scene
        withCamera.objects["cam"] = camera
        withCamera.roots.append("cam")
        withCamera.activeCamera = "cam"
        let glb = GLTFScene.glb(nil, in: scene, look: look, painted: painted(files, look: look))
        let package = BlenderPackage.archive(withCamera, look: look, preset: .clay, render: .init(width: 640, height: 360),
                                             painted: painted(files, look: look))
        let entries = try Dictionary(uniqueKeysWithValues: ZipReader.entries(package).map { ($0.name, $0.data) })
        XCTAssertNotNil(entries["scene.glb"])
        guard let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] else { return }
        let root = URL(fileURLWithPath: directory)
        let painted = root.appendingPathComponent("painted")
        try FileManager.default.createDirectory(at: painted, withIntermediateDirectories: true)
        try glb.write(to: painted.appendingPathComponent("painted.glb"))
        let folder = root.appendingPathComponent("painted-blender")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in entries {
            try data.write(to: folder.appendingPathComponent(name))
        }
    }
}
