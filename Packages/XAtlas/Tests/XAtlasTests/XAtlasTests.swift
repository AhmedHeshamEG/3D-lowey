import XAtlasCpp
import XCTest

final class XAtlasTests: XCTestCase {
    /// A unit cube, 24 vertices (one per face corner), 12 triangles.
    private func cube() -> (positions: [Float], indices: [UInt32]) {
        let faces: [[SIMD3<Float>]] = [
            [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]], [[1, 0, 0], [0, 0, 0], [0, 1, 0], [1, 1, 0]],
            [[1, 0, 1], [1, 0, 0], [1, 1, 0], [1, 1, 1]], [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]],
            [[0, 1, 1], [1, 1, 1], [1, 1, 0], [0, 1, 0]], [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]
        ]
        var positions: [Float] = []
        var indices: [UInt32] = []
        for face in faces {
            let base = UInt32(positions.count / 3)
            for corner in face {
                positions += [corner.x, corner.y, corner.z]
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return (positions, indices)
    }

    private func unwrap(_ positions: [Float], _ indices: [UInt32]) -> (XAStatus, XAUnwrap) {
        var result = XAUnwrap()
        let status = positions.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { i in
                XAUnwrapMesh(p.baseAddress, nil, positions.count / 3, i.baseAddress, indices.count, 1024, 2, &result)
            }
        }
        return (status, result)
    }

    func testCubeUnwrapsIntoOneSquareAtlas() {
        let (positions, indices) = cube()
        var (status, result) = unwrap(positions, indices)
        defer { XAUnwrapFree(&result) }
        XCTAssertEqual(status, XAOk)
        XCTAssertEqual(result.indexCount, indices.count)
        XCTAssertGreaterThanOrEqual(result.vertexCount, 14)
        XCTAssertGreaterThanOrEqual(result.chartCount, 1)
        for index in 0 ..< result.vertexCount {
            XCTAssertLessThan(Int(result.xref[index]), positions.count / 3)
            XCTAssert((0 ... 1).contains(result.uvs[index * 2]) && (0 ... 1).contains(result.uvs[index * 2 + 1]))
        }
    }

    func testTheSameMeshUnwrapsTheSameWay() {
        let (positions, indices) = cube()
        var (_, first) = unwrap(positions, indices)
        var (_, second) = unwrap(positions, indices)
        defer {
            XAUnwrapFree(&first)
            XAUnwrapFree(&second)
        }
        XCTAssertEqual(first.vertexCount, second.vertexCount)
        for index in 0 ..< first.vertexCount * 2 {
            XCTAssertEqual(first.uvs[index], second.uvs[index])
        }
    }

    func testRefusesBadInput() {
        var result = XAUnwrap()
        let positions: [Float] = [0, 0, 0, 1, 0, 0, .nan, 1, 0]
        let indices: [UInt32] = [0, 1, 2]
        let status = positions.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { i in XAUnwrapMesh(p.baseAddress, nil, 3, i.baseAddress, 3, 1024, 2, &result) }
        }
        XCTAssertEqual(status, XAInvalidInput)
        let outOfRange: [UInt32] = [0, 1, 7]
        let status2 = positions.withUnsafeBufferPointer { p in
            outOfRange.withUnsafeBufferPointer { i in XAUnwrapMesh(p.baseAddress, nil, 3, i.baseAddress, 3, 1024, 2, &result) }
        }
        XCTAssertEqual(status2, XAInvalidInput)
    }
}
