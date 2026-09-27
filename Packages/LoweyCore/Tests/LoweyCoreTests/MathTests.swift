import Foundation
@testable import LoweyCore
import XCTest

final class MathTests: XCTestCase {
    func testVectorBasics() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, 5, 6)
        XCTAssertEqual(a + b, Vec3(5, 7, 9))
        XCTAssertEqual(b - a, Vec3(3, 3, 3))
        XCTAssertEqual(a * 2, Vec3(2, 4, 6))
        XCTAssertEqual(2 * a, Vec3(2, 4, 6))
        XCTAssertEqual(a / 2, Vec3(0.5, 1, 1.5))
        XCTAssertEqual(-a, Vec3(-1, -2, -3))
        XCTAssertEqual(a.dot(b), 32)
        XCTAssertEqual(Vec3.unitX.cross(.unitY), .unitZ)
        XCTAssertEqual(Vec3(3, 4, 0).length, 5)
        XCTAssertEqual(Vec3(3, 4, 0).lengthSquared, 25)
        XCTAssertTrue(Vec3(0, 0, 9).normalized.isApproximately(.unitZ))
        XCTAssertEqual(Vec3.zero.normalized, .zero)
        XCTAssertEqual(a.lerp(to: b, 0.5), Vec3(2.5, 3.5, 4.5))
        XCTAssertEqual(a.scaled(by: b), Vec3(4, 10, 18))
        XCTAssertEqual(Vec3.min(a, Vec3(0, 5, 1)), Vec3(0, 2, 1))
        XCTAssertEqual(Vec3.max(a, Vec3(0, 5, 1)), Vec3(1, 5, 3))
        XCTAssertEqual(a.maxComponent, 3)
        XCTAssertEqual(a.minComponent, 1)
        XCTAssertEqual(a.distance(to: Vec3(1, 2, 4)), 1)
        var c = a
        c[.y] = 9
        XCTAssertEqual(c[.y], 9)
        c += Vec3(1, 1, 1)
        c -= Vec3(1, 1, 1)
        c *= 2
        XCTAssertEqual(c, Vec3(2, 18, 6))
        XCTAssertEqual(a.map { $0 * 10 }, Vec3(10, 20, 30))
        XCTAssertEqual(Axis.z.unit, .unitZ)
        XCTAssertEqual(a.description, "(1.0, 2.0, 3.0)")
        XCTAssertEqual(Vec2(3, 4).length, 5)
        XCTAssertEqual(Vec2(1, 0).cross(Vec2(0, 1)), 1)
    }

    func testVectorCodableIsCompactArray() throws {
        let data = try JSONEncoder().encode(Vec3(1, 2.5, -3))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[1,2.5,-3]")
        XCTAssertEqual(try JSONDecoder().decode(Vec3.self, from: data), Vec3(1, 2.5, -3))
    }

    func testQuaternionRotation() {
        let q = Quat(angle: .pi / 2, axis: .unitY)
        XCTAssertTrue(q.act(.unitX).isApproximately(Vec3(0, 0, -1)))
        XCTAssertTrue((q * q.inverse).isApproximately(.identity))
        XCTAssertTrue(q.conjugate.act(q.act(Vec3(1, 2, 3))).isApproximately(Vec3(1, 2, 3)))
        XCTAssertEqual(Quat.identity.act(Vec3(1, 2, 3)), Vec3(1, 2, 3))
        XCTAssertTrue(Quat(x: 0, y: 0, z: 0, w: 0).normalized.isApproximately(.identity))
    }

    func testEulerRoundTrip() {
        for euler in [Vec3(10, 20, 30), Vec3(-45, 170, 5), Vec3(0, -90, 0), Vec3(89, 0, 0), Vec3(0, 0, 0)] {
            let q = Quat(eulerDegrees: euler)
            let back = Quat(eulerDegrees: q.eulerDegrees)
            XCTAssertTrue(q.isApproximately(back, tolerance: 1e-6), "\(euler) → \(q.eulerDegrees)")
        }
        // Gimbal lock still produces an equivalent rotation.
        let locked = Quat(eulerDegrees: Vec3(90, 30, 0))
        XCTAssertTrue(locked.isApproximately(Quat(eulerDegrees: locked.eulerDegrees), tolerance: 1e-6))
    }

    func testSlerp() {
        let a = Quat.identity
        let b = Quat(angle: .pi / 2, axis: .unitY)
        let half = a.slerp(to: b, 0.5)
        XCTAssertTrue(half.isApproximately(Quat(angle: .pi / 4, axis: .unitY)))
        XCTAssertTrue(a.slerp(to: b, 0).isApproximately(a))
        XCTAssertTrue(a.slerp(to: b, 1).isApproximately(b))
        // Shortest path when quaternions are in opposite hemispheres.
        let negB = Quat(x: -b.x, y: -b.y, z: -b.z, w: -b.w)
        XCTAssertTrue(a.slerp(to: negB, 0.5).isApproximately(half))
        // Nearly identical → linear path.
        let tiny = Quat(angle: 0.0001, axis: .unitX)
        XCTAssertTrue(a.slerp(to: tiny, 0.5).isApproximately(Quat(angle: 0.00005, axis: .unitX)))
    }

    func testRotationBetweenVectors() {
        XCTAssertTrue(Quat.rotation(from: .unitX, to: .unitY).act(.unitX).isApproximately(.unitY))
        XCTAssertTrue(Quat.rotation(from: .unitX, to: .unitX).isApproximately(.identity))
        XCTAssertTrue(Quat.rotation(from: .unitX, to: -Vec3.unitX).act(.unitX).isApproximately(-Vec3.unitX))
        XCTAssertTrue(Quat.rotation(from: .unitY, to: -Vec3.unitY).act(.unitY).isApproximately(-Vec3.unitY))
    }

    func testTransformComposeAndRelative() {
        let parent = Transform(position: Vec3(1, 0, 0), rotation: Quat(angle: .pi / 2, axis: .unitY), scale: Vec3(2, 2, 2))
        let child = Transform(position: Vec3(1, 0, 0), rotation: Quat(angle: 0.3, axis: .unitX), scale: Vec3(0.5, 0.5, 0.5))
        let world = parent * child
        XCTAssertTrue(world.position.isApproximately(Vec3(1, 0, -2)))
        let back = Transform.relative(world: world, toParent: parent)
        XCTAssertTrue(back.isApproximately(child))
        XCTAssertTrue(parent.inverseApply(to: parent.apply(to: Vec3(3, 4, 5))).isApproximately(Vec3(3, 4, 5)))
        XCTAssertTrue(parent.applyDirection(.unitX).isApproximately(Vec3(0, 0, -2)))
        XCTAssertEqual(Transform.identity.apply(to: Vec3(1, 2, 3)), Vec3(1, 2, 3))
    }

    func testBounds() throws {
        let bounds = try XCTUnwrap(Bounds(points: [Vec3(0, 0, 0), Vec3(2, 4, -2)]))
        XCTAssertEqual(bounds.min, Vec3(0, 0, -2))
        XCTAssertEqual(bounds.max, Vec3(2, 4, 0))
        XCTAssertEqual(bounds.center, Vec3(1, 2, -1))
        XCTAssertEqual(bounds.size, Vec3(2, 4, 2))
        XCTAssertEqual(bounds.extents, Vec3(1, 2, 1))
        XCTAssertEqual(bounds.corners.count, 8)
        XCTAssertTrue(bounds.contains(Vec3(1, 1, -1)))
        XCTAssertFalse(bounds.contains(Vec3(3, 1, -1)))
        XCTAssertTrue(bounds.intersects(Bounds(min: Vec3(1, 1, -1), max: Vec3(5, 5, 5))))
        XCTAssertFalse(bounds.intersects(Bounds(min: Vec3(3, 3, 3), max: Vec3(5, 5, 5))))
        let moved = bounds.transformed(by: Transform(position: Vec3(10, 0, 0)))
        XCTAssertEqual(moved.min.x, 10)
        XCTAssertEqual(bounds.union(moved).max.x, 12)
        XCTAssertNil(Bounds(points: [Vec3]()))
    }

    func testRay() {
        let ray = Ray(origin: .zero, direction: Vec3(0, 0, 5))
        XCTAssertEqual(ray.direction, .unitZ)
        XCTAssertEqual(ray.point(at: 2), Vec3(0, 0, 2))
    }

    func testColorHex() throws {
        let color = try XCTUnwrap(RGBA(hex: "#FF8000"))
        XCTAssertEqual(color.r, 1)
        XCTAssertEqual(color.g, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(color.hex, "#FF8000")
        XCTAssertEqual(RGBA(hex: "11223344")?.hex, "#11223344")
        XCTAssertNil(RGBA(hex: "#12"))
        XCTAssertNil(RGBA(hex: "zzzzzz"))
        XCTAssertEqual(RGBA.black.lerp(to: .white, 0.5).r, 0.5, accuracy: 1.0 / 255)
        XCTAssertEqual(RGBA.white.luminance, 1, accuracy: 1e-9)
        XCTAssertEqual(RGBA.white.scaled(0.5).g, 0.5, accuracy: 1.0 / 255)
    }

    func testColorValueCodableAndPalette() throws {
        let palette = Palette.starter
        let literal = ColorValue.rgba(RGBA(1, 0, 0))
        let bound = ColorValue.palette(2)
        XCTAssertEqual(try LoweyJSON.decode(ColorValue.self, from: LoweyJSON.encode(literal)), literal)
        XCTAssertEqual(try LoweyJSON.decode(ColorValue.self, from: LoweyJSON.encode(bound)), bound)
        XCTAssertEqual(try String(decoding: JSONEncoder().encode(bound), as: UTF8.self), "\"palette:2\"")
        XCTAssertEqual(bound.resolved(in: palette), palette.swatches[2].color)
        XCTAssertEqual(ColorValue.palette(99).resolved(in: palette), .blockout)
        XCTAssertEqual(bound.paletteSlot, 2)
        XCTAssertNil(literal.paletteSlot)
        XCTAssertThrowsError(try LoweyJSON.decode(ColorValue.self, from: Data("\"nope\"".utf8)))
        XCTAssertThrowsError(try LoweyJSON.decode(RGBA.self, from: Data("\"nope\"".utf8)))
    }

    func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0 ..< 100 {
            XCTAssertEqual(a.next(), b.next())
        }
        var c = SeededRandom(seed: 7)
        for _ in 0 ..< 1000 {
            let value = c.unit()
            XCTAssertTrue(value >= 0 && value < 1)
            let ranged = c.range(5, 6)
            XCTAssertTrue(ranged >= 5 && ranged < 6)
        }
    }
}
