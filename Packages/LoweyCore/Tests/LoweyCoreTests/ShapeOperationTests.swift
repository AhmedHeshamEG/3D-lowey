import Foundation
@testable import LoweyCore
import XCTest

/// Modelling II's shape operations: inset, bevel and round, shell, mirror and live symmetry, several faces at once.
final class ShapeOperationTests: XCTestCase {
    private let mm = 0.001

    /// 40 × 10 × 20 mm, like M3's acceptance block.
    private var block: EditableMesh { .box(min: .zero, max: Vec3(40 * mm, 10 * mm, 20 * mm)) }

    private func assertSolid(_ mesh: EditableMesh, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(MeshTopology(mesh).isClosedManifold, "closed manifold", file: file, line: line)
        XCTAssertTrue(MeshBoolean.isSolid(mesh), "Manifold accepts it", file: file, line: line)
        XCTAssertGreaterThan(mesh.volume, 0, "faces point out", file: file, line: line)
    }

    private func face(_ mesh: EditableMesh, facing direction: Vec3) -> Int {
        mesh.faces.indices.first { mesh.normal(of: $0).dot(direction) > 0.999 } ?? -1
    }

    private func edge(_ mesh: EditableMesh, between first: Vec3, and second: Vec3) -> MeshEdge? {
        let topology = MeshTopology(mesh)
        return mesh.edges.first { edge in
            let normals = topology.faces(along: edge).map { mesh.normal(of: $0) }
            return normals.contains { $0.dot(first) > 0.999 } && normals.contains { $0.dot(second) > 0.999 }
        }
    }

    // MARK: Inset

    func testInsetMakesARingAndKeepsTheFacePicked() throws {
        let mesh = block
        let top = face(mesh, facing: .unitY)
        let inset = try Inset.apply(mesh, faces: [top], distance: 5 * mm)
        assertSolid(inset)
        XCTAssertEqual(inset.faces.count, 6 + 4, "four ring faces")
        XCTAssertEqual(inset.volume, mesh.volume, accuracy: 1e-15, "inset alone doesn't change the shape")
        XCTAssertEqual(inset.area(of: top), 30 * mm * 10 * mm, accuracy: 1e-12, "the same index is now the inner face")
        // Then the inner face pushes in on its own: a pocket.
        let pocket = try PushPull.apply(inset, face: top, distance: -3 * mm)
        assertSolid(pocket)
        XCTAssertEqual(pocket.volume, mesh.volume - 30 * mm * 10 * mm * 3 * mm, accuracy: 1e-14)
    }

    func testInsetGrowsHolesAndRefusesToCloseUp() throws {
        let ring = Prism.make(outline: [Vec3(0, 0, 0), Vec3(4, 0, 0), Vec3(4, 0, -4), Vec3(0, 0, -4)],
                              holes: [[Vec3(1.5, 0, -1.5), Vec3(1.5, 0, -2.5), Vec3(2.5, 0, -2.5), Vec3(2.5, 0, -1.5)]],
                              normal: .unitY, from: 0, to: 1)
        let top = face(ring, facing: .unitY)
        let inset = try Inset.apply(ring, faces: [top], distance: 0.25)
        assertSolid(inset)
        // Outline 3.5 × 3.5, hole 1.5 × 1.5.
        XCTAssertEqual(inset.area(of: top), 3.5 * 3.5 - 1.5 * 1.5, accuracy: 1e-9)
        XCTAssertThrowsError(try Inset.apply(ring, faces: [top], distance: 0.8)) { XCTAssertEqual($0 as? Inset.Failure, .tooFar) }
        XCTAssertThrowsError(try Inset.apply(block, faces: [face(block, facing: .unitY)], distance: 25 * mm)) {
            XCTAssertEqual($0 as? Inset.Failure, .tooFar)
        }
    }

    // MARK: Bevel and round

    func testBevelOneEdgeCutsAnExactTriangle() throws {
        let mesh = block
        let edge = try XCTUnwrap(edge(mesh, between: .unitY, and: .unitZ))
        let bevelled = try EdgeBevel.apply(mesh, edges: [edge], size: 2 * mm, style: .chamfer)
        assertSolid(bevelled)
        XCTAssertEqual(bevelled.faces.count, 7, "one new slanted face")
        XCTAssertEqual(bevelled.volume, mesh.volume - 0.5 * 2 * mm * 2 * mm * 40 * mm, accuracy: 1e-14)
        // The slanted face is 40 mm long and 2√2 mm wide.
        let slanted = bevelled.faces.indices.first { abs(bevelled.normal(of: $0).dot(Vec3(0, 1, 1).normalized)) > 0.999 } ?? -1
        XCTAssertEqual(bevelled.area(of: slanted), 40 * mm * 2 * mm * 2.0.squareRoot(), accuracy: 1e-12)
    }

    func testRoundingAnEdgeRemovesTheCornerOutsideTheArc() throws {
        let mesh = block
        let edge = try XCTUnwrap(edge(mesh, between: .unitY, and: .unitX))
        let rounded = try EdgeBevel.apply(mesh, edges: [edge], size: 3 * mm, style: .round)
        assertSolid(rounded)
        // The corner beyond a quarter circle: r² (1 - π/4), along the 20 mm edge; the arc is 8 flat strips.
        let exact = mesh.volume - 3 * mm * 3 * mm * (1 - .pi / 4) * 20 * mm
        XCTAssertEqual(rounded.volume, exact, accuracy: exact * 2e-3)
        XCTAssertEqual(rounded.faces.count, 6 + 8)
    }

    func testRoundingEveryEdgeOfABlockStaysSolid() throws {
        let mesh = block
        let all = Set(mesh.edges)
        let rounded = try EdgeBevel.apply(mesh, edges: all, size: 2 * mm, style: .round)
        assertSolid(rounded)
        XCTAssertLessThan(rounded.volume, mesh.volume)
        let bounds = try XCTUnwrap(rounded.bounds)
        XCTAssertTrue(bounds.size.isApproximately(Vec3(40 * mm, 10 * mm, 20 * mm), tolerance: 1e-9), "rounding keeps the size")
    }

    func testAnInsideEdgeIsFilled() throws {
        // An L: a 20 × 10 block with a 10 × 10 block on its left half; the inside corner runs along z.
        let base = EditableMesh.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 10 * mm))
        let tower = EditableMesh.box(min: Vec3(0, 10 * mm, 0), max: Vec3(10 * mm, 20 * mm, 10 * mm))
        let ell = try MeshBoolean.combine(base, tower, .union)
        let inside = try XCTUnwrap(ell.edges.first { edge in
            let a = ell.vertices[edge.a], b = ell.vertices[edge.b]
            return abs(a.x - 10 * mm) < 1e-12 && abs(b.x - 10 * mm) < 1e-12 && abs(a.y - 10 * mm) < 1e-12 && abs(b.y - 10 * mm) < 1e-12
        })
        let filled = try EdgeBevel.apply(ell, edges: [inside], size: 2 * mm, style: .chamfer)
        assertSolid(filled)
        XCTAssertEqual(filled.volume, ell.volume + 0.5 * 2 * mm * 2 * mm * 10 * mm, accuracy: 1e-14)
    }

    func testBevelRefusals() throws {
        let mesh = block
        let edge = try XCTUnwrap(edge(mesh, between: .unitY, and: .unitZ))
        XCTAssertThrowsError(try EdgeBevel.apply(mesh, edges: [edge], size: 15 * mm, style: .chamfer)) {
            XCTAssertEqual($0 as? EdgeBevel.Failure, .tooBig)
        }
        let plane = EditableMesh(vertices: [.zero, Vec3(1, 0, 0), Vec3(1, 0, -1), Vec3(0, 0, -1)], faces: [EditableMesh.Face([0, 1, 2, 3])])
        XCTAssertThrowsError(try EdgeBevel.apply(plane, edges: [MeshEdge(0, 1)], size: 0.1, style: .round)) {
            XCTAssertEqual($0 as? EdgeBevel.Failure, .notSolid)
        }
    }

    // MARK: Shell

    func testShellHollowsAndOpensTheTop() throws {
        let mesh = block
        let closed = try Shell.apply(mesh, thickness: 2 * mm)
        assertSolid(closed)
        let cavity = 36 * mm * 6 * mm * 16 * mm
        XCTAssertEqual(closed.volume, mesh.volume - cavity, accuracy: 1e-14)
        let top = face(mesh, facing: .unitY)
        let open = try Shell.apply(mesh, thickness: 2 * mm, open: [top])
        assertSolid(open)
        // The cavity now reaches through the top: 36 × 8 × 16.
        XCTAssertEqual(open.volume, mesh.volume - 36 * mm * 8 * mm * 16 * mm, accuracy: 1e-14)
        XCTAssertThrowsError(try Shell.apply(mesh, thickness: 6 * mm)) { XCTAssertEqual($0 as? Shell.Failure, .tooThick) }
    }

    func testShellWorksOnARoundSolid() throws {
        let cylinder = EditableMesh.cylinder(base: .zero, radius: 10 * mm, height: 30 * mm, segments: 24)
        let top = face(cylinder, facing: .unitY)
        let cup = try Shell.apply(cylinder, thickness: 1.5 * mm, open: [top])
        assertSolid(cup)
        XCTAssertLessThan(cup.volume, cylinder.volume * 0.4)
    }

    // MARK: Several faces, mirror, symmetry

    func testOppositeFacesPullTogether() throws {
        let mesh = block
        let left = face(mesh, facing: -.unitX), right = face(mesh, facing: .unitX)
        let wider = try PushPull.apply(mesh, faces: [left, right], distance: 5 * mm)
        assertSolid(wider)
        XCTAssertEqual(wider.faces.count, 6, "both slid")
        XCTAssertEqual(try XCTUnwrap(wider.bounds).size.x, 50 * mm, accuracy: 1e-15)
        // A top and a front that share an edge slide together too.
        let corner = try PushPull.apply(mesh, faces: [face(mesh, facing: .unitY), face(mesh, facing: .unitZ)], distance: 2 * mm)
        XCTAssertEqual(corner.volume, 40 * mm * 12 * mm * 22 * mm, accuracy: 1e-14)
    }

    func testMirrorReflectsAndSymmetrizeJoinsHalves() throws {
        let half = EditableMesh.box(min: Vec3(0, 0, 0), max: Vec3(10 * mm, 5 * mm, 5 * mm))
        let plane = MirrorPlane(origin: .zero, normal: .unitX)
        let mirrored = MeshMirror.reflected(half, across: plane)
        assertSolid(mirrored)
        XCTAssertEqual(try XCTUnwrap(mirrored.bounds).min.x, -10 * mm, accuracy: 1e-15)
        let whole = try MeshMirror.symmetrize(half, across: plane, keepPositive: true)
        assertSolid(whole)
        XCTAssertEqual(whole.faces.count, 6, "the halves merge into one box")
        XCTAssertEqual(whole.volume, 2 * half.volume, accuracy: 1e-15)
        // An off-centre shape keeps the side asked for.
        let shifted = EditableMesh.box(min: Vec3(-2 * mm, 0, 0), max: Vec3(8 * mm, 5 * mm, 5 * mm))
        let kept = try MeshMirror.symmetrize(shifted, across: plane, keepPositive: true)
        XCTAssertEqual(try XCTUnwrap(kept.bounds).size.x, 16 * mm, accuracy: 1e-12)
        XCTAssertThrowsError(try MeshMirror.symmetrize(half, across: plane, keepPositive: false))
    }

    func testCounterpartFacesAcrossThePlane() {
        let box = EditableMesh.box(min: Vec3(-5, 0, -1), max: Vec3(5, 1, 1))
        let plane = SymmetryAxis.x.plane
        let left = face(box, facing: -.unitX), right = face(box, facing: .unitX), top = face(box, facing: .unitY)
        XCTAssertEqual(MeshMirror.counterpart(of: left, in: box, across: plane), right)
        XCTAssertEqual(MeshMirror.counterpart(of: top, in: box, across: plane), top, "a face across the plane is its own mirror")
    }

    // MARK: Commands

    private func session(with mesh: EditableMesh, at position: Vec3 = .zero) -> (EditSession, ObjectID) {
        let id: ObjectID = "solid"
        let object = SceneObject(id: id, name: "Solid", kind: .mesh(mesh), transform: Transform(position: position))
        let scene = Scene(id: "s", name: "S", objects: [id: object], roots: [id])
        let info = ProjectInfo(id: "p", name: "P", created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0),
                               sceneOrder: ["s"], sceneNames: ["s": "S"])
        return (EditSession(document: Document(project: info, scene: scene)), id)
    }

    private func mesh(of id: ObjectID, in session: EditSession) -> EditableMesh? {
        guard case let .mesh(mesh) = session.document.scene.objects[id]?.kind else { return nil }
        return mesh
    }

    func testSymmetryKeepsBothSidesInStepAndUndoes() throws {
        let off = EditableMesh.box(min: Vec3(-10 * mm, 0, -5 * mm), max: Vec3(14 * mm, 6 * mm, 5 * mm))
        var (session, id) = session(with: off, at: Vec3(1, 0, 0))
        try session.perform(ModelingOperations.setSymmetry(id, .x, in: session.document.scene))
        let centred = try XCTUnwrap(mesh(of: id, in: session))
        XCTAssertEqual(try XCTUnwrap(centred.bounds).center.x, 0, accuracy: 1e-12, "the pivot is in the middle now")
        XCTAssertEqual(session.document.scene.worldTransform(of: id).position.x, 1 + 2 * mm, accuracy: 1e-12, "nothing moved on screen")
        XCTAssertEqual(try ModelingOperations.symmetry(of: XCTUnwrap(session.document.scene.objects[id])), .x)
        // Pull the right side: the left follows.
        let right = face(centred, facing: .unitX)
        try session.perform(ModelingOperations.pushPull(id, face: right, distance: 3 * mm, in: session.document.scene))
        let pulled = try XCTUnwrap(mesh(of: id, in: session)?.bounds)
        XCTAssertEqual(pulled.min.x, -15 * mm, accuracy: 1e-12)
        XCTAssertEqual(pulled.max.x, 15 * mm, accuracy: 1e-12)
        // Bevel an edge on the left: the right gets it too.
        let current = try XCTUnwrap(mesh(of: id, in: session))
        let leftTop = try XCTUnwrap(edge(current, between: -.unitX, and: .unitY))
        try session.perform(ModelingOperations.bevel(id, edges: [leftTop], size: 1 * mm, style: .chamfer, in: session.document.scene))
        let bevelled = try XCTUnwrap(mesh(of: id, in: session))
        assertSolid(bevelled)
        XCTAssertEqual(bevelled.faces.count, 8, "a slanted face on each side")
        try session.undo()
        try session.undo()
        try session.undo()
        XCTAssertEqual(mesh(of: id, in: session), off)
        XCTAssertEqual(session.document.scene.worldTransform(of: id).position.x, 1, accuracy: 1e-12)
    }

    func testMirrorCommandMakesATwinOrJoins() throws {
        var (session, id) = session(with: .box(min: Vec3(-1, 0, -1), max: Vec3(1, 1, 1)), at: Vec3(5, 0, 0))
        let start = session
        var ids = IDFactory.sequential("m")
        try session.perform(ModelingOperations.mirror(id, across: MirrorPlane(origin: .zero, normal: .unitX), in: session.document.scene, ids: &ids))
        XCTAssertEqual(session.document.scene.objects.count, 2)
        let copy = try XCTUnwrap(session.document.scene.objects.values.first { $0.id != id })
        XCTAssertEqual(session.document.scene.worldTransform(of: copy.id).position.x, -5, accuracy: 1e-9, "its twin across the middle")
        // Across its own side face, it joins into one solid twice as long.
        var other = start
        try other.perform(ModelingOperations.mirror(id, across: MirrorPlane(origin: Vec3(6, 0, 0), normal: .unitX), in: other.document.scene,
                                                    ids: &ids))
        XCTAssertEqual(other.document.scene.objects.count, 1)
        XCTAssertEqual(try XCTUnwrap(mesh(of: id, in: other)?.bounds).size.x, 4, accuracy: 1e-9)
    }

    func testShapeCommandsAreOneLabelledStep() throws {
        let (session, id) = session(with: block)
        let scene = session.document.scene
        let top = face(block, facing: .unitY)
        let commands = try [
            ModelingOperations.inset(id, faces: [top], distance: 2 * mm, in: scene),
            ModelingOperations.shell(id, thickness: 1 * mm, open: [top], in: scene),
            ModelingOperations.bevel(id, edges: [XCTUnwrap(edge(block, between: .unitY, and: .unitZ))], size: 1 * mm, style: .round, in: scene)
        ]
        XCTAssertEqual(commands.map(\.label), ["Inset", "Shell", "Round"])
        XCTAssertThrowsError(try ModelingOperations.shell(id, thickness: 30 * mm, open: [], in: scene)) {
            XCTAssertEqual(($0 as? ModelingOperations.Failure)?.description, Shell.Failure.tooThick.description)
        }
    }
}

/// Arrays along a path (a sketch's curve).
final class PathArrayTests: XCTestCase {
    func testCopiesSpreadEvenlyAlongAnOpenPath() {
        let path = [Vec3(0, 0, 0), Vec3(4, 0, 0), Vec3(4, 0, -4)]
        let base = Transform(position: Vec3(10, 0, 0))
        let places = PathSampler.transforms(along: path, closed: false, count: 5, from: base, align: false)
        XCTAssertEqual(places.count, 4, "the original is the first of five")
        XCTAssertTrue(places[1].position.isApproximately(Vec3(14, 0, 0)), "halfway is the corner")
        XCTAssertTrue(places[3].position.isApproximately(Vec3(14, 0, -4)), "the last one sits on the end")
    }

    func testAlignedCopiesTurnWithTheCurveAndClosedPathsGoRound() {
        let square = [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 0, -2), Vec3(0, 0, -2)]
        let places = PathSampler.transforms(along: square, closed: true, count: 4, from: .identity, align: true)
        XCTAssertEqual(places.count, 3)
        XCTAssertTrue(places[0].position.isApproximately(Vec3(2, 0, 0)))
        XCTAssertTrue(places[2].position.isApproximately(Vec3(0, 0, -2)))
        // At the end of the second side the path runs along -z: that copy is turned a quarter turn from +x.
        XCTAssertTrue(places[1].position.isApproximately(Vec3(2, 0, -2)))
        XCTAssertTrue(places[1].rotation.act(.unitX).isApproximately(Vec3(0, 0, -1), tolerance: 1e-9))
    }

    func testArrayAlongASketchCurveIsOneGroupedStep() throws {
        let cube = SceneObject(id: "cube", name: "Post", kind: .primitive(.cube))
        let sketch = Sketch(plane: PlaneFrame(normal: .unitY, origin: .zero), curves: [.line(Vec2(0, 0), Vec2(6, 0))])
        let line = SceneObject(id: "sketch", name: "Sketch", kind: .sketch(sketch))
        let scene = Scene(id: "s", name: "S", objects: ["cube": cube, "sketch": line], roots: ["cube", "sketch"])
        let path = try XCTUnwrap(sketch.path())
        var operations = Operations(ids: .sequential("a"))
        let (command, group) = try XCTUnwrap(operations.array("cube", layout: .path(count: 4, points: path.points, closed: path.closed, align: true),
                                                              in: scene))
        var document = Document(project: ProjectInfo(id: "p", name: "P", created: Date(timeIntervalSince1970: 0),
                                                     modified: Date(timeIntervalSince1970: 0), sceneOrder: ["s"], sceneNames: ["s": "S"]),
                                scene: scene)
        _ = try command.apply(to: &document)
        XCTAssertEqual(document.scene.objects[group]?.children.count, 4)
        // The ground plane's sketch x runs along the world's z.
        let along = (document.scene.objects[group]?.children ?? []).map { document.scene.worldTransform(of: $0).position }
        XCTAssertEqual(along.map(\.z).sorted(), [0, 2, 4, 6].map { Double($0) }, accuracy: 1e-9)
    }
}

private func XCTAssertEqual(_ lhs: [Double], _ rhs: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (a, b) in zip(lhs, rhs) {
        XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line)
    }
}
