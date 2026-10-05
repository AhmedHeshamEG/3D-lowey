import Foundation
@testable import LoweyCore
import XCTest

/// Sketches fill into regions, and regions pull into solids or cut into them, as one undo step each.
final class SketchTests: XCTestCase {
    private let mm = 0.001
    private let ground = PlaneFrame(origin: .zero, normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))

    func testClosedShapesFillAndNestedOnesMakeHoles() {
        let sketch = Sketch(plane: ground, curves: [
            .rectangle(Vec2(0, 0), Vec2(40 * mm, 20 * mm)),
            .circle(center: Vec2(20 * mm, 10 * mm), radius: 3 * mm),
            .line(Vec2(60 * mm, 0), Vec2(70 * mm, 0))
        ])
        let regions = sketch.regions
        XCTAssertEqual(regions.count, 2, "the open line fills nothing")
        let ring = sketch.region(at: Vec2(5 * mm, 5 * mm)).map { regions[$0] }
        XCTAssertEqual(ring?.holes.count, 1)
        let disc = sketch.region(at: Vec2(20 * mm, 10 * mm)).map { regions[$0] }
        XCTAssertEqual(disc?.holes.count, 0)
        XCTAssertEqual(disc?.area ?? 0, .pi * 9 * mm * mm, accuracy: 0.002 * .pi * 9 * mm * mm)
        XCTAssertNil(sketch.region(at: Vec2(65 * mm, 5 * mm)))
    }

    func testLinesDrawnCornerToCornerClose() {
        let sketch = Sketch(plane: ground, curves: [
            .line(Vec2(0, 0), Vec2(1, 0)), .line(Vec2(1, 0), Vec2(1, 1)), .line(Vec2(0, 1), Vec2(1, 1)), .line(Vec2(0, 1), Vec2(0, 0))
        ])
        XCTAssertEqual(sketch.regions.count, 1)
        XCTAssertEqual(sketch.regions.first?.area ?? 0, 1, accuracy: 1e-12)
    }

    func testArcsSplinesAndOffsets() {
        let arc = SketchCurve.arc(Vec2(1, 0), Vec2(0, 1), Vec2(-1, 0)).points
        XCTAssertEqual(arc.first?.x ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(arc.last?.x ?? 0, -1, accuracy: 1e-9)
        XCTAssertTrue(arc.allSatisfy { $0.y >= -1e-9 && abs($0.length - 1) < 1e-9 }, "the upper half, through (0, 1)")
        let spline = SketchCurve.spline([Vec2(0, 0), Vec2(1, 1), Vec2(2, 0)], closed: false).points
        XCTAssertEqual(spline.first, Vec2(0, 0))
        XCTAssertEqual(spline.last, Vec2(2, 0))
        XCTAssertTrue(spline.contains { abs($0.x - 1) < 1e-9 && abs($0.y - 1) < 1e-9 }, "passes through its points")
        guard case let .circle(_, radius)? = SketchCurve.circle(center: .init(0, 0), radius: 2).offset(by: 0.5) else { return XCTFail("circle") }
        XCTAssertEqual(radius, 2.5)
        let square = SketchCurve.polyline([Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true).offset(by: -0.5)
        XCTAssertEqual(square.map { abs(PolygonTriangulator.signedArea($0.points)) } ?? 0, 1, accuracy: 1e-9, "inset by 0.5 on every side")
    }

    /// The acceptance flow in Core: a 40 × 20 mm rectangle pulled 10 mm, a 6 mm circle on its top cut through it.
    func testABlockWithAHoleFromSketches() throws {
        var ids = IDFactory.sequential("t")
        var document = emptyDocument()
        let sketchID: ObjectID = ids.next()
        let sketch = ModelingOperations.newSketch(on: ground, curves: [.rectangle(Vec2(0, 0), Vec2(40 * mm, 20 * mm))], target: nil, id: sketchID)
        try document.run(.insert(SceneFragment(object: sketch), parent: nil, index: nil))
        try document.run(ModelingOperations.pull(sketch: sketchID, region: 0, distance: 10 * mm, in: document.scene, ids: &ids))
        XCTAssertNil(document.scene.objects[sketchID], "the used-up sketch is gone")
        guard let solid = document.scene.objects.values.first(where: { $0.kind.typeName == "mesh" }),
              case let .mesh(block) = solid.kind else { return XCTFail("a solid") }
        let world = block.transformed(by: document.scene.worldTransform(of: solid.id))
        XCTAssertEqual(world.bounds?.size.x ?? 0, 40 * mm, accuracy: 1e-12)
        XCTAssertEqual(world.bounds?.size.y ?? 0, 10 * mm, accuracy: 1e-12)
        XCTAssertEqual(world.bounds?.size.z ?? 0, 20 * mm, accuracy: 1e-12)

        // A circle on the top face, cut down through the block.
        let top = PlaneFrame(origin: Vec3(0, 10 * mm, 0), normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))
        let circleID: ObjectID = ids.next()
        let circle = ModelingOperations.newSketch(on: top, curves: [.circle(center: Vec2(20 * mm, 10 * mm), radius: 3 * mm)],
                                                  target: solid.id, id: circleID)
        try document.run(.insert(SceneFragment(object: circle), parent: nil, index: nil))
        let cut = try ModelingOperations.pull(sketch: circleID, region: 0, distance: -10 * mm, in: document.scene, ids: &ids)
        XCTAssertEqual(cut.label, "Cut")
        try document.run(cut)
        guard case let .mesh(holed)? = document.scene.objects[solid.id]?.kind else { return XCTFail("still a mesh") }
        XCTAssertTrue(MeshTopology(holed).isClosedManifold)
        let caps = holed.faces.indices.filter { abs(holed.normal(of: $0).y) > 0.99 }
        XCTAssertEqual(caps.count, 2)
        XCTAssertTrue(caps.allSatisfy { holed.faces[$0].loops.count == 2 }, "a hole all the way through")
    }

    func testBooleanCommandKeepsTheFirstAndUndoes() throws {
        var document = emptyDocument()
        var ids = IDFactory.sequential("b")
        let a = SceneObject(id: ids.next(), name: "A", kind: .primitive(.cube), transform: Transform(scale: Vec3(2, 1, 1)))
        let b = SceneObject(id: ids.next(), name: "B", kind: .primitive(.cube), transform: Transform(position: Vec3(1, 0, 0)))
        try document.run(.insert(SceneFragment(objects: [a, b], roots: [a.id, b.id]), parent: nil, index: nil))
        let before = document.scene
        let command = try ModelingOperations.boolean([a.id, b.id], .union, in: document.scene)
        let inverse = try document.run(command)
        XCTAssertNil(document.scene.objects[b.id])
        guard case let .mesh(mesh)? = document.scene.objects[a.id]?.kind else { return XCTFail("mesh") }
        // A spans x −1…1, B 0.5…1.5: together −1…1.5, in A's space (scale 2) −0.5…0.75.
        XCTAssertEqual(mesh.bounds?.max.x ?? 0, 0.75, accuracy: 1e-9)
        XCTAssertEqual(mesh.faces.count, 6)
        try document.run(inverse)
        XCTAssertEqual(document.scene, before, "one undo step puts both back")
    }

    func testPushPullBakesScaleSoLengthsAreReal() throws {
        var document = emptyDocument()
        let cube = SceneObject(id: "c", name: "Cube", kind: .primitive(.cube), transform: Transform(scale: Vec3(0.04, 0.01, 0.02)))
        try document.run(.insert(SceneFragment(object: cube), parent: nil, index: nil))
        guard let (mesh, _) = ModelingOperations.bakedMesh(of: cube) else { return XCTFail("bakes") }
        let top = mesh.faces.indices.first { mesh.normal(of: $0).y > 0.99 } ?? -1
        try document.run(ModelingOperations.pushPull(cube.id, face: top, distance: 5 * mm, in: document.scene))
        guard let object = document.scene.objects[cube.id], case let .mesh(result) = object.kind else { return XCTFail("mesh") }
        XCTAssertEqual(object.transform.scale, .one)
        XCTAssertEqual(result.bounds?.size.y ?? 0, 15 * mm, accuracy: 1e-12)
    }

    func testCommandsRoundTripThroughTheJournalFormat() throws {
        let sketch = Sketch(plane: ground, curves: [.circle(center: .init(0, 0), radius: 1), .arc(.init(1, 0), .init(0, 1), .init(-1, 0))])
        let command = EditCommand.batch("Pull", [.setKind("s", .sketch(sketch)), .setKind("m", .mesh(.box(min: .zero, max: .one)))])
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(EditCommand.self, from: data), command)
    }
}

private func emptyDocument() -> Document {
    let scene = Scene(id: "scene-1", name: "Test", objects: [:], roots: [])
    let info = ProjectInfo(id: "project-1", name: "Test", created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0),
                           sceneOrder: ["scene-1"], sceneNames: ["scene-1": "Test"])
    return Document(project: info, scene: scene)
}

private extension Document {
    /// Applies a command and returns its inverse.
    @discardableResult
    mutating func run(_ command: EditCommand) throws -> EditCommand {
        try command.apply(to: &self).inverse
    }
}
