import Foundation
@testable import LoweyCore
import XCTest

final class EngineGeometryTests: XCTestCase {
    // MARK: Bevel

    func testRoundedBoxKeepsSizeAndPivot() throws {
        let mesh = try XCTUnwrap(BevelMesh.make(.cube, size: SIMD3<Float>(2, 1, 0.5), bevel: BevelSpec(radius: 0.05, segments: 3)))
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-5, "pivot at the base")
        XCTAssertEqual(bounds.size.x, 2, accuracy: 1e-4)
        XCTAssertEqual(bounds.size.y, 1, accuracy: 1e-4)
        XCTAssertEqual(bounds.size.z, 0.5, accuracy: 1e-4)
        let center = SIMD3<Float>(0, 0.5, 0)
        for (position, normal) in zip(mesh.positions, mesh.normals) {
            XCTAssertEqual(length3(normal), 1, accuracy: 1e-4)
            XCTAssertGreaterThan(dot3(normal, position - center), 0, "normals point outward")
        }
        for tri in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[tri])]
            let b = mesh.positions[Int(mesh.indices[tri + 1])]
            let c = mesh.positions[Int(mesh.indices[tri + 2])]
            let face = cross3(b - a, c - a)
            guard length3(face) > 1e-9 else { continue }
            XCTAssertGreaterThan(dot3(face, (a + b + c) / 3 - center), -1e-6, "counter-clockwise faces point outward")
        }
    }

    func testBevelledCylinderAndCone() throws {
        for shape in [PrimitiveShape.cylinder, .cone] {
            let mesh = try XCTUnwrap(BevelMesh.make(shape, size: SIMD3<Float>(1, 2, 1), bevel: .standard))
            let bounds = try XCTUnwrap(mesh.bounds)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-4, "\(shape)")
            XCTAssertEqual(bounds.max.y, 2, accuracy: 1e-3, "\(shape)")
            XCTAssertEqual(bounds.size.x, 1, accuracy: 0.01, "\(shape)")
            XCTAssertFalse(mesh.isEmpty)
        }
        XCTAssertNil(BevelMesh.make(.sphere, size: SIMD3<Float>(1, 1, 1), bevel: .standard))
        XCTAssertNil(BevelMesh.make(.cube, size: SIMD3<Float>(1, 1, 1), bevel: BevelSpec(radius: 0)))
    }

    func testBevelSpecFromObject() {
        var cube = SceneObject(id: "c", name: "Cube", kind: .primitive(.cube))
        XCTAssertNil(BevelSpec(cube), "1.x objects stay sharp")
        cube[.bevel] = .float(0.04)
        cube[.bevelSegments] = .int(9)
        XCTAssertEqual(BevelSpec(cube), BevelSpec(radius: 0.04, segments: 6))
    }

    // MARK: Shadow Brush

    func testShadowPaintFalloffAndMerging() {
        let dab = ShadowDab(position: Vec3(0, 1, 0), radius: 0.5, amount: -0.8)
        XCTAssertEqual(ShadowPaint.bias(at: SIMD3<Float>(0, 1, 0), dabs: [dab]), -0.8, accuracy: 1e-5)
        XCTAssertEqual(ShadowPaint.bias(at: SIMD3<Float>(0, 2, 0), dabs: [dab]), 0)
        let halfway = ShadowPaint.bias(at: SIMD3<Float>(0.25, 1, 0), dabs: [dab])
        XCTAssertTrue(halfway < 0 && halfway > -0.8)
        let merged = ShadowPaint.adding(ShadowDab(position: Vec3(0.01, 1, 0), radius: 0.5, amount: -0.8), to: [dab])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].amount, -1, accuracy: 1e-9)
        let apart = ShadowPaint.adding(ShadowDab(position: Vec3(1, 1, 0), radius: 0.5, amount: 0.5), to: [dab])
        XCTAssertEqual(apart.count, 2)
        let mesh = PrimitiveMesh.make(.cube)
        XCTAssertEqual(ShadowPaint.biases(for: mesh, dabs: [dab]).count, mesh.positions.count)
        XCTAssertTrue(ShadowPaint.biases(for: mesh, dabs: []).isEmpty)
    }

    func testNewCommandsRevert() throws {
        let document = makeDocument()
        try assertReverts(.setShadowPaint("a", [ShadowDab(position: Vec3(0, 1, 0), radius: 0.3, amount: -0.5)]), on: document)
        try assertReverts(.setCustomLooks([LookPreset.ink.duplicated(id: "m", name: "My Ink")]), on: document)
        var working = document
        XCTAssertThrowsError(try EditCommand.setShadowPaint("missing", []).apply(to: &working))
        XCTAssertEqual(EditCommand.setShadowPaint("a", []).label, "Paint shadows")
        XCTAssertEqual(EditCommand.setCustomLooks([]).label, "Edit looks")
    }

    // MARK: Frame shot

    private let person = ShotSubject(bounds: Bounds(min: Vec3(-0.25, 0, -0.2), max: Vec3(0.25, 1.8, 0.2)), front: Vec3(0, 0, 1),
                                     isCharacter: true)

    /// Where a world point lands in the frame (−1…1, y up) for a solution, and its depth.
    private func project(_ point: Vec3, _ shot: ShotSolution, aspect: Double = 16.0 / 9.0) -> (x: Double, y: Double, z: Double) {
        let local = shot.rotation.inverse.act(point - shot.position)
        let f = 1 / tan(shot.fieldOfView * .pi / 360)
        return (local.x * f / aspect / -local.z, local.y * f / -local.z, -local.z)
    }

    func testCloseUpIsCloserAndTighterThanWide() {
        let wide = FrameShot.solve(person, type: .wide, composition: .center)
        let close = FrameShot.solve(person, type: .closeUp, composition: .center)
        XCTAssertLessThan((close.position - person.bounds.center).length, (wide.position - person.bounds.center).length)
        XCTAssertGreaterThan(close.focalLength, wide.focalLength)
        XCTAssertLessThan(abs(project(Vec3(0, 1.7, 0), close).y), 1, "the head is in the close-up")
        XCTAssertGreaterThan(abs(project(Vec3(0, 0.05, 0), close).y), 1, "the feet are not")
    }

    func testFullShotShowsTheWholeSubject() {
        let shot = FrameShot.solve(person, type: .full, composition: .center)
        for corner in person.bounds.corners {
            let point = project(corner, shot)
            XCTAssertLessThan(abs(point.x), 1.02)
            XCTAssertLessThan(abs(point.y), 1.02)
            XCTAssertGreaterThan(point.z, 0, "in front of the camera")
        }
    }

    func testThirdsPutTheSubjectOffCentre() {
        let right = FrameShot.solve(person, type: .medium, composition: .rightThird)
        let left = FrameShot.solve(person, type: .medium, composition: .leftThird)
        let aimRight = right.position + right.rotation.act(Vec3(0, 0, -right.focusDistance))
        XCTAssertGreaterThan(project(Vec3(0, aimRight.y, 0), right).x, 0.2)
        XCTAssertLessThan(project(Vec3(0, aimRight.y, 0), left).x, -0.2)
    }

    func testAnglesAndFront() {
        let low = FrameShot.solve(person, type: .full, composition: .lowAngle)
        let high = FrameShot.solve(person, type: .full, composition: .highAngle)
        XCTAssertLessThan(low.position.y, high.position.y)
        let facingBack = ShotSubject(bounds: person.bounds, front: Vec3(0, 0, -1), isCharacter: true)
        XCTAssertLessThan(FrameShot.solve(facingBack, type: .full, composition: .center).position.z, 0, "the camera goes in front")
    }

    func testTwoShotAndOverTheShoulder() {
        let partner = ShotSubject(bounds: Bounds(min: Vec3(1.25, 0, -0.2), max: Vec3(1.75, 1.8, 0.2)), front: Vec3(-1, 0, 0),
                                  isCharacter: true)
        let two = FrameShot.solve(person, type: .twoShot, composition: .center, other: partner)
        for center in [person.bounds.center, partner.bounds.center] {
            XCTAssertLessThan(abs(project(center, two).x), 1)
        }
        let ots = FrameShot.solve(person, type: .overTheShoulder, composition: .center, other: partner)
        XCTAssertGreaterThan(ots.position.x, partner.bounds.center.x, "behind the other subject")
        XCTAssertEqual(ShotType.allCases.count, 9)
        XCTAssertEqual(Composition.allCases.count, 5)
    }
}
