import Foundation
@testable import LoweyCore
import XCTest

/// The brush engine itself is hmm-kit's (HmmBrush, tested there); these check what Maquette builds on it.
final class BrushEngineTests: XCTestCase {
    func testGreyPNGDecodesBack() throws {
        let image = GreyImage(width: 70000 / 700, height: 700) { x, y in x * y }
        let png = GreyPNG.encode(image)
        XCTAssertEqual(png.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // IDAT starts after the signature (8) and IHDR (25); its zlib body skips the 2-byte header and 4-byte Adler.
        let idatLength = Int(png[33]) << 24 | Int(png[34]) << 16 | Int(png[35]) << 8 | Int(png[36])
        let zlib = png.subdata(in: 41 ..< 41 + idatLength)
        let raw = try Inflate.decompress(zlib.subdata(in: 2 ..< zlib.count - 4))
        XCTAssertEqual(raw.count, (image.width + 1) * image.height)
        XCTAssertEqual(raw[1 + image.width * 3 / 4 + (image.width + 1) * 350], image.pixels[350 * image.width + image.width * 3 / 4])
    }

    func testEditingInkKeepsTheBrushAndSeed() {
        let stroke = DrawingRecipe.Stroke(points: (0 ..< 6).map { Vec3(Double($0), 0, 0) }, widths: Array(repeating: 0.1, count: 6),
                                          alphas: [1, 0.9, 0.8, 0.7, 0.6, 0.5], brush: "b-1", seed: 42)
        let recipe = DrawingRecipe(style: .ink, strokes: [stroke])
        let erased = InkEditing.erasing(recipe) { _, point in point == 2 }
        XCTAssertEqual(erased.strokes.count, 2)
        XCTAssertEqual(erased.strokes[1].alphas, [0.7, 0.6, 0.5])
        XCTAssertTrue(erased.strokes.allSatisfy { $0.brush == "b-1" && $0.seed == 42 })
        let moved = InkEditing.moving([0], by: Vec3(0, 1, 0), in: recipe)
        XCTAssertEqual(moved.strokes[0].brush, "b-1")
        XCTAssertEqual(InkMesher.trimmed(stroke, to: 2.5).alphas?.last ?? 0, 0.75, accuracy: 1e-9)
    }

    func testOldStrokesStillRead() throws {
        let ink = #"{"points":[[0,0,0],[1,0,0]],"widths":[0.1,0.1]}"#
        let stroke = try JSONDecoder().decode(DrawingRecipe.Stroke.self, from: Data(ink.utf8))
        XCTAssertNil(stroke.brush)
        XCTAssertEqual(stroke.path.alphas, [1, 1])
        let flip = ##"{"points":[[0,0],[1,0]],"widths":[0.01,0.01],"color":"#000000"}"##
        let decoded = try JSONDecoder().decode(FlipStroke.self, from: Data(flip.utf8))
        XCTAssertNil(decoded.seed)
        let drawn = FlipStroke(points: [Vec2(0, 0), Vec2(1, 1)], widths: [0.01, 0.01], color: decoded.color, alphas: [1, 0.5], brush: "b-2",
                               seed: 9)
        XCTAssertEqual(try JSONDecoder().decode(FlipStroke.self, from: JSONEncoder().encode(drawn)), drawn)
    }

    func testProjectBrushesAreOneUndoableCommand() throws {
        let document = Document(project: ProjectInfo(id: "p", name: "Brushes"), scene: Scene(id: "s", name: "S"))
        let key = BrushKey.key(for: BuiltInBrushes.pencil)
        var frozen = BuiltInBrushes.pencil
        frozen.id = key
        let applied = try assertReverts(.setBrushes([key: frozen]), on: document)
        XCTAssertEqual(applied.project.brushes[key]?.name, "Pencil")
        let encoded = try SchemaCoder.shared.encode(applied.project, kind: .project)
        XCTAssertEqual(try SchemaCoder.shared.decode(ProjectInfo.self, kind: .project, from: encoded).brushes, [key: frozen])
        XCTAssertFalse(try String(decoding: SchemaCoder.shared.encode(document.project, kind: .project), as: UTF8.self).contains("brushes"))
    }
}
