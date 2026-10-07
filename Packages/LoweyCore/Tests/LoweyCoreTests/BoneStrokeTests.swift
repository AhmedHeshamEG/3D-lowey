import Foundation
@testable import LoweyCore
import XCTest

/// Draw a bone, redone (M8): the chain runs through the middle of the part the stroke is on, at one depth; joints land
/// where the stroke bends; drawing along a chain again replaces it.
final class BoneStrokeTests: XCTestCase {
    /// Rays straight down from above, one per Pencil sample, along x.
    private func strokeFromAbove(from start: Double, to end: Double, z: Double = 0) -> [Ray] {
        stride(from: start, through: end, by: 0.02).map { Ray(origin: Vec3($0, 3, z), direction: Vec3(0, -1, 0)) }
    }

    private func positions(_ mesh: MeshData) -> [Vec3] {
        mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
    }

    // MARK: Depth from the mesh

    func testCrossingsAreTheStretchesInsideTheObject() {
        typealias Crossing = CrossingPath.Crossing
        XCTAssertEqual(CrossingPath.crossings([(1, true), (1.2, false), (2, true), (3, false)]), [Crossing(entry: 1, exit: 1.2), Crossing(entry: 2, exit: 3)])
        XCTAssertEqual(CrossingPath.crossings([(1, true), (1.4, true), (1.6, false), (2, false)]), [Crossing(entry: 1, exit: 2)],
                       "a piece pushed into another is one stretch")
        XCTAssertEqual(CrossingPath.crossings([(1, true), (1, true), (2, false)]), [Crossing(entry: 1, exit: 2)], "a shared edge counts once")
        XCTAssertEqual(CrossingPath.crossings([(1, false), (2, true)]), [Crossing(entry: 1, exit: 2)], "inside-out faces pair up in order")
        XCTAssertEqual(CrossingPath.crossings([(1, true)]), [Crossing(entry: 1, exit: 1)], "an open shell keeps its entry")
        XCTAssertTrue(CrossingPath.crossings([]).isEmpty)
    }

    func testTheStrokeStaysInThePartInFront() {
        // An arm held over a body: every ray goes through the arm, then through the body behind it.
        var mesh = RigSamples.box(centre: Vec3(1, 0, 0), size: Vec3(2.4, 0.8, 0.8), steps: 4)
        mesh.append(RigSamples.tube(from: 0.2, to: 1.8, height: 1, radius: (0.08, 0.08), rings: 24, sides: 12))
        let samples = BoneStroke.centreline(rays: strokeFromAbove(from: 0.3, to: 1.7), surface: TriangleBVH(mesh))
        XCTAssertEqual(samples.count, 71)
        for sample in samples {
            XCTAssertEqual(sample.point.y, 1, accuracy: 0.01, "in the middle of the arm, not in the body behind it")
            XCTAssertEqual(sample.thickness, 0.16, accuracy: 0.02)
        }
    }

    func testAStrokeThatStartsOnTheBodyStaysAtOneDepth() {
        // The same arm, but the stroke starts on the body before the arm begins: it stays in the body under the arm.
        var mesh = RigSamples.box(centre: Vec3(1, 0, 0), size: Vec3(2.4, 0.8, 0.8), steps: 4)
        mesh.append(RigSamples.tube(from: 0.8, to: 1.8, height: 1, radius: (0.08, 0.08), rings: 24, sides: 12))
        let samples = BoneStroke.centreline(rays: strokeFromAbove(from: 0.1, to: 1.7), surface: TriangleBVH(mesh))
        for (a, b) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThan(abs(a.point.y - b.point.y), 0.05, "no jump in depth along the stroke")
        }
    }

    func testTheChainKeepsItsDepthWhereThePartRunsIntoTheBody() {
        // The creature's tail is pushed into its body. A stroke that starts on the body used to rise to the body's
        // skin and dive to its middle; it runs straight in at the tail's own depth.
        let mesh = RigSamples.creature()
        let samples = BoneStroke.centreline(rays: strokeFromAbove(from: 0.1, to: 1.55), surface: TriangleBVH(mesh))
        XCTAssertEqual(samples.count, 73)
        for sample in samples {
            XCTAssertEqual(sample.point.y, RigSamples.tailHeight, accuracy: 0.02, "at the tail's depth at x = \(sample.point.x)")
            XCTAssertLessThan(sample.thickness, 0.4, "never as thick as the body")
        }
    }

    // MARK: Joints at the bends

    private func elbow() -> [Vec3] {
        stride(from: 0.0, through: 1.0, by: 0.02).map { Vec3($0, 0, 0) } + stride(from: 0.02, through: 1.0, by: 0.02).map { Vec3(1, $0, 0) }
    }

    func testJointsLandWhereTheStrokeBends() {
        let path = BoneStroke.smoothed(elbow())
        let joints = BoneStroke.joints(along: path, thickness: 0.2)
        XCTAssertEqual(joints.first?.distance(to: Vec3(0, 0, 0)) ?? 1, 0, accuracy: 1e-9)
        XCTAssertEqual(joints.last?.distance(to: Vec3(1, 1, 0)) ?? 1, 0, accuracy: 1e-9)
        let nearest = joints.map { $0.distance(to: Vec3(1, 0, 0)) }.min() ?? 1
        XCTAssertLessThan(nearest, 0.04, "a joint at the elbow")
        XCTAssertGreaterThanOrEqual(joints.count, 5)
        XCTAssertLessThanOrEqual(joints.count, 9)
        // Evenly spaced along each arm of the elbow.
        let corner = joints.firstIndex { $0.distance(to: Vec3(1, 0, 0)) < 0.04 } ?? 0
        let steps = zip(joints[...corner], joints[...corner].dropFirst()).map { $0.distance(to: $1) }
        XCTAssertEqual(steps.max() ?? 0, steps.min() ?? 1, accuracy: 0.02)
    }

    func testAStraightStrokeIsCutEvenlyAsBefore() {
        let path = stride(from: 0.0, through: 1.0, by: 0.02).enumerated().map { Vec3($1, 0, 0.008 * sin(Double($0) * 0.7)) }
        let joints = BoneStroke.joints(along: path, thickness: 0.1)
        XCTAssertEqual(joints.count, 8, "seven bones about 1.4 thicknesses long")
        XCTAssertEqual(joints, BoneStroke.resample(path, count: 8), "a wobbly hand isn't a bend")
        XCTAssertEqual(BoneStroke.bends(path, tolerance: 0.05), [0, path.count - 1])
    }

    func testThePreviewShowsTheJointsTheStrokeWillMake() throws {
        let samples = elbow().map { BoneStroke.Sample(point: $0, thickness: 0.2) }
        let preview = BoneStroke.preview(samples)
        let rig = try BoneStroke.addingChain(samples, to: nil, surface: elbow())
        XCTAssertEqual(preview.count, rig.skeleton.joints.count)
        for point in preview {
            XCTAssertLessThan(rig.restPositions.map { $0.distance(to: point) }.min() ?? 1, 1e-9)
        }
        XCTAssertTrue(BoneStroke.preview([samples[0]]).isEmpty, "one sample isn't a bone yet")
    }

    // MARK: Drawing it again

    func testDrawingAlongAChainAgainReplacesIt() throws {
        let mesh = RigSamples.creature()
        let bvh = TriangleBVH(mesh)
        let surface = positions(mesh)
        let tail = BoneStroke.centreline(rays: strokeFromAbove(from: 0.44, to: 1.55), surface: bvh)
        let first = try BoneStroke.addingChain(tail, to: nil, surface: surface)
        let chain = Array(first.restPositions.dropFirst())
        // A fin standing on the tail's third joint. Its first joint sits on the tail's own bone, so it goes with the
        // tail; the three above it are the fin.
        let fin = [BoneStroke.Sample(point: chain[2], thickness: 0.1), BoneStroke.Sample(point: chain[2] + Vec3(0, 0.4, 0), thickness: 0.1)]
        let finned = try BoneStroke.addingChain(fin, to: first, surface: surface)
        let finNames = Array(finned.skeleton.names.suffix(3))
        XCTAssertEqual(finned.skeleton.joints.count, first.skeleton.joints.count + 4)

        // The tail again, a little shorter and off to one side.
        let again = BoneStroke.centreline(rays: strokeFromAbove(from: 0.5, to: 1.5, z: 0.015), surface: bvh)
        let redrawn = try BoneStroke.addingChain(again, to: finned, surface: surface)
        XCTAssertEqual(redrawn.skeleton.joints[0].name, "root")
        XCTAssertEqual(redrawn.restPositions[0], first.restPositions[0], "the root stays where it was")
        let old = Set(chain.map { $0.x })
        let tailNow = redrawn.skeleton.joints.indices.filter { index in
            redrawn.skeleton.joints[index].name != "root" && !finNames.contains(redrawn.skeleton.joints[index].name)
        }
        XCTAssertEqual(tailNow.count, BoneStroke.preview(again).count, "one tail, not two on top of each other")
        XCTAssertTrue(tailNow.allSatisfy { !old.contains(redrawn.restPositions[$0].x) }, "the old chain is gone")
        XCTAssertEqual(redrawn.restPositions[tailNow[0]].z, 0.015, accuracy: 0.005, "the new one is where it was drawn")
        // The fin kept its joints, their names and places, and hangs from the new tail.
        for name in finNames {
            let before = try XCTUnwrap(finned.skeleton.index(of: name))
            let after = try XCTUnwrap(redrawn.skeleton.index(of: name))
            XCTAssertLessThan(redrawn.restPositions[after].distance(to: finned.restPositions[before]), 1e-9)
        }
        let finBase = try XCTUnwrap(redrawn.skeleton.index(of: finNames[0]))
        let hangsFrom = try XCTUnwrap(redrawn.skeleton.joints[finBase].parent)
        XCTAssertTrue(tailNow.contains(hangsFrom), "the fin hangs from the new tail")
        XCTAssertLessThan(redrawn.restPositions[hangsFrom].distance(to: redrawn.restPositions[finBase]), 0.2)
        for index in redrawn.skeleton.joints.indices {
            if let parent = redrawn.skeleton.joints[index].parent { XCTAssertLessThan(parent, index, "parents first") }
        }
        XCTAssertNil(redrawn.skin, "the weights are worked out again")
    }

    func testAStrokeSomewhereNewAddsAChain() throws {
        let mesh = RigSamples.creature()
        let surface = positions(mesh)
        let tail = BoneStroke.centreline(rays: strokeFromAbove(from: 0.44, to: 1.55), surface: TriangleBVH(mesh))
        let first = try BoneStroke.addingChain(tail, to: nil, surface: surface)
        let chain = Array(first.restPositions.dropFirst())
        // Across the tail, not along it: nothing is redrawn.
        let across = [-0.3, 0.3].map { BoneStroke.Sample(point: chain[3] + Vec3(0, 0, $0), thickness: 0.1) }
        XCTAssertTrue(BoneStroke.redrawn(by: across.map(\.point), in: first, reach: 0.075).isEmpty)
        let more = try BoneStroke.addingChain(across, to: first, surface: surface)
        XCTAssertGreaterThan(more.skeleton.joints.count, first.skeleton.joints.count)
        XCTAssertEqual(Array(more.restPositions.prefix(first.skeleton.joints.count)), first.restPositions, "what was there stays")
        // A person's skeleton is never taken for a redrawn chain.
        var person = first
        person.standard = .humanoid
        XCTAssertEqual(try BoneStroke.addingChain(tail, to: person, surface: surface).skeleton.joints.count, first.skeleton.joints.count * 2 - 1)
    }
}
