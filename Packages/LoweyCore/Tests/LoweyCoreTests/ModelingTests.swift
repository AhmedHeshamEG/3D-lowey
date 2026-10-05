import Foundation
@testable import LoweyCore
import XCTest

/// The editable mesh: faces from triangles, triangulation with holes, booleans, push/pull and exact lengths.
final class ModelingTests: XCTestCase {
    private let mm = 0.001
    /// 50 in CI (the acceptance); raise it locally to soak the boolean path.
    static let randomCases = Int(ProcessInfo.processInfo.environment["MODELING_RANDOM_CASES"] ?? "") ?? 50

    /// The acceptance block: 40 × 20 × 10 mm.
    private var block: EditableMesh { .box(min: .zero, max: Vec3(40 * mm, 10 * mm, 20 * mm)) }

    private func assertSolid(_ mesh: EditableMesh, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(MeshTopology(mesh).isClosedManifold, "closed manifold", file: file, line: line)
        XCTAssertTrue(MeshBoolean.isSolid(mesh), "Manifold accepts it", file: file, line: line)
        XCTAssertGreaterThan(mesh.volume, 0, "faces point out", file: file, line: line)
    }

    // MARK: Faces

    func testABoxHasSixQuadsAndTheRightVolume() {
        let box = block
        XCTAssertEqual(box.faces.count, 6)
        XCTAssertEqual(box.edges.count, 12)
        assertSolid(box)
        XCTAssertEqual(box.volume, 40 * 20 * 10 * mm * mm * mm, accuracy: 1e-12)
    }

    func testPrimitivesBecomeWholeFaces() {
        let cube = EditableMesh.primitive(.cube, size: Vec3(2, 1, 3))
        XCTAssertEqual(cube.faces.count, 6, "coplanar triangles merge into quads")
        XCTAssertEqual(cube.vertices.count, 8, "welded")
        XCTAssertEqual(cube.volume, 6, accuracy: 1e-9)
        assertSolid(cube)
        let cylinder = EditableMesh.primitive(.cylinder)
        XCTAssertEqual(cylinder.faces.count, 16, "14 sides, a top and a bottom")
        assertSolid(cylinder)
    }

    func testTrianglesOfAFaceWithAHoleCoverItsArea() {
        let ring = Prism.make(outline: [Vec3(0, 0, 0), Vec3(4, 0, 0), Vec3(4, 0, -4), Vec3(0, 0, -4)],
                              holes: [[Vec3(1, 0, -1), Vec3(1, 0, -3), Vec3(3, 0, -3), Vec3(3, 0, -1)]], normal: .unitY, from: 0, to: 1)
        assertSolid(ring)
        XCTAssertEqual(ring.volume, 12, accuracy: 1e-9)
        let top = ring.faces.indices.first { ring.normal(of: $0).y > 0.99 } ?? -1
        XCTAssertEqual(ring.area(of: top), 12, accuracy: 1e-9)
        let triangles = ring.triangulate(face: top)
        let area = triangles.reduce(0.0) { sum, tri in
            sum + (ring.vertices[tri.1] - ring.vertices[tri.0]).cross(ring.vertices[tri.2] - ring.vertices[tri.0]).length / 2
        }
        XCTAssertEqual(area, 12, accuracy: 1e-9)
    }

    func testCodableRoundTripKeepsTheMesh() throws {
        let mesh = EditableMesh.cylinder(base: .zero, radius: 3 * mm, height: 10 * mm, segments: 24)
        let data = try JSONEncoder().encode(ObjectKind.mesh(mesh))
        let decoded = try JSONDecoder().decode(ObjectKind.self, from: data)
        guard case let .mesh(back) = decoded else { return XCTFail("kind") }
        XCTAssertEqual(back.faces, mesh.faces)
        XCTAssertEqual(back.volume, mesh.volume, accuracy: 1e-12)
        XCTAssertEqual(back.vertices.count, mesh.vertices.count)
    }

    // MARK: Booleans

    func testABlockWithAHoleThroughIt() throws {
        let hole = EditableMesh.cylinder(base: Vec3(20 * mm, -1 * mm, 10 * mm), radius: 3 * mm, height: 12 * mm, segments: 32)
        let result = try MeshBoolean.combine(block, hole, .subtract)
        assertSolid(result)
        // Top and bottom are one face each, with one hole.
        let caps = result.faces.indices.filter { abs(result.normal(of: $0).y) > 0.99 }
        XCTAssertEqual(caps.count, 2)
        XCTAssertTrue(caps.allSatisfy { result.faces[$0].loops.count == 2 })
        // 4 sides + 2 caps + 32 hole walls.
        XCTAssertEqual(result.faces.count, 38)
        let expected = 40 * 20 * 10 * mm * mm * mm - holeVolume(radius: 3 * mm, height: 10 * mm, segments: 32)
        XCTAssertEqual(result.volume, expected, accuracy: 1e-12)
        // The block's own corners come back exact (not rounded through Float).
        XCTAssertTrue(result.vertices.contains(Vec3(40 * mm, 10 * mm, 20 * mm)))
    }

    func testUnionOfTwoTouchingBoxesMergesTheirFaces() throws {
        let left = EditableMesh.box(min: .zero, max: Vec3(1, 1, 1))
        let right = EditableMesh.box(min: Vec3(1, 0, 0), max: Vec3(2, 1, 1))
        let result = try MeshBoolean.combine(left, right, .union)
        assertSolid(result)
        XCTAssertEqual(result.faces.count, 6, "one long box: coplanar faces merged, the seam's corners dropped")
        XCTAssertEqual(result.vertices.count, 8)
        XCTAssertEqual(result.volume, 2, accuracy: 1e-9)
    }

    func testIntersectAndNothingLeft() throws {
        let a = EditableMesh.box(min: .zero, max: Vec3(2, 2, 2))
        let b = EditableMesh.box(min: Vec3(1, 1, 1), max: Vec3(3, 3, 3))
        XCTAssertEqual(try MeshBoolean.combine(a, b, .intersect).volume, 1, accuracy: 1e-9)
        let far = EditableMesh.box(min: Vec3(5, 5, 5), max: Vec3(6, 6, 6))
        XCTAssertThrowsError(try MeshBoolean.combine(a, far, .intersect)) { error in
            XCTAssertEqual(error as? MeshBoolean.Failure, .nothingLeft)
        }
    }

    func testAnOpenSurfaceIsRefused() {
        let plane = EditableMesh.primitive(.plane)
        XCTAssertFalse(MeshBoolean.isSolid(plane))
        XCTAssertThrowsError(try MeshBoolean.combine(block, plane, .union)) { error in
            XCTAssertEqual(error as? MeshBoolean.Failure, .notSolid)
        }
    }

    /// Acceptance: booleans produce manifold meshes on 50 randomized cases.
    func testFiftyRandomBooleansStayManifold() throws {
        var random = SeededRandom(seed: 0x5EED)
        var produced = 0
        for index in 0 ..< Self.randomCases {
            let a = randomSolid(&random, kind: index % 3)
            let b = randomSolid(&random, kind: (index / 3) % 3)
            let operation = MeshBoolean.Operation.allCases[index % 3]
            do {
                let result = try MeshBoolean.combine(a, b, operation)
                assertSolid(result)
                produced += 1
                // Combining again with the result keeps working (results are clean inputs).
                let again = try MeshBoolean.combine(result, randomSolid(&random, kind: 0), .union)
                XCTAssertTrue(MeshTopology(again).isClosedManifold)
            } catch MeshBoolean.Failure.nothingLeft {
                continue
            }
        }
        XCTAssertGreaterThan(produced, Self.randomCases * 7 / 10, "most random cases overlap")
    }

    private func randomSolid(_ random: inout SeededRandom, kind: Int) -> EditableMesh {
        let center = Vec3(rnd(&random, -0.4 ... 0.4), rnd(&random, -0.4 ... 0.4), rnd(&random, -0.4 ... 0.4))
        let size = Vec3(rnd(&random, 0.3 ... 1), rnd(&random, 0.3 ... 1), rnd(&random, 0.3 ... 1))
        let turn = Quat(angle: rnd(&random, 0 ... 3), axis: Vec3(rnd(&random, -1 ... 1), 1, rnd(&random, -1 ... 1)).normalized)
        let shape: EditableMesh = switch kind {
        case 0: .box(min: size * -0.5, max: size * 0.5)
        case 1: .cylinder(base: Vec3(0, -size.y / 2, 0), radius: size.x / 2, height: size.y, segments: 6 + Int(rnd(&random, 0 ... 20)))
        default: .primitive(.sphere, size: size).transformed(by: Transform(position: Vec3(0, -size.y / 2, 0)))
        }
        return shape.transformed(by: Transform(position: center, rotation: turn))
    }

    private func rnd(_ random: inout SeededRandom, _ range: ClosedRange<Double>) -> Double {
        random.range(range.lowerBound, range.upperBound)
    }

    private func holeVolume(radius: Double, height: Double, segments: Int) -> Double {
        0.5 * Double(segments) * radius * radius * sin(2 * .pi / Double(segments)) * height
    }

    // MARK: Push/pull

    func testPushPullSlidesASquareFaceToAnExactSize() throws {
        let box = block
        let top = box.faces.indices.first { box.normal(of: $0).y > 0.99 } ?? -1
        XCTAssertTrue(PushPull.slides(box, face: top))
        let taller = try PushPull.apply(box, face: top, distance: 5 * mm)
        XCTAssertEqual(taller.faces.count, 6, "same faces, stretched")
        XCTAssertEqual(taller.bounds?.size.y ?? 0, 15 * mm, accuracy: 1e-12)
        let lower = try PushPull.apply(box, face: top, distance: -4 * mm)
        XCTAssertEqual(lower.bounds?.size.y ?? 0, 6 * mm, accuracy: 1e-12)
        XCTAssertThrowsError(try PushPull.apply(box, face: top, distance: -10 * mm)) { error in
            XCTAssertEqual(error as? PushPull.Failure, .tooFar)
        }
    }

    func testPushPullOnASlopedFaceAddsAPrism() throws {
        let ramp = EditableMesh.primitive(.ramp)
        assertSolid(ramp)
        let slope = ramp.faces.indices.first { face in
            let normal = ramp.normal(of: face)
            return normal.y > 0.1 && normal.y < 0.99
        } ?? -1
        XCTAssertGreaterThanOrEqual(slope, 0)
        XCTAssertFalse(PushPull.slides(ramp, face: slope))
        let thicker = try PushPull.apply(ramp, face: slope, distance: 0.1)
        assertSolid(thicker)
        XCTAssertGreaterThan(thicker.volume, ramp.volume + ramp.area(of: slope) * 0.1 * 0.99)
        let thinner = try PushPull.apply(ramp, face: slope, distance: -0.1)
        assertSolid(thinner)
        XCTAssertLessThan(thinner.volume, ramp.volume)
    }

    // MARK: Selection

    func testGrowShrinkAndSimilarFaces() {
        let box = block
        let top = box.faces.indices.first { box.normal(of: $0).y > 0.99 } ?? -1
        let picked = MeshSelection(mode: .face, faces: [top])
        let grown = picked.grown(in: box)
        XCTAssertEqual(grown.faces.count, 5, "the top and its four sides")
        XCTAssertEqual(grown.shrunk(in: box).faces, [top])
        let side = box.faces.indices.first { box.normal(of: $0).x > 0.99 } ?? -1
        let similar = MeshSelection(mode: .face, faces: [side]).similar(in: box)
        XCTAssertEqual(similar.faces.count, 1, "the opposite side faces the other way")
        let edges = MeshSelection(mode: .edge, edges: [MeshEdge(0, 1)]).similar(in: box)
        XCTAssertEqual(edges.edges.count, 4, "the four 40 mm edges")
    }

    func testPickingAndLasso() {
        let box = block
        let ray = Ray(origin: Vec3(20 * mm, 1, 10 * mm), direction: Vec3(0, -1, 0))
        let hit = MeshPicking.face(ray, in: box)
        XCTAssertEqual(hit.map { box.normal(of: $0.face).y } ?? 0, 1, accuracy: 1e-9)
        // Looking straight down, the screen is x/z.
        let project: (Vec3) -> Vec2? = { Vec2($0.x, $0.z) }
        let corner = MeshPicking.pick(ray, screenPoint: Vec2(39 * mm, 19 * mm), mode: .vertex, in: box, project: project)
        XCTAssertEqual(corner.map { box.vertices[$0.vertices.first ?? 0] }, Vec3(40 * mm, 10 * mm, 20 * mm))
        let loop = [Vec2(-1, -1), Vec2(1, -1), Vec2(1, 1), Vec2(-1, 1)]
        let caught = MeshSelection.lasso(loop, mode: .vertex, in: box, project: project) { box.normal(of: $0).y > 0.5 }
        XCTAssertEqual(caught.vertices.count, 4, "only the corners of faces facing up")
    }

    // MARK: Lengths

    func testTypedLengths() throws {
        func value(_ text: String, _ unit: LengthUnit = .millimetre) throws -> Double {
            try LengthExpression.evaluate(text, defaultUnit: unit)
        }
        XCTAssertEqual(try value("25mm"), 0.025, accuracy: 1e-12)
        XCTAssertEqual(try value("25"), 0.025, accuracy: 1e-12)
        XCTAssertEqual(try value("2*12"), 0.024, accuracy: 1e-12)
        XCTAssertEqual(try value("2 × 12 mm"), 0.024, accuracy: 1e-12)
        XCTAssertEqual(try value("1ft 6in", .metre), 0.4572, accuracy: 1e-12)
        XCTAssertEqual(try value("(40-6)/2"), 0.017, accuracy: 1e-12)
        XCTAssertEqual(try value("1.5cm + 2"), 0.017, accuracy: 1e-12)
        XCTAssertEqual(try value("-3,5"), -0.0035, accuracy: 1e-12)
        XCTAssertThrowsError(try value("2 apples"))
        XCTAssertThrowsError(try value("4/0"))
        XCTAssertEqual(LengthUnit.millimetre.format(0.04), "40 mm")
        XCTAssertEqual(LengthUnit.millimetre.format(0.01234), "12.3 mm")
        XCTAssertEqual(LengthUnit.metre.format(1.25), "1.25 m")
    }
}
