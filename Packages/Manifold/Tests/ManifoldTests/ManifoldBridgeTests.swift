import ManifoldCpp
import Testing

/// The spike: Manifold builds through SwiftPM and answers from Swift on Linux and iPadOS.
struct ManifoldBridgeTests {
    /// A closed axis-aligned box, 8 shared vertices, 12 counter-clockwise triangles.
    static func box(min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> (positions: [Float], triangles: [UInt32]) {
        let corners: [SIMD3<Float>] = (0..<8).map { i in
            SIMD3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z)
        }
        let quads: [[UInt32]] = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
        let triangles = quads.flatMap { [$0[0], $0[1], $0[2], $0[0], $0[2], $0[3]] }
        return (corners.flatMap { [$0.x, $0.y, $0.z] }, triangles)
    }

    static func run(_ a: (positions: [Float], triangles: [UInt32]), _ b: (positions: [Float], triangles: [UInt32]),
                    _ op: MBOperation) -> (MBStatus, triangles: Int, volumeSign: Float) {
        var pa = a.positions, ta = a.triangles, pb = b.positions, tb = b.triangles
        var tagsA = [UInt32](repeating: 0, count: ta.count / 3), tagsB = [UInt32](repeating: 0, count: tb.count / 3)
        return pa.withUnsafeMutableBufferPointer { pa in
            ta.withUnsafeMutableBufferPointer { ta in
                pb.withUnsafeMutableBufferPointer { pb in
                    tb.withUnsafeMutableBufferPointer { tb in
                        tagsA.withUnsafeMutableBufferPointer { ga in
                            tagsB.withUnsafeMutableBufferPointer { gb in
                                var meshA = MBMesh(positions: pa.baseAddress, vertexCount: pa.count / 3, triangles: ta.baseAddress,
                                                   faceTags: ga.baseAddress, triangleCount: ta.count / 3)
                                var meshB = MBMesh(positions: pb.baseAddress, vertexCount: pb.count / 3, triangles: tb.baseAddress,
                                                   faceTags: gb.baseAddress, triangleCount: tb.count / 3)
                                var out = MBMesh()
                                let status = MBBoolean(&meshA, &meshB, op, 100, &out)
                                defer { MBMeshFree(&out) }
                                return (status, out.triangleCount, Float(out.vertexCount))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func subtractingABoxLeavesASolid() {
        let block = Self.box(min: [0, 0, 0], max: [4, 2, 1])
        let hole = Self.box(min: [1, 0.5, -1], max: [2, 1.5, 2])
        let (status, triangles, vertices) = Self.run(block, hole, MBSubtract)
        #expect(status == MBOk)
        #expect(triangles > 12)
        #expect(vertices == 16)
    }

    @Test func anOpenMeshIsRefused() {
        var box = Self.box(min: [0, 0, 0], max: [1, 1, 1])
        box.triangles.removeLast(3)
        let (status, _, _) = Self.run(box, Self.box(min: [0, 0, 0], max: [1, 1, 1]), MBUnion)
        #expect(status == MBNotManifold)
    }
}
