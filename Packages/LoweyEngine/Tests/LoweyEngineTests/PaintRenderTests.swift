import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import Metal
import XCTest

/// Painting on models on the GPU: a painted object shows its paint, a stroke lands where the camera sees the object
/// (and nowhere else), what it changed reads back as tiles, and paint follows a shape that changed under it.
@MainActor
final class PaintRenderTests: XCTestCase {
    private var device: RenderDevice!

    override func setUp() async throws {
        device = try RenderDevice.sharedDevice()
    }

    /// A white cube in front of the camera with one layer (filled when `fill` is given), and its files.
    private func paintedCube(fill: RGBA?) throws -> (Document, [String: Data]) {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(0.95, 0.95, 0.95)))
        let mesh = try XCTUnwrap(PaintSource.mesh(of: cube))
        var (paint, _, files) = try PaintOperations.prepare(mesh: mesh, keepOwnUVs: false, size: 1024)
        if let fill {
            let filled = PaintOperations.fill(fill, layer: paint.layers[0], surface: paint.surface, object: "cube")
            files.merge(filled.files) { _, new in new }
            guard case let .paintTiles(_, changes) = filled.command else { throw CommandError.empty }
            for change in changes {
                paint.layers[0].tiles[change.tile] = change.file
            }
        }
        cube.paint = paint
        let document = TestDocuments.document("paint", objects: [cube], camera: Vec3(0, 0.5, 3.2), look: Look(presetID: LookPreset.clay.id))
        return (document, files)
    }

    /// Commits the read-back and waits for the GPU.
    private func finish(_ readback: PaintTextures.StrokeReadback) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            readback.commandBuffer.addCompletedHandler { _ in continuation.resume() }
            readback.commandBuffer.commit()
        }
    }

    private func request(_ document: Document, files: [String: Data]) -> (ShotBuilder, FrameRequest) {
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        builder.paintFile = { files[$0] }
        return (builder, builder.request(at: 0, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: 0))
    }

    func testAPaintedCubeShowsItsPaint() async throws {
        let (document, files) = try paintedCube(fill: RGBA(0.9, 0.1, 0.1, 1))
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        let (_, request) = request(document, files: files)
        let image = try await frames.image(request, width: 640, height: 360)
        GoldenImage().attach(image, name: "paint-cube")
        let center = ImageChecks.rgb(image, x: 0.5, y: 0.5)
        XCTAssertGreaterThan(center.r, center.g + 0.25, "the cube shows its red paint")
        XCTAssertTrue(frames.renderer.lastScene?.items.contains { $0.painted == "cube" } == true)
        // Without its files the cube is drawn as it is: no paint, not a crash.
        let (_, bare) = self.request(document, files: [:])
        let plain = try await frames.image(bare, width: 640, height: 360)
        let unpainted = ImageChecks.rgb(plain, x: 0.5, y: 0.5)
        XCTAssertLessThan(abs(unpainted.r - unpainted.g), 0.1, "its own colour")
    }

    func testAStrokeLandsWhereTheCubeIsSeenAndReadsBack() async throws {
        let (document, files) = try paintedCube(fill: nil)
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        var (_, request) = request(document, files: files)
        let brush = BuiltInBrushes.inkPen
        let points = (0 ... 30).map { Vec2(200 + Double($0) * 8, 180) }
        let path = BrushPath(points: points, widths: Array(repeating: 18, count: points.count), alphas: Array(repeating: 1, count: points.count))
        request.livePaint = LivePaint(object: "cube", layer: "l1", stroke: 1, source: .stamps(BrushStroker.dabs(path, brush: brush, seed: 1), brush: brush),
                                      color: RGBA(0.1, 0.2, 0.95, 1), erases: false, pixelsPerPoint: 1)
        let image = try await frames.image(request, width: 640, height: 360)
        GoldenImage().attach(image, name: "paint-stroke")
        let onStroke = ImageChecks.rgb(image, x: 0.5, y: 0.5)
        XCTAssertGreaterThan(onStroke.b, onStroke.r + 0.2, "the stroke shows on the cube in the frame that drew it")
        let readback = try XCTUnwrap(frames.renderer.paintStrokeReadback())
        await finish(readback)
        let tiles = PaintPixels.changedTiles(after: readback.bytes(readback.after), before: readback.bytes(readback.before), size: readback.size)
        XCTAssertFalse(tiles.isEmpty, "the stroke changed tiles")
        XCTAssertLessThan(tiles.count, 8, "only the tiles under the stroke (of 16)")
        let blue = tiles.values
            .contains { tile in stride(from: 0, to: tile.pixels.count, by: 4).contains { tile.pixels[$0 + 2] > 200 && tile.pixels[$0 + 3] > 200 } }
        XCTAssertTrue(blue, "in its colour")
        XCTAssertNil(frames.renderer.paintStrokeReadback(), "read once")
    }

    func testAStrokeOffTheCubePaintsNothing() async throws {
        let (document, files) = try paintedCube(fill: nil)
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        var (_, request) = request(document, files: files)
        let brush = BuiltInBrushes.inkPen
        let points = (0 ... 20).map { Vec2(20 + Double($0) * 4, 30) }
        let path = BrushPath(points: points, widths: Array(repeating: 12, count: points.count), alphas: Array(repeating: 1, count: points.count))
        request.livePaint = LivePaint(object: "cube", layer: "l1", stroke: 7, source: .stamps(BrushStroker.dabs(path, brush: brush, seed: 1), brush: brush),
                                      color: RGBA(0, 0, 0, 1), erases: false, pixelsPerPoint: 1)
        _ = try await frames.render(request, width: 640, height: 360)
        let readback = try XCTUnwrap(frames.renderer.paintStrokeReadback())
        await finish(readback)
        XCTAssertTrue(PaintPixels.changedTiles(after: readback.bytes(readback.after), before: readback.bytes(readback.before), size: readback.size).isEmpty,
                      "the sky isn't the cube")
    }

    func testPaintFollowsAShapeThatChanged() async throws {
        var (document, files) = try paintedCube(fill: RGBA(0.9, 0.1, 0.1, 1))
        document.scene.objects["cube"]?[.bevel] = .float(0.06)
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        let (_, request) = request(document, files: files)
        let image = try await frames.image(request, width: 640, height: 360)
        let center = ImageChecks.rgb(image, x: 0.5, y: 0.5)
        XCTAssertGreaterThan(center.r, center.g + 0.25, "carried onto the bevelled cube (exports carry it at once)")
    }

    func testPlacedModelsPaintAsOneSurface() throws {
        let box = PrimitiveMesh.make(.cube)
        var skinned = ImportedPart(name: "Arm", mesh: box, material: 0)
        skinned.joints = Array(repeating: SIMD4<UInt16>(0, 0, 0, 0), count: box.positions.count)
        skinned.weights = Array(repeating: SIMD4<Float>(1, 0, 0, 0), count: box.positions.count)
        let model = ImportedModel(parts: [ImportedPart(name: "Seat", mesh: box, material: 0), ImportedPart(name: "Back", mesh: box, material: 1)],
                                  materials: [
                                      ImportedMaterial(name: "Red", baseColor: RGBA(1, 0, 0)),
                                      ImportedMaterial(name: "Blue", baseColor: RGBA(0, 0, 1))
                                  ])
        let merged = try XCTUnwrap(AssetPaint.mergedMesh(model))
        XCTAssertEqual(merged.triangleCount, box.triangleCount * 2)
        XCTAssertEqual(AssetPaint.partOfTriangle(model).filter { $0 == 1 }.count, box.triangleCount)
        XCTAssertNil(AssetPaint.mergedMesh(ImportedModel(parts: [skinned], materials: [])), "characters wait for rigging")
        let unwrap = try PaintUnwrap.unwrap(merged)
        let baked = AssetPaint.bake(model, merged: merged, unwrap: unwrap, size: 128)
        let colours = Set(stride(from: 0, to: baked.pixels.count, by: 4).compactMap { baked.pixels[$0 + 3] == 255 ? baked.pixels[$0 + 2] > 128 : nil })
        XCTAssertEqual(colours, [true, false], "both parts' colours are baked in")
    }
}
