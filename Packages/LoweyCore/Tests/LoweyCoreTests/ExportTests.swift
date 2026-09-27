import Foundation
@testable import LoweyCore
import XCTest

final class ExportTests: XCTestCase {
    func testMeshesForBlockoutAndDrawingsWithExtrasForModels() throws {
        let (info, scenes) = try EnigmaSample.build()
        let desk = scenes[0]
        var extraCalls = 0
        let meshes = SceneExport.meshes(nil, in: desk, look: desk.look ?? info.look) { object, _ in
            extraCalls += 1
            XCTAssertFalse(object.kind.hasSurface && object.kind.assetID == nil && object.kind.prefabID == nil && object.kind != .group,
                           "primitives and drawings are handled in Core")
            return []
        }
        XCTAssertGreaterThan(meshes.count, 15)
        XCTAssertTrue(meshes.contains { $0.name == "Lamp arm" }, "drawn objects export")
        XCTAssertTrue(meshes.contains { $0.name == "Bulb" && $0.emissiveStrength > 0 })
        XCTAssertGreaterThan(extraCalls, 0, "groups/lights go through the extra hook")
        let selection = SceneExport.meshes([try XCTUnwrap(desk.objects.values.first { $0.name == "Desk" }).id], in: desk, look: info.look)
        XCTAssertEqual(selection.count, 6, "desk top + 4 legs + drawer")
    }

    func testGLBIsValidAndReadable() throws {
        let mesh = PrimitiveMesh.make(.cube, shading: .flat)
        let items = [
            ExportMesh(name: "Cube", transform: Transform(position: Vec3(1, 2, 3), rotation: Quat(angle: 0.5, axis: .unitY)), mesh: mesh,
                       color: RGBA(1, 0.5, 0.25), emissive: RGBA(1, 1, 0), emissiveStrength: 2),
            ExportMesh(name: "Empty", transform: .identity, mesh: MeshData(), color: .blockout)
        ]
        let data = SceneExport.glb(items)
        XCTAssertEqual(data.prefix(4), Data("glTF".utf8))
        XCTAssertEqual(Int(GLTFReader.readUInt32(data, 8)), data.count, "header length matches")
        let file = try GLTFReader.parse(data, baseURL: nil)
        XCTAssertEqual(file.array("nodes").count, 1, "empty meshes are skipped")
        XCTAssertEqual(file.array("meshes").count, 1)
        let positions = try GLTFReader.accessor(file, 0)
        XCTAssertEqual(positions.count, mesh.positions.count)
        XCTAssertEqual(positions.values[0], Double(mesh.positions[0].x), accuracy: 1e-6)
        let material = try XCTUnwrap(file.array("materials").first)
        XCTAssertNotNil(material["emissiveFactor"])
        let pbr = try XCTUnwrap(material["pbrMetallicRoughness"] as? [String: Any])
        let base = try XCTUnwrap(pbr["baseColorFactor"] as? [Double])
        XCTAssertEqual(base[0], 1, accuracy: 1e-9)
        XCTAssertEqual(base[1], SceneExport.linear(items[0].color.g), accuracy: 1e-9, "sRGB colours are written linear")
        let indices = try GLTFReader.accessor(file, 3)
        XCTAssertEqual(indices.count, mesh.indices.count)
        XCTAssertEqual(SceneExport.linear(0.01), 0.01 / 12.92, accuracy: 1e-12)
    }

    func testUSDZIsAnAlignedStoredZipWithUSDText() throws {
        let item = ExportMesh(name: "My Cube!", transform: Transform(position: Vec3(0, 1, 0)), mesh: PrimitiveMesh.make(.cube, shading: .smooth),
                              color: RGBA(0.2, 0.4, 0.6), emissive: RGBA(1, 0, 0), emissiveStrength: 0.5)
        let text = SceneExport.usda([item])
        XCTAssertTrue(text.hasPrefix("#usda 1.0"))
        XCTAssertTrue(text.contains("def Xform \"My_Cube_0\""))
        XCTAssertTrue(text.contains("UsdPreviewSurface"))
        XCTAssertTrue(text.contains("normal3f[] normals"))
        XCTAssertTrue(text.contains("rel material:binding = </Root/Materials/M0>"))
        XCTAssertEqual(text.components(separatedBy: "{").count, text.components(separatedBy: "}").count, "braces balance")
        let usdz = SceneExport.usdz([item])
        XCTAssertEqual(GLTFReader.readUInt32(usdz, 0), 0x0403_4B50, "zip local header")
        let nameLength = Int(usdz[26]) | Int(usdz[27]) << 8
        let extraLength = Int(usdz[28]) | Int(usdz[29]) << 8
        let dataOffset = 30 + nameLength + extraLength
        XCTAssertEqual(dataOffset % 64, 0, "USDZ needs 64-byte aligned file data")
        let payload = usdz.subdata(in: dataOffset ..< dataOffset + Data(text.utf8).count)
        XCTAssertEqual(String(data: payload, encoding: .utf8), text)
        XCTAssertEqual(GLTFReader.readUInt32(usdz, 14), CRC32.checksum(Data(text.utf8)))
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926, "standard CRC-32 check value")
        let plain = ZipWriter.storedArchive([("a.txt", Data("hi".utf8)), ("b.txt", Data())])
        XCTAssertEqual(GLTFReader.readUInt32(plain, plain.count - 22), 0x0605_4B50, "end of central directory")
    }
}
