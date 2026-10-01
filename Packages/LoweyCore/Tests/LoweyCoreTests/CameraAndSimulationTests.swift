import Foundation
@testable import LoweyCore
import XCTest

/// Camera moves, lens maths and baked simulations.
final class CameraAndSimulationTests: XCTestCase {
    // MARK: Camera

    private func cameraDocument() -> (Document, ObjectID) {
        var document = makeDocument()
        var camera = SceneObject(id: "cam", name: "Camera", kind: .camera,
                                 transform: Transform(position: Vec3(0, 1, 10), rotation: .identity))
        camera[.fieldOfView] = .float(50)
        document.scene.objects["cam"] = camera
        document.scene.roots.append("cam")
        return (document, "cam")
    }

    func testEveryCameraMoveKeysTheCameraAndReverts() throws {
        let (document, cam) = cameraDocument()
        var ids = IDFactory.sequential("cm")
        for move in CameraMove.allCases {
            let command = try XCTUnwrap(CameraMoves.apply(move, camera: cam, subject: Vec3(0, 1, 0), at: 0.5,
                                                          options: CameraMoveOptions(duration: move.defaultDuration),
                                                          current: document.scene, timeline: document.scene.timeline, ids: &ids))
            let applied = try assertReverts(command, on: document)
            XCTAssertFalse(applied.scene.timeline.tracks.isEmpty, "\(move)")
            XCTAssertFalse(move.title.isEmpty)
            let start = Animator.evaluate(applied, at: 0.5).scene.objects[cam]!
            let original = document.scene.objects[cam]!
            if move != .reveal {
                XCTAssertTrue(start.transform.position.isApproximately(original.transform.position, tolerance: 1e-6), "\(move) starts in place")
            }
            let end = Animator.evaluate(applied, at: 0.5 + move.defaultDuration).scene.objects[cam]!
            switch move {
            case .pushIn:
                XCTAssertLessThan(end.transform.position.distance(to: Vec3(0, 1, 0)), 9.99)
            case .pullOut:
                XCTAssertGreaterThan(end.transform.position.distance(to: Vec3(0, 1, 0)), 10.01)
            case .punchIn:
                XCTAssertLessThan(end[.fieldOfView]?.floatValue ?? 50, 50)
            case .snapZoom:
                // Rushes most of the way in, and ends looking exactly where it looked (the jolt settles).
                XCTAssertLessThan(end.transform.position.distance(to: Vec3(0, 1, 0)), 5)
                XCTAssertTrue(end.transform.rotation.isApproximately(original.transform.rotation, tolerance: 1e-6))
                let early = Animator.evaluate(applied, at: 0.5 + move.defaultDuration * 0.3).scene.objects[cam]!
                XCTAssertLessThan(early.transform.position.distance(to: Vec3(0, 1, 0)), end.transform.position.distance(to: Vec3(0, 1, 0)),
                                  "overshoots before it settles")
            case .truck:
                XCTAssertEqual(end.transform.position.x, 2, accuracy: 1e-9)
            case .crane:
                XCTAssertEqual(end.transform.position.y, 3, accuracy: 1e-9)
            case .orbit:
                XCTAssertEqual(end.transform.position.distance(to: Vec3(0, 1, 0)), 10, accuracy: 1e-6, "orbits keep their distance")
                let view = end.transform.rotation.act(Vec3(0, 0, -1))
                XCTAssertTrue(view.isApproximately((Vec3(0, 1, 0) - end.transform.position).normalized, tolerance: 1e-6), "and keep looking")
            case .whipPan:
                XCTAssertFalse(end.transform.rotation.isApproximately(original.transform.rotation, tolerance: 1e-3))
            case .shake:
                XCTAssertTrue(end.transform.rotation.isApproximately(original.transform.rotation, tolerance: 1e-9), "settles")
            case .dolly:
                XCTAssertEqual(end.transform.position.z, 8, accuracy: 1e-9)
            case .reveal:
                XCTAssertLessThan(start.transform.position.y, original.transform.position.y)
                XCTAssertTrue(end.transform.position.isApproximately(original.transform.position, tolerance: 1e-9))
            }
        }
        XCTAssertNil(CameraMoves.apply(.pushIn, camera: "none", subject: .zero, at: 0, options: CameraMoveOptions(duration: 1),
                                       current: document.scene, timeline: document.scene.timeline, ids: &ids))
        let pull = try XCTUnwrap(CameraMoves.focusPull(camera: cam, to: 2, at: 1, duration: 1, current: document.scene,
                                                       timeline: document.scene.timeline, ids: &ids))
        let pulled = try assertReverts(pull, on: document)
        XCTAssertEqual(Animator.evaluate(pulled, at: 2).scene.objects[cam]?[.focusDistance], .float(2))
    }

    func testLensMath() {
        var lens = CameraLens(fieldOfView: 50)
        XCTAssertEqual(CameraLens.fieldOfView(focalLength: lens.focalLength), 50, accuracy: 1e-9)
        XCTAssertEqual(lens.framing(aspect: 16.0 / 9.0).fieldOfView, 50)
        XCTAssertEqual(lens.framing(aspect: 16.0 / 9.0).yaw, 0)
        lens.portraitZoom = 1.2
        lens.portraitShift = 0.5
        let portrait = lens.framing(aspect: 9.0 / 16.0)
        XCTAssertEqual(portrait.fieldOfView, 60, accuracy: 1e-9)
        XCTAssertLessThan(portrait.yaw, 0, "pan right = turn right (negative yaw)")
        let (document, cam) = cameraDocument()
        XCTAssertEqual(CameraLens(document.scene.objects[cam]!).fieldOfView, 50)
    }

    // MARK: Simulations

    func testPhysicsFallsAndSettlesOnTheGround() throws {
        var document = makeDocument()
        document.scene.objects["c"]?.transform.position = Vec3(-2, 3, 1)
        var ids = IDFactory.sequential("sim")
        let bounds = SceneBounds()
        let command = try XCTUnwrap(Simulation.physics(["c"], settings: PhysicsSettings(kind: .fall, duration: 3), at: 0, fps: 30,
                                                       bounds: bounds, current: document.scene, timeline: document.scene.timeline, ids: &ids))
        let applied = try assertReverts(command, on: document)
        let late = Animator.evaluate(applied, at: 3).scene
        XCTAssertEqual(late.objects["c"]!.transform.position.y, 0, accuracy: 0.02, "rests on the ground (pivot at the base)")
        let early = Animator.evaluate(applied, at: 0.3).scene
        XCTAssertLessThan(early.objects["c"]!.transform.position.y, 3)
        // Deterministic.
        var ids2 = IDFactory.sequential("sim")
        let again = try XCTUnwrap(Simulation.physics(["c"], settings: PhysicsSettings(kind: .fall, duration: 3), at: 0, fps: 30,
                                                     bounds: bounds, current: document.scene, timeline: document.scene.timeline, ids: &ids2))
        XCTAssertEqual(command, again)
    }

    func testExplosionScattersObjects() throws {
        var document = makeDocument()
        document.scene.objects["b"]?.parent = nil
        document.scene.objects["a"]?.children = []
        document.scene.roots.append("b")
        var ids = IDFactory.sequential("sim")
        let command = try XCTUnwrap(Simulation.physics(["a", "b", "c"], settings: PhysicsSettings(kind: .explode, duration: 2, center: Vec3(0, 0, 0)),
                                                       at: 1, fps: 30, bounds: SceneBounds(), current: document.scene,
                                                       timeline: document.scene.timeline, ids: &ids))
        let applied = try assertReverts(command, on: document)
        let before = Animator.evaluate(applied, at: 1).scene
        let after = Animator.evaluate(applied, at: 1.5).scene
        for id in ["a", "c"] as [ObjectID] {
            let start = before.objects[id]!.transform.position
            let end = after.objects[id]!.transform.position
            XCTAssertGreaterThan(Vec3(end.x, 0, end.z).length, Vec3(start.x, 0, start.z).length, "\(id) flies outward")
        }
        XCTAssertNil(Simulation.physics(["zzz"], settings: PhysicsSettings(), at: 0, fps: 30, bounds: SceneBounds(), current: document.scene,
                                        timeline: document.scene.timeline, ids: &ids))
        var bodies = [Simulation.Body(id: "x", position: Vec3(0, 0.5, 0), velocity: .zero, rotation: .identity, spin: .zero, radius: 0.5,
                                      bottom: 0, parentWorld: .identity, scale: .one),
                      Simulation.Body(id: "y", position: Vec3(0.5, 0.5, 0), velocity: .zero, rotation: .identity, spin: .zero, radius: 0.5,
                                      bottom: 0, parentWorld: .identity, scale: .one)]
        Simulation.step(&bodies, dt: 0.01, settings: PhysicsSettings(gravity: 0))
        XCTAssertGreaterThanOrEqual(bodies[0].position.distance(to: bodies[1].position), 0.999, "overlapping bodies are pushed apart")
    }

    func testFlockAndCrowdBake() throws {
        var document = makeDocument()
        var birds: [ObjectID] = []
        for index in 0 ..< 8 {
            let id = ObjectID(raw: "bird-\(index)")
            document.scene.objects[id] = SceneObject(id: id, name: "Bird", kind: .primitive(.cone),
                                                     transform: Transform(position: Vec3(Double(index) * 0.5, 6, 0)))
            document.scene.roots.append(id)
            birds.append(id)
        }
        var ids = IDFactory.sequential("flock")
        let settings = Simulation.FlockSettings(duration: 3)
        let flock = try XCTUnwrap(Simulation.flock(birds, settings: settings, at: 0, fps: 30, current: document.scene,
                                                   timeline: document.scene.timeline, ids: &ids))
        let flying = try assertReverts(flock, on: document)
        let end = Animator.evaluate(flying, at: 3).scene
        for bird in birds {
            let p = end.objects[bird]!.transform.position
            XCTAssertLessThan(abs(p.x - settings.center.x), settings.extent.x + 6, "stays around the area")
            XCTAssertNotEqual(p, document.scene.objects[bird]!.transform.position, "moved")
        }
        XCTAssertNil(Simulation.flock(["none"], settings: settings, at: 0, fps: 30, current: document.scene, timeline: document.scene.timeline,
                                      ids: &ids))

        let seats = birds.indices.map { Vec3(Double($0) * 1.5, 0, -5) }
        let crowd = try XCTUnwrap(Simulation.crowdWalk(birds, to: seats, at: 0, fps: 30, current: document.scene,
                                                       timeline: document.scene.timeline, ids: &ids))
        let walked = try assertReverts(crowd, on: document)
        let arrived = Animator.evaluate(walked, at: 60).scene
        for (index, bird) in birds.enumerated() {
            let p = arrived.objects[bird]!.transform.position
            XCTAssertLessThan(Vec3(p.x - seats[index].x, 0, p.z - seats[index].z).length, 0.35, "everyone reaches their seat")
        }
    }
}
