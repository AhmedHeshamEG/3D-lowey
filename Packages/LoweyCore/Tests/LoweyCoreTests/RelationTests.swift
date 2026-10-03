import Foundation
@testable import LoweyCore
import XCTest

final class RelationTests: XCTestCase {
    private var kit: KitIndex!

    override func setUpWithError() throws {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Kit")
        kit = try KitIndex.load(from: root)
    }

    /// A desk turned to face +X at (2, 0, 1), a lamp and a cube lying around elsewhere.
    private func deskScene() -> (Scene, LibraryManifest) {
        var manifest = LibraryManifest()
        manifest.kit = kit.assets
        var scene = Scene(id: "s", name: "Desk")
        let desk = SceneObject(id: "desk", name: "Desk", kind: .asset("kit.office-desk"),
                               transform: Transform(position: Vec3(2, 0, 1), rotation: Quat(angle: .pi / 2, axis: .unitY)))
        let lamp = SceneObject(id: "lamp", name: "Lamp", kind: .asset("kit.room-lamproundtable"), transform: Transform(position: Vec3(-3, 0, -3)))
        var box = SceneObject(id: "box", name: "Box", kind: .primitive(.cube), transform: Transform(position: Vec3(-1, 0, 4)))
        box.transform.scale = Vec3(0.5, 0.5, 0.5)
        for object in [desk, lamp, box] {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        return (scene, manifest)
    }

    private func apply(_ placements: [Placement], solver: RelationSolver) throws -> Scene {
        var document = Document(project: ProjectInfo(id: "p", name: "P"), scene: solver.scene)
        _ = try solver.command(for: placements).apply(to: &document)
        return document.scene
    }

    func testALampOnTheDeskLandsOnItsTopFacingItsFront() throws {
        let (scene, manifest) = deskScene()
        let solver = RelationSolver(scene: scene, library: manifest)
        let placed = try apply(solver.place(["lamp"], .on, reference: "desk"), solver: solver)
        let after = RelationSolver(scene: placed, library: manifest)
        let lamp = try XCTUnwrap(after.bounds.worldBounds(of: "lamp", in: placed))
        let desk = try XCTUnwrap(after.bounds.worldBounds(of: "desk", in: placed))
        let top = try XCTUnwrap(kit.assets.first { $0.id.raw == "kit.office-desk" }?.kit?.surfaces.first)
        XCTAssertEqual(lamp.min.y, top.height, accuracy: 0.01, "standing on the desk's top")
        XCTAssertTrue(after.isGrounded("lamp").grounded, "grounded (gap \(after.isGrounded("lamp").gap))")
        XCTAssertGreaterThanOrEqual(lamp.min.x, desk.min.x - 0.01)
        XCTAssertLessThanOrEqual(lamp.max.x, desk.max.x + 0.01)
        XCTAssertGreaterThanOrEqual(lamp.min.z, desk.min.z - 0.01)
        XCTAssertLessThanOrEqual(lamp.max.z, desk.max.z + 0.01)
        // Facing the desk's front (+X once the desk is turned).
        let front = placed.worldTransform(of: "lamp").rotation.act(Vec3(0, 0, 1))
        XCTAssertEqual(front.x, 1, accuracy: 1e-6)
    }

    func testASecondThingOnTheDeskFindsItsOwnSpot() throws {
        let (scene, manifest) = deskScene()
        var solver = RelationSolver(scene: scene, library: manifest)
        var placed = try apply(solver.place(["lamp"], .on, reference: "desk"), solver: solver)
        solver = RelationSolver(scene: placed, library: manifest)
        placed = try apply(solver.place(["box"], .on, reference: "desk"), solver: solver)
        let bounds = SceneBounds(library: manifest)
        let lamp = try XCTUnwrap(bounds.worldBounds(of: "lamp", in: placed))
        let box = try XCTUnwrap(bounds.worldBounds(of: "box", in: placed))
        XCTAssertFalse(RelationSolver.overlap(lamp, box), "no intersection")
        XCTAssertEqual(box.min.y, lamp.min.y, accuracy: 0.01, "both on the top")
    }

    func testBesideAndInFrontStayOnTheFloorAndApart() throws {
        let (scene, manifest) = deskScene()
        let solver = RelationSolver(scene: scene, library: manifest)
        let placed = try apply(solver.place(["box"], .besideLeft, reference: "desk"), solver: solver)
        let bounds = SceneBounds(library: manifest)
        let box = try XCTUnwrap(bounds.worldBounds(of: "box", in: placed))
        let desk = try XCTUnwrap(bounds.worldBounds(of: "desk", in: placed))
        XCTAssertEqual(box.min.y, 0, accuracy: 1e-6, "on the ground")
        XCTAssertFalse(RelationSolver.overlap(box, desk))
        // The desk faces +X, so seen from its front its left is +Z (a camera at +X looking back sees +Z on its left).
        XCTAssertGreaterThan(box.center.z, desk.max.z - 0.01)
        let front = try apply(solver.place(["box"], .inFrontOf, reference: "desk"), solver: solver)
        XCTAssertGreaterThan(try XCTUnwrap(bounds.worldBounds(of: "box", in: front)).min.x, desk.max.x)
    }

    func testGroupsAroundRowAndStack() throws {
        let (scene, manifest) = deskScene()
        let solver = RelationSolver(scene: scene, library: manifest)
        let ring = try solver.place(["lamp", "box"], .around(radius: 2), reference: "desk")
        XCTAssertEqual(ring.count, 2)
        for placement in ring {
            let horizontal = Vec3(placement.world.position.x - 2, 0, placement.world.position.z - 1).length
            XCTAssertEqual(horizontal, 2, accuracy: 0.6)
        }
        let stack = try apply(solver.place(["box", "lamp"], .stack, reference: "desk"), solver: solver)
        let bounds = SceneBounds(library: manifest)
        XCTAssertGreaterThan(try XCTUnwrap(bounds.worldBounds(of: "lamp", in: stack)).min.y,
                             try XCTUnwrap(bounds.worldBounds(of: "box", in: stack)).min.y)
        XCTAssertThrowsError(try solver.place(["lamp"], .on, reference: "nothing"))
        XCTAssertEqual(Relation(name: "beside_left"), .besideLeft)
        XCTAssertEqual(Relation(name: "around", radius: 3), .around(radius: 3))
        XCTAssertNil(Relation(name: "sideways"))
    }
}
