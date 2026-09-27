import Foundation
@testable import LoweyCore
import XCTest

final class GeometryTests: XCTestCase {
    /// Every triangle's geometric normal must point away from the shape's center (closed, outward-facing).
    private func assertOutward(_ mesh: MeshData, center: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        var inward = 0
        for tri in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[tri])]
            let b = mesh.positions[Int(mesh.indices[tri + 1])]
            let c = mesh.positions[Int(mesh.indices[tri + 2])]
            let n = cross3(b - a, c - a)
            if length3(n) < 1e-9 { continue }
            let centroid = (a + b + c) / 3
            if dot3(n, centroid - center) < -1e-6 { inward += 1 }
        }
        XCTAssertEqual(inward, 0, "triangles facing inward", file: file, line: line)
    }

    func testPrimitivesAreLowPolyOutwardAndBaseAligned() throws {
        for shape in PrimitiveShape.allCases {
            let mesh = PrimitiveMesh.make(shape)
            XCTAssertFalse(mesh.isEmpty, "\(shape)")
            XCTAssertLessThan(mesh.triangleCount, 600, "\(shape) should be low-poly")
            let bounds = try XCTUnwrap(mesh.bounds)
            XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-5, "\(shape) sits on the ground")
            let expected = PrimitiveMesh.bounds(shape)
            XCTAssertTrue(bounds.max.isApproximately(expected.max, tolerance: 0.03), "\(shape) \(bounds.max) vs \(expected.max)")
            if shape != .plane, shape != .torus {
                assertOutward(mesh, center: SIMD3<Float>(0, Float(bounds.center.y), 0))
            }
            for style in ShadingStyle.allCases {
                let shaded = PrimitiveMesh.make(shape, shading: style)
                XCTAssertEqual(shaded.normals.count, shaded.positions.count)
                XCTAssertEqual(shaded.triangleCount, mesh.triangleCount)
            }
        }
    }

    func testFlatVersusAutoSmooth() {
        let cube = PrimitiveMesh.make(.cube)
        // Auto-smooth keeps a cube's edges hard: every normal is axis-aligned.
        for normal in cube.autoSmoothed().normals {
            let components = [abs(normal.x), abs(normal.y), abs(normal.z)].sorted()
            XCTAssertEqual(components[2], 1, accuracy: 1e-5)
        }
        // …but softens a sphere: normals differ from face normals.
        let sphere = PrimitiveMesh.make(.sphere)
        let smooth = sphere.autoSmoothed()
        let flat = sphere.faceted()
        XCTAssertEqual(smooth.positions.count, flat.positions.count)
        let differing = zip(smooth.normals, flat.normals).filter { length3($0 - $1) > 0.01 }.count
        XCTAssertGreaterThan(differing, flat.normals.count / 2)
        // Faceted triangles have three identical normals.
        for tri in stride(from: 0, to: flat.normals.count, by: 3) {
            XCTAssertEqual(flat.normals[tri], flat.normals[tri + 1])
        }
        // Welding merges seams.
        XCTAssertLessThan(sphere.welded().positions.count, sphere.positions.count)
        var smoothed = sphere.smoothed()
        smoothed.computeSmoothNormals()
        XCTAssertEqual(smoothed.normals.count, smoothed.positions.count)
    }

    func testMeshAppendMirrorTransform() throws {
        var mesh = PrimitiveMesh.box(size: SIMD3<Float>(1, 1, 1))
        let count = mesh.positions.count
        var partial = MeshData(positions: [.zero, SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)], indices: [0, 1, 2])
        mesh.append(partial)
        XCTAssertEqual(mesh.positions.count, count + 3)
        XCTAssertEqual(mesh.indices.suffix(3), [UInt32(count), UInt32(count + 1), UInt32(count + 2)])
        partial.normals = []
        let moved = PrimitiveMesh.make(.cube).transformed(Transform(position: Vec3(2, 0, 0), scale: Vec3(2, 1, 1)))
        let bounds = try XCTUnwrap(moved.bounds)
        XCTAssertEqual(bounds.min.x, 1, accuracy: 1e-5)
        XCTAssertEqual(bounds.max.x, 3, accuracy: 1e-5)
        let offset = PrimitiveMesh.make(.cube).transformed(Transform(position: Vec3(2, 0, 0)))
        let mirrored = offset.mirroredCopy(axis: .x)
        let mirroredBounds = try XCTUnwrap(mirrored.bounds)
        XCTAssertEqual(mirroredBounds.max.x, -1.5, accuracy: 1e-5)
        assertOutward(mirrored, center: SIMD3<Float>(-2, 0.5, 0))
    }

    func testTubeFromStroke() throws {
        let stroke = DrawingRecipe.Stroke(points: [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(2, 1, 0), Vec3(2, 2, 1)], widths: [0.1, 0.1, 0.2, 0.05])
        let tube = DrawingMesher.tube(stroke, sides: 6)
        XCTAssertEqual(tube.positions.count, 4 * 6 + 2)
        XCTAssertEqual(tube.triangleCount, 3 * 6 * 2 + 12)
        let bounds = try XCTUnwrap(tube.bounds)
        XCTAssertTrue(bounds.contains(Vec3(0, 0, 0)))
        XCTAssertTrue(bounds.contains(Vec3(2, 2, 1)))
        // A straight tube is closed and faces outward.
        let straight = DrawingMesher.tube(.init(points: [Vec3(0, 0, 0), Vec3(0, 0, 2)], widths: [0.2, 0.2]), sides: 8)
        assertOutward(straight, center: SIMD3<Float>(0, 0, 1))
        // A single tap becomes a small ball.
        let dot = DrawingMesher.tube(.init(points: [Vec3(1, 1, 1)], widths: [0.1]), sides: 6)
        let dotBounds = try XCTUnwrap(dot.bounds)
        XCTAssertTrue(dotBounds.center.isApproximately(Vec3(1, 1, 1), tolerance: 1e-5))
    }

    func testRibbonIsDoubleSided() {
        let stroke = DrawingRecipe.Stroke(points: [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(2, 0, 0)], widths: [0.1, 0.1, 0.1])
        let ribbon = DrawingMesher.ribbon(stroke, normal: .unitY)
        XCTAssertEqual(ribbon.triangleCount, 2 * 2 * 2)
        let upward = ribbon.normals.filter { $0.y > 0.9 }.count
        let downward = ribbon.normals.filter { $0.y < -0.9 }.count
        XCTAssertEqual(upward, downward)
        // Geometric winding agrees with the stored normals.
        for tri in stride(from: 0, to: ribbon.indices.count, by: 3) {
            let a = ribbon.positions[Int(ribbon.indices[tri])]
            let b = ribbon.positions[Int(ribbon.indices[tri + 1])]
            let c = ribbon.positions[Int(ribbon.indices[tri + 2])]
            XCTAssertGreaterThan(dot3(cross3(b - a, c - a), ribbon.normals[Int(ribbon.indices[tri])]), 0)
        }
        XCTAssertFalse(DrawingMesher.ribbon(.init(points: [.zero], widths: [0.1]), normal: .unitY).isEmpty)
    }

    func testExtrudeOutline() throws {
        // An L-shaped (concave) outline drawn clockwise on the ground.
        let outline = [Vec3(0, 0, 0), Vec3(0, 0, -2), Vec3(1, 0, -2), Vec3(1, 0, -1), Vec3(2, 0, -1), Vec3(2, 0, 0), Vec3(0, 0, 0)]
        let mesh = DrawingMesher.extrude(outline: outline, normal: .unitY, depth: 0.5)
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.max.y, 0.5, accuracy: 1e-5)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-5)
        // 6-gon → 4 cap triangles each side + 6 walls × 2.
        XCTAssertEqual(mesh.triangleCount, 4 * 2 + 12)
        // Cap area equals the L area (3 m²).
        var area: Float = 0
        for tri in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[tri])]
            let b = mesh.positions[Int(mesh.indices[tri + 1])]
            let c = mesh.positions[Int(mesh.indices[tri + 2])]
            let n = cross3(b - a, c - a)
            if n.y > 0, abs(a.y - 0.5) < 1e-5 { area += length3(n) / 2 }
        }
        XCTAssertEqual(area, 3, accuracy: 1e-4)
        XCTAssertTrue(DrawingMesher.extrude(outline: [.zero, .one], normal: .unitY, depth: 1).isEmpty)
        XCTAssertTrue(DrawingMesher.extrude(outline: [], normal: .unitY, depth: 1).isEmpty)
    }

    func testTriangulationAndArea() {
        let square = [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)]
        XCTAssertEqual(DrawingMesher.signedArea(square), 1)
        XCTAssertEqual(DrawingMesher.triangulate(square).count, 2)
        XCTAssertEqual(DrawingMesher.signedArea(square.reversed()), -1)
        // Self-intersecting bow-tie still yields triangles (fan fallback) instead of nothing.
        let bowtie = [Vec2(0, 0), Vec2(1, 1), Vec2(1, 0), Vec2(0, 1)]
        XCTAssertFalse(DrawingMesher.triangulate(bowtie).isEmpty)
        XCTAssertTrue(DrawingMesher.pointInTriangle(Vec2(0.2, 0.2), Vec2(0, 0), Vec2(1, 0), Vec2(0, 1)))
        XCTAssertFalse(DrawingMesher.pointInTriangle(Vec2(2, 2), Vec2(0, 0), Vec2(1, 0), Vec2(0, 1)))
    }

    func testLatheFacesOutwardEitherDirection() throws {
        let up = [Vec3(0.5, 0, 0), Vec3(0.4, 0.5, 0), Vec3(0.2, 1, 0)]
        for profile in [up, up.reversed()] {
            let mesh = DrawingMesher.lathe(profile: profile, segments: 8)
            let bounds = try XCTUnwrap(mesh.bounds)
            XCTAssertEqual(bounds.max.y, 1, accuracy: 1e-5)
            XCTAssertEqual(bounds.max.x, 0.5, accuracy: 0.01)
            assertOutward(mesh, center: SIMD3<Float>(0, 0.5, 0))
        }
        XCTAssertTrue(DrawingMesher.lathe(profile: [.zero], segments: 8).isEmpty)
    }

    func testRecipeMeshing() {
        let strokes = [DrawingRecipe.Stroke(points: [Vec3(0.3, 0, 0), Vec3(0.3, 1, 0), Vec3(0, 1.2, 0)], widths: [0.05, 0.05, 0.05])]
        for style in DrawingRecipe.Style.allCases {
            let mesh = DrawingMesher.mesh(for: DrawingRecipe(style: style, strokes: strokes, normal: .unitZ, depth: 0.2, segments: 6))
            XCTAssertFalse(mesh.isEmpty, "\(style)")
        }
        XCTAssertTrue(DrawingMesher.mesh(for: DrawingRecipe(style: .tube, strokes: [])).isEmpty)
        let basis = DrawingMesher.basis(for: .unitY)
        XCTAssertTrue(basis.0.cross(basis.1).isApproximately(.unitY))
        let sideBasis = DrawingMesher.basis(for: .unitX)
        XCTAssertTrue(sideBasis.0.cross(sideBasis.1).isApproximately(.unitX))
    }

    func testStrokeFilter() {
        // Noisy dense line along X.
        var points: [Vec3] = []
        for index in 0 ... 200 {
            points.append(Vec3(Double(index) * 0.005, index % 2 == 0 ? 0.002 : -0.002, 0))
        }
        let widths = Array(repeating: 0.05, count: points.count)
        let raw = StrokeFilter.process(points: points, widths: widths, smoothing: 0)
        XCTAssertLessThan(raw.points.count, points.count, "spacing merges dense points")
        XCTAssertEqual(raw.points.first, points.first)
        XCTAssertEqual(raw.points.last, points.last)
        let smooth = StrokeFilter.process(points: points, widths: widths, smoothing: 1)
        XCTAssertLessThan(smooth.points.count, raw.points.count, "smoothing simplifies")
        XCTAssertEqual(smooth.points.count, smooth.widths.count)
        XCTAssertEqual(smooth.points.first, points.first)
        XCTAssertEqual(StrokeFilter.process(points: [.zero], widths: [0.1], smoothing: 1).points.count, 1)
        let two = StrokeFilter.process(points: [.zero, Vec3(0.001, 0, 0)], widths: [], smoothing: 0.5)
        XCTAssertEqual(two.points.count, 2)
        XCTAssertEqual(StrokeFilter.rdp([.zero, .one], tolerance: 1), [0, 1])
        XCTAssertEqual(StrokeFilter.rdp([.zero, .zero, .zero], tolerance: 0.1), [0, 2])
    }

    func testGuideSurfaceIntersections() throws {
        let down = Ray(origin: Vec3(0.2, 5, 0.1), direction: Vec3(0, -1, 0))
        let plane = try XCTUnwrap(GuideSurface.plane(origin: .zero, normal: .unitY).intersect(down))
        XCTAssertTrue(plane.point.isApproximately(Vec3(0.2, 0, 0.1)))
        XCTAssertEqual(plane.normal, .unitY)
        XCTAssertEqual(plane.distance, 5, accuracy: 1e-9)
        // From below, the facing side flips.
        let up = Ray(origin: Vec3(0, -3, 0), direction: .unitY)
        XCTAssertEqual(GuideSurface.plane(origin: .zero, normal: .unitY).intersect(up)?.normal, -Vec3.unitY)
        XCTAssertNil(GuideSurface.plane(origin: .zero, normal: .unitY).intersect(Ray(origin: Vec3(0, 1, 0), direction: .unitX)))
        XCTAssertNil(GuideSurface.plane(origin: .zero, normal: .unitY).intersect(Ray(origin: Vec3(0, 1, 0), direction: .unitY)))

        let box = try XCTUnwrap(GuideSurface.box(center: .zero, size: Vec3(2, 2, 2)).intersect(down))
        XCTAssertTrue(box.point.isApproximately(Vec3(0.2, 1, 0.1)))
        XCTAssertEqual(box.normal, .unitY)
        let side = try XCTUnwrap(GuideSurface.box(center: .zero, size: Vec3(2, 2, 2)).intersect(Ray(origin: Vec3(-5, 0, 0), direction: .unitX)))
        XCTAssertEqual(side.normal, -Vec3.unitX)
        XCTAssertNil(GuideSurface.box(center: .zero, size: Vec3(2, 2, 2)).intersect(Ray(origin: Vec3(5, 5, 5), direction: .unitX)))
        XCTAssertNil(GuideSurface.box(center: .zero, size: Vec3(2, 2, 2)).intersect(Ray(origin: Vec3(0, 5, 0), direction: .unitY)))

        let sphere = try XCTUnwrap(GuideSurface.sphere(center: .zero, radius: 1).intersect(down))
        XCTAssertEqual(sphere.point.length, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(sphere.normal.y, 0.9)
        XCTAssertNil(GuideSurface.sphere(center: .zero, radius: 1).intersect(Ray(origin: Vec3(5, 5, 0), direction: .unitX)))
        let inside = try XCTUnwrap(GuideSurface.sphere(center: .zero, radius: 1).intersect(Ray(origin: .zero, direction: .unitX)))
        XCTAssertEqual(inside.distance, 1, accuracy: 1e-9)

        let cylinder = GuideSurface.cylinder(base: .zero, radius: 1, height: 2)
        let sideHit = try XCTUnwrap(cylinder.intersect(Ray(origin: Vec3(-5, 1, 0), direction: .unitX)))
        XCTAssertTrue(sideHit.point.isApproximately(Vec3(-1, 1, 0)))
        XCTAssertTrue(sideHit.normal.isApproximately(-Vec3.unitX))
        let capHit = try XCTUnwrap(cylinder.intersect(down))
        XCTAssertEqual(capHit.point.y, 2, accuracy: 1e-9)
        XCTAssertEqual(capHit.normal, .unitY)
        XCTAssertNil(cylinder.intersect(Ray(origin: Vec3(-5, 5, 0), direction: .unitX)))
        for surface in [GuideSurface.plane(origin: .zero, normal: .unitY), .box(center: .zero, size: .one), cylinder, .sphere(center: .zero, radius: 1)] {
            XCTAssertFalse(surface.kindName.isEmpty)
            XCTAssertEqual(try LoweyJSON.decode(GuideSurface.self, from: LoweyJSON.encode(surface)), surface)
        }
    }

    func testViewAxes() {
        for axis in ViewAxis.allCases {
            XCTAssertFalse(axis.displayName.isEmpty)
            XCTAssertEqual(axis.planeNormal.length, 1)
            _ = axis.angles
        }
        XCTAssertEqual(ViewAxis.top.planeNormal, .unitY)
    }

    func testOBJParser() throws {
        let obj = """
        # a quad and a triangle with negative indices
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        vt 0 0
        vt 1 0
        vt 1 1
        vn 0 0 1
        f 1/1/1 2/2/1 3/3/1 4/1/1
        v 0 0 1
        f -1 -4 -3
        o ignored
        """
        let mesh = try OBJParser.parse(obj)
        XCTAssertEqual(mesh.triangleCount, 3)
        XCTAssertEqual(mesh.bounds?.max, Vec3(1, 1, 1))
        XCTAssertThrowsError(try OBJParser.parse("# nothing here\nv 1 2 3\n"))
        let noNormals = try OBJParser.parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
        XCTAssertEqual(noNormals.normals.first?.z ?? 0, 1, accuracy: 1e-5)
    }

    func testGLTFDependencies() {
        let json = """
        {"buffers":[{"uri":"model.bin"},{"uri":"data:application/octet-stream;base64,AAAA"}],
         "images":[{"uri":"textures/Base%20Color.png"},{"bufferView":1}]}
        """
        XCTAssertEqual(GLTFDependencies.referencedURIs(in: Data(json.utf8)), ["model.bin", "textures/Base Color.png"])
        XCTAssertEqual(GLTFDependencies.referencedURIs(in: Data("nope".utf8)), [])
    }
}

final class MeshRaycastTests: XCTestCase {
    func testHitsNearestFaceFacingViewer() throws {
        let cube = PrimitiveMesh.make(.cube)
        let hit = try XCTUnwrap(MeshRaycast.intersect(Ray(origin: Vec3(0.1, 5, 0.2), direction: -Vec3.unitY), mesh: cube))
        XCTAssertEqual(hit.point.y, 1, accuracy: 1e-5)
        XCTAssertEqual(hit.normal.y, 1, accuracy: 1e-5)
        XCTAssertEqual(hit.distance, 4, accuracy: 1e-5)
        let side = try XCTUnwrap(MeshRaycast.intersect(Ray(origin: Vec3(-3, 0.5, 0), direction: .unitX), mesh: cube))
        XCTAssertEqual(side.point.x, -0.5, accuracy: 1e-5)
        XCTAssertEqual(side.normal.x, -1, accuracy: 1e-5)
        XCTAssertNil(MeshRaycast.intersect(Ray(origin: Vec3(3, 5, 3), direction: -Vec3.unitY), mesh: cube))
        XCTAssertNil(MeshRaycast.intersect(Ray(origin: Vec3(0, 5, 0), direction: .unitY), mesh: cube))
        // From inside, the far wall is hit and its normal still faces the ray origin.
        let inside = try XCTUnwrap(MeshRaycast.intersect(Ray(origin: Vec3(0, 0.5, 0), direction: .unitX), mesh: cube))
        XCTAssertEqual(inside.normal.x, -1, accuracy: 1e-5)
    }
}
