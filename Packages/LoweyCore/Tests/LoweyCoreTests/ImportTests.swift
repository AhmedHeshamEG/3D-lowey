import Foundation
@testable import LoweyCore
import XCTest

final class ImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "glb", subdirectory: "Fixtures"))
    }

    func testStaticGLBReadsMeshAndMaterial() throws {
        let model = try GLTFMeshReader.model(contentsOf: fixture("box"))
        XCTAssertEqual(model.parts.count, 1)
        XCTAssertEqual(model.parts[0].mesh.triangleCount, 12)
        XCTAssertEqual(model.parts[0].mesh.normals.count, 24)
        XCTAssertFalse(model.parts[0].isSkinned)
        XCTAssertEqual(model.materials[0].baseColor, RGBA(0.9, 0.55, 0.2))
        XCTAssertFalse(model.materials[0].isGlossy)
        let bounds = try XCTUnwrap(model.bounds)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-6)
        XCTAssertEqual(bounds.max.y, 1, accuracy: 1e-6)
        XCTAssertNil(model.skin)
    }

    func testRiggedGLBReadsSkinThatMatchesItsSkeleton() throws {
        let url = try fixture("Tiger_Rigged")
        let model = try GLTFMeshReader.model(contentsOf: url)
        let skin = try XCTUnwrap(model.skin)
        let rig = try XCTUnwrap(GLTFReader.rig(contentsOf: url))
        XCTAssertEqual(Set(skin.joints), Set(rig.skeleton.joints.map(\.name)), "skin joints map onto the Core skeleton by name")
        XCTAssertEqual(skin.inverseBindMatrices.count, skin.joints.count)
        XCTAssertEqual(skin.armature.count, 16)
        let skinned = model.parts.filter(\.isSkinned)
        XCTAssertFalse(skinned.isEmpty)
        for part in skinned {
            XCTAssertEqual(part.weights.count, part.mesh.positions.count)
            for weights in part.weights {
                XCTAssertEqual(weights.x + weights.y + weights.z + weights.w, 1, accuracy: 1e-4)
            }
            for joints in part.joints {
                XCTAssertLessThan(Int(joints.x), skin.joints.count)
            }
        }
    }

    func testNodeTransformsAreBakedIntoStaticParts() throws {
        // One triangle under a node moved up 2 m and scaled ×2.
        let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        let buffer = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let json = """
        {"asset":{"version":"2.0"},"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0,"translation":[0,2,0],"scale":[2,2,2]}],
         "meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],
         "accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}],
         "bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36}],
         "buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,\(buffer.base64EncodedString())"}]}
        """
        let model = try GLTFMeshReader.model(data: Data(json.utf8))
        XCTAssertEqual(model.parts[0].mesh.positions, [SIMD3<Float>(0, 2, 0), SIMD3<Float>(2, 2, 0), SIMD3<Float>(0, 4, 0)])
        XCTAssertEqual(model.parts[0].mesh.indices, [0, 1, 2], "no indices = sequential triangles")
        XCTAssertEqual(model.parts[0].mesh.normals.count, 3, "missing normals are computed")
        XCTAssertEqual(model.materials.count, 1, "a default material when the file has none")
        XCTAssertEqual(model.triangleCount, 1)
    }

    func testNotGLTFIsRefused() {
        XCTAssertThrowsError(try GLTFMeshReader.model(data: Data("hello".utf8)))
    }

    func testColumnMajorMatrix() {
        let matrix = GLTFMeshReader.columnMajor(Transform(position: Vec3(1, 2, 3), scale: Vec3(2, 2, 2)))
        XCTAssertEqual(matrix, [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 1, 2, 3, 1])
        XCTAssertEqual(ImportedModel(mesh: PrimitiveMesh.make(.cube)).parts.count, 1)
    }
}
