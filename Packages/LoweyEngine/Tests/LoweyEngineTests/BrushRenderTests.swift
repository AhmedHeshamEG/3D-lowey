import CoreGraphics
import ImageIO
import LoweyCore
@testable import LoweyEngine
import XCTest

/// The brush engine on the GPU: an imported Procreate brush set draws recognisably (the M5 acceptance golden), the
/// built-in brushes, ink strokes in a scene (drawn by their brush, still picked), and flipbook layers.
@MainActor
final class BrushRenderTests: XCTestCase {
    private var device: RenderDevice!

    override func setUp() async throws {
        device = try RenderDevice.sharedDevice()
    }

    private static func png(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// Each brush's sample stroke in a row of its own, black on white.
    private func sheet(_ brushes: [Brush], images: [String: Data], width: Int = 640, rowHeight: Int = 72) throws -> CGImage {
        let renderer = try BrushPreviewRenderer(device: device)
        let strokes = brushes.enumerated().map { index, brush in
            var path = BrushPreviewPath.sample(width: Double(width), height: Double(rowHeight), brush: brush, size: 12)
            path.points = path.points.map { $0 + Vec2(0, Double(index * rowHeight)) }
            return BrushPreviewStroke(path: path, brush: brush, color: RGBA(0.08, 0.08, 0.1), seed: UInt64(index + 1))
        }
        return try XCTUnwrap(renderer.image(strokes, width: width, height: rowHeight * brushes.count, background: .white) { key in
            images[key].flatMap(Self.png)
        })
    }

    func testAProcreateBrushSetImportsAndDrawsRecognisably() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("Brushes/Sample.brushset")
        let imported = try BrushFileImport.read(Data(contentsOf: url), fileName: "Sample.brushset") { UUID().uuidString }
        XCTAssertEqual(imported.brushes.map(\.name), ["Leaf Stamp", "Hard Pen"])
        let image = try sheet(imported.brushes, images: imported.images, rowHeight: 120)
        // The leaf tip stamps separate leaves (spacing 0.6 of a tip): many dark islands, not one line.
        let leafRow = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 640, height: 120)))
        XCTAssertGreaterThan(GoldenImage.coverage(leafRow).content, 0.02, "the leaves are drawn")
        try GoldenImage().assertMatches(image, named: "brushset-sample")
    }

    func testEveryBuiltInBrushDraws() throws {
        let image = try sheet(BuiltInBrushes.all, images: [:])
        for (index, brush) in BuiltInBrushes.all.enumerated() {
            let row = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: index * 72, width: 640, height: 72)))
            XCTAssertGreaterThan(GoldenImage.coverage(row).content, 0.01, "\(brush.name) draws")
        }
        try GoldenImage().assertMatches(image, named: "brushes-built-in")
    }

    func testInkDrawsWithItsBrushAndIsStillPicked() async throws {
        var document = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
        let pencil = BuiltInBrushes.pencil
        let key = BrushKey.key(for: pencil)
        var frozen = pencil
        frozen.id = key
        document.project.brushes = [key: frozen]
        let points = (0 ... 40).map { Vec3(-2 + Double($0) * 0.1, 1.6 + sin(Double($0) * 0.3) * 0.2, 1.5) }
        let stroke = DrawingRecipe.Stroke(points: points, widths: Array(repeating: 0.05, count: points.count), brush: key, seed: 3)
        var ink = SceneObject(id: "ink", name: "Ink", kind: .drawing(DrawingRecipe(style: .ink, strokes: [stroke], normal: .unitZ)))
        ink[.color] = .color(.rgba(RGBA(0.9, 0.1, 0.1)))
        document.scene.objects[ink.id] = ink
        document.scene.roots.append(ink.id)
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        let request = builder.request(at: 0, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: 0)
        let image = try await frames.image(request, width: 640, height: 360)
        GoldenImage().attach(image, name: "ink-pencil")
        // Red where the stroke runs: the pencil's stamps were drawn in the shading pass.
        let pixels = GoldenImage.rgba(image)
        let red = stride(from: 0, to: pixels.count, by: 4).count { pixels[$0] > 150 && pixels[$0 + 1] < 90 && pixels[$0 + 2] < 90 }
        XCTAssertGreaterThan(red, 200, "the ink is drawn in its colour")
        XCTAssertEqual(frames.renderer.lastScene?.brushes.count, 1, "the stamps came from the brush engine")
    }

    func testFlipbookLayersAreStampedAndBlended() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.clay.id, mood: .day)
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        var request = builder.request(at: 0, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: 0)
        let line = FlipbookPixelStroke(points: (0 ... 30).map { Vec2(40 + Double($0) * 18, 60) }, widths: Array(repeating: 10, count: 31),
                                       color: RGBA(0.1, 0.2, 0.95), filled: false, seed: 1)
        let burst = FlipbookPixelStroke(points: [Vec2(300, 200), Vec2(360, 230), Vec2(320, 300), Vec2(270, 260)], widths: [3, 3, 3, 3],
                                        color: RGBA(1, 0.85, 0.1), filled: true, seed: 2)
        request.flipbooks = [FlipbookDraw(track: "a", blend: .normal, opacity: 1, strokes: [line]),
                             FlipbookDraw(track: "b", blend: .normal, opacity: 0.5, strokes: [burst])]
        let image = try await frames.image(request, width: 640, height: 360)
        GoldenImage().attach(image, name: "flipbook-layers")
        let pixels = GoldenImage.rgba(image)
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let base = (y * 640 + x) * 4
            return (Int(pixels[base]), Int(pixels[base + 1]), Int(pixels[base + 2]))
        }
        let onLine = pixel(220, 60)
        XCTAssertGreaterThan(onLine.2, 180, "the blue line is stamped")
        XCTAssertLessThan(onLine.0, 80)
        let inBurst = pixel(315, 250)
        XCTAssertGreaterThan(inBurst.0, inBurst.2 + 40, "the filled shape is laid down at half opacity, yellow over the shot")
    }
}
