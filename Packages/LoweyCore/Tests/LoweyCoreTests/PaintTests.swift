import Foundation
@testable import LoweyCore
import XCTest

final class PaintTests: XCTestCase {
    private func paintedDocument(size: Int = 512) throws -> (Document, ObjectPaint, PaintUnwrap) {
        var document = makeDocument()
        let cube = try XCTUnwrap(document.scene.objects["a"])
        let mesh = try XCTUnwrap(PaintSource.mesh(of: cube))
        let prepared = try PaintOperations.prepare(mesh: mesh, keepOwnUVs: false, size: size)
        _ = try EditCommand.setPaint("a", prepared.paint).apply(to: &document)
        return (document, prepared.paint, prepared.unwrap)
    }

    // MARK: The document

    func testPaintCommandsRevertAndSurviveJSON() throws {
        let (document, paint, _) = try paintedDocument()
        try assertReverts(.setPaint("c", paint), on: document)
        try assertReverts(.setPaint("a", nil), on: document)
        let tile = PaintTileIndex(column: 1, row: 0)
        let applied = try assertReverts(.paintTiles("a", [PaintTileChange(layer: "l1", tile: tile, file: "paint/0000000000000001.png"),
                                                          PaintTileChange(layer: "l1", tile: tile, file: "paint/0000000000000002.png")]),
                                        on: document)
        XCTAssertEqual(applied.scene.objects["a"]?.paint?.layers[0][tile], "paint/0000000000000002.png", "the last change of a tile wins")
        var working = document
        XCTAssertThrowsError(try EditCommand.paintTiles("c", []).apply(to: &working), "no paint to change")
        XCTAssertThrowsError(try EditCommand.paintTiles("a", [PaintTileChange(layer: "nope", tile: tile, file: nil)]).apply(to: &working))
        XCTAssertEqual(EditCommand.paintTiles("a", []).label, "Paint")
        XCTAssertEqual(EditCommand.setPaint("a", nil).label, "Paint layers")
    }

    func testPaintSurvivesTheSceneFile() throws {
        let (document, paint, _) = try paintedDocument()
        let data = try LoweyJSON.encode(document.scene)
        let scene = try LoweyJSON.decode(Scene.self, from: data)
        XCTAssertEqual(scene.objects["a"]?.paint, paint)
        XCTAssertNil(scene.objects["c"]?.paint, "objects without paint write no paint")
        XCTAssertFalse(try String(decoding: LoweyJSON.encode(document.scene.objects["c"]), as: UTF8.self).contains("paint"))
    }

    func testTileIndexKeys() {
        XCTAssertEqual(PaintTileIndex(column: 3, row: 7).key, "3,7")
        XCTAssertEqual(PaintTileIndex(key: "3,7"), PaintTileIndex(column: 3, row: 7))
        XCTAssertNil(PaintTileIndex(key: "3"))
        XCTAssertNil(PaintTileIndex(key: "-1,2"))
        XCTAssertEqual(PaintSurface(size: 2000, unwrap: "u", mesh: "m").size, 1792, "whole tiles")
        XCTAssertEqual(PaintSurface(size: 2048, unwrap: "u", mesh: "m").allTiles.count, 64)
    }

    func testOnlySurfacesTakePaint() {
        XCTAssertTrue(SceneObject(id: "p", name: "P", kind: .primitive(.cube)).isPaintable)
        XCTAssertTrue(SceneObject(id: "m", name: "M", kind: .asset("chair")).isPaintable)
        XCTAssertFalse(SceneObject(id: "i", name: "I", kind: .drawing(DrawingRecipe(style: .ink, strokes: []))).isPaintable)
        XCTAssertTrue(SceneObject(id: "t", name: "T", kind: .drawing(DrawingRecipe(style: .tube, strokes: []))).isPaintable)
        XCTAssertFalse(SceneObject(id: "l", name: "L", kind: .light(.point)).isPaintable)
    }

    // MARK: Pictures

    func testPNGRoundTripsAndDecodesEveryFilter() throws {
        var image = RGBAImage.clear(width: 5, height: 3)
        image.setPixel(0, 0, RGBA(1, 0, 0, 1))
        image.setPixel(4, 2, RGBA(0.2, 0.4, 0.6, 0.5))
        XCTAssertEqual(try PNGCodec.decode(PNGCodec.encode(image)), image)
        // Hand-made rows with each filter (sub, up, average, Paeth) over an RGB picture.
        let rows: [[UInt8]] = [[1, 10, 20, 30, 5, 5, 5], [2, 1, 1, 1, 2, 2, 2], [3, 4, 4, 4, 8, 8, 8], [4, 0, 0, 0, 1, 1, 1]]
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(2)
        header.appendBigEndian(4)
        header += Data([8, 2, 0, 0, 0])
        png += GreyPNG.chunk("IHDR", header)
        png += GreyPNG.chunk("IDAT", GreyPNG.zlibStored(rows.flatMap(\.self)))
        png += GreyPNG.chunk("IEND", Data())
        let decoded = try PNGCodec.decode(png)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(Array(decoded.pixels[0 ..< 8]), [10, 20, 30, 255, 15, 25, 35, 255], "sub")
        XCTAssertEqual(Array(decoded.pixels[8 ..< 11]), [11, 21, 31], "up")
        XCTAssertEqual(Array(decoded.pixels[16 ..< 19]), [9, 14, 19], "average")
        XCTAssertEqual(Array(decoded.pixels[24 ..< 27]), [9, 14, 19], "Paeth picks the pixel above")
        XCTAssertThrowsError(try PNGCodec.decode(Data([1, 2, 3])))
    }

    func testTilesAndContentNames() {
        let surface = PaintSurface(size: 512, unwrap: "u", mesh: "m")
        var image = RGBAImage.clear(width: 512, height: 512)
        image.setPixel(300, 10, RGBA(1, 1, 1, 1))
        let tiles = PaintComposer.tiles(of: image, surface: surface)
        XCTAssertEqual(Array(tiles.keys), [PaintTileIndex(column: 1, row: 0)], "clear tiles are no files")
        let layer = PaintLayer(id: "l1", name: "Layer 1")
        let (changes, files) = PaintOperations.tileChanges(image, layer: layer, surface: surface)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(changes[0].file?.hasPrefix("paint/") == true)
        var painted = layer
        painted[PaintTileIndex(column: 1, row: 0)] = changes[0].file
        XCTAssertEqual(PaintComposer.layerImage(painted, surface: surface) { name in files[name].flatMap { try? PNGCodec.decode($0) } }, image)
        let cleared = PaintOperations.tileChanges(.clear(width: 512, height: 512), layer: painted, surface: surface)
        XCTAssertEqual(cleared.changes, [PaintTileChange(layer: "l1", tile: PaintTileIndex(column: 1, row: 0), file: nil)])
        XCTAssertEqual(PaintFiles.tileName(for: Data([1, 2])), PaintFiles.tileName(for: Data([1, 2])))
    }

    // MARK: Unwrap

    func testUnwrapCoversTheMeshAndRoundTripsItsFile() throws {
        let mesh = PrimitiveMesh.make(.sphere, shading: .smooth)
        let unwrap = try PaintUnwrap.unwrap(mesh)
        XCTAssertEqual(unwrap.indices.count, mesh.indices.count, "the mesh's triangles, in order")
        XCTAssertTrue(unwrap.source.allSatisfy { Int($0) < mesh.positions.count })
        XCTAssertTrue(unwrap.uvs.allSatisfy { (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y) })
        XCTAssertEqual(try PaintUnwrap(data: unwrap.data), unwrap)
        XCTAssertThrowsError(try PaintUnwrap(data: Data("MQUV".utf8)))
        let painted = try XCTUnwrap(unwrap.mesh(over: mesh))
        XCTAssertEqual(painted.triangleCount, mesh.triangleCount)
        for triangle in 0 ..< mesh.triangleCount {
            for corner in 0 ..< 3 {
                let original = mesh.positions[Int(mesh.indices[triangle * 3 + corner])]
                XCTAssertEqual(painted.positions[Int(painted.indices[triangle * 3 + corner])], original)
            }
        }
        // Charts don't overlap: the coverage counts each pixel once.
        let coverage = PaintRaster.coverage(unwrap, size: 256)
        XCTAssertGreaterThan(coverage.filter { $0 != 0 }.count, 256 * 256 / 4)
        XCTAssertThrowsError(try PaintUnwrap.unwrap(MeshData()))
    }

    func testOwnUVsAreKeptOnlyWhenTheyDontOverlap() throws {
        var quad = MeshData()
        let a = quad.addVertex(SIMD3<Float>(0, 0, 0), uv: SIMD2<Float>(0, 0))
        let b = quad.addVertex(SIMD3<Float>(1, 0, 0), uv: SIMD2<Float>(1, 0))
        let c = quad.addVertex(SIMD3<Float>(1, 1, 0), uv: SIMD2<Float>(1, 1))
        let d = quad.addVertex(SIMD3<Float>(0, 1, 0), uv: SIMD2<Float>(0, 1))
        quad.addTriangle(a, b, c)
        quad.addTriangle(a, c, d)
        XCTAssertNotNil(PaintUnwrap.existing(quad))
        var twice = quad
        twice.append(quad)
        XCTAssertNil(PaintUnwrap.existing(twice), "two faces on the same pixels")
        var outside = quad
        outside.uvs[2] = SIMD2<Float>(2, 1)
        XCTAssertNil(PaintUnwrap.existing(outside))
        XCTAssertNil(PaintUnwrap.existing(PrimitiveMesh.make(.cube)), "every face of the cube on the whole square")
        let prepared = try PaintOperations.prepare(mesh: quad, keepOwnUVs: true, size: 256)
        XCTAssertEqual(try PaintUnwrap(data: XCTUnwrap(prepared.files[prepared.paint.surface.unwrap])).uvs, quad.uvs)
    }

    func testFingerprintFollowsTheShape() {
        let cube = PrimitiveMesh.make(.cube)
        XCTAssertEqual(PaintMesh.fingerprint(cube), PaintMesh.fingerprint(PrimitiveMesh.make(.cube)))
        XCTAssertNotEqual(PaintMesh.fingerprint(cube), PaintMesh.fingerprint(PrimitiveMesh.make(.sphere)))
        var object = SceneObject(id: "c", name: "C", kind: .primitive(.cube), transform: Transform(scale: Vec3(4, 1, 1)))
        XCTAssertEqual(PaintSource.stretch(of: object), SIMD3<Float>(4, 1, 1))
        object[.bevel] = .float(0.05)
        XCTAssertEqual(PaintSource.stretch(of: object), SIMD3<Float>(1, 1, 1), "a bevelled box is built at its size")
        XCTAssertNil(PaintSource.mesh(of: SceneObject(id: "l", name: "L", kind: .light(.point))))
    }

    // MARK: Compositing

    func testBlendModesFollowTheW3CFormulas() {
        let red = SIMD3<Double>(1, 0, 0)
        let grey = SIMD4<Double>(0.5, 0.5, 0.5, 1)
        XCTAssertEqual(PaintComposer.blend(source: red, alpha: 1, mode: .normal, backdrop: grey), SIMD4<Double>(1, 0, 0, 1))
        XCTAssertEqual(PaintComposer.blend(source: red, alpha: 1, mode: .multiply, backdrop: grey), SIMD4<Double>(0.5, 0, 0, 1))
        XCTAssertEqual(PaintComposer.blend(source: red, alpha: 1, mode: .screen, backdrop: grey), SIMD4<Double>(1, 0.5, 0.5, 1))
        XCTAssertEqual(PaintComposer.blend(source: red, alpha: 0.5, mode: .normal, backdrop: grey), SIMD4<Double>(0.75, 0.25, 0.25, 1))
        // Over nothing, every mode shows the source.
        XCTAssertEqual(PaintComposer.blend(source: red, alpha: 1, mode: .multiply, backdrop: .zero), SIMD4<Double>(1, 0, 0, 1))
        XCTAssertEqual(PaintBlend.overlay.mix(0.25, 0.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(PaintBlend.add.mix(0.75, 0.5), 1)
    }

    func testCompositeHonoursOpacityVisibilityAndOrder() {
        let surface = PaintSurface(size: 256, unwrap: "u", mesh: "m")
        let white = RGBAImage(width: 256, height: 256, color: RGBA(1, 1, 1, 1))
        let red = RGBAImage(width: 256, height: 256, color: RGBA(1, 0, 0, 1))
        var bottom = PaintLayer(id: "l1", name: "Bottom")
        bottom.tiles["0,0"] = "white"
        var top = PaintLayer(id: "l2", name: "Top", opacity: 0.5, blend: .multiply)
        top.tiles["0,0"] = "red"
        let pictures = ["white": white, "red": red]
        func image(_ layer: PaintLayer) -> RGBAImage {
            PaintComposer.layerImage(layer, surface: surface) { pictures[$0] }
        }
        let both = PaintComposer.composite(ObjectPaint(surface: surface, layers: [bottom, top]), layer: image)
        XCTAssertEqual(both.pixel(10, 10).r, 1, accuracy: 0.01)
        XCTAssertEqual(both.pixel(10, 10).g, 0.5, accuracy: 0.01, "white × red at half opacity")
        top.visible = false
        let hidden = PaintComposer.composite(ObjectPaint(surface: surface, layers: [bottom, top]), layer: image)
        XCTAssertEqual(hidden.pixel(10, 10), RGBA(1, 1, 1, 1))
        let nothing = PaintComposer.composite(ObjectPaint(surface: surface, layers: []), layer: image)
        XCTAssertEqual(nothing.pixel(0, 0).a, 0)
        let flat = PaintComposer.flattened(nothing, over: RGBA(0, 0, 1, 1))
        XCTAssertEqual(flat.pixel(0, 0), RGBA(0, 0, 1, 1), "the object's own colour under no paint")
    }

    func testDilationFillsAroundChartsOnly() {
        var image = RGBAImage.clear(width: 8, height: 1)
        image.setPixel(3, 0, RGBA(1, 0, 0, 1))
        var coverage = [UInt8](repeating: 0, count: 8)
        coverage[3] = 1
        coverage[4] = 1
        PaintRaster.dilate(&image, coverage: coverage, passes: 2)
        XCTAssertEqual(image.pixel(2, 0), RGBA(1, 0, 0, 1), "outside the chart, pushed out")
        XCTAssertEqual(image.pixel(1, 0), RGBA(1, 0, 0, 1))
        XCTAssertEqual(image.pixel(4, 0).a, 0, "inside the chart, unpainted stays unpainted")
        XCTAssertEqual(image.pixel(0, 0).a, 0, "only `passes` deep")
    }

    // MARK: Moving paint

    func testFillClearAndLayerOperations() throws {
        let (document, paint, _) = try paintedDocument()
        let fill = PaintOperations.fill(RGBA(0, 1, 0, 1), layer: paint.layers[0], surface: paint.surface, object: "a")
        XCTAssertEqual(fill.files.count, 1, "one file for every tile of a fill")
        let filled = try assertReverts(fill.command, on: document)
        let filledPaint = try XCTUnwrap(filled.scene.objects["a"]?.paint)
        XCTAssertEqual(filledPaint.layers[0].tiles.count, 4)
        XCTAssertNotNil(PaintOperations.clear(filledPaint.layers[0], object: "a"))
        XCTAssertNil(PaintOperations.clear(paint.layers[0], object: "a"))

        let (add, newID) = try XCTUnwrap(PaintOperations.addLayer(to: filledPaint, above: "l1", object: "a"))
        let added = try assertReverts(add, on: filled)
        let twoLayers = try XCTUnwrap(added.scene.objects["a"]?.paint)
        XCTAssertEqual(twoLayers.layers.map(\.id), ["l1", newID])
        XCTAssertEqual(twoLayers.layers[1].name, "Layer 2")
        try assertReverts(XCTUnwrap(PaintOperations.moveLayer(newID, to: 0, in: twoLayers, object: "a")), on: added)
        XCTAssertNil(PaintOperations.moveLayer(newID, to: 1, in: twoLayers, object: "a"))
        try assertReverts(XCTUnwrap(PaintOperations.update(newID, in: twoLayers, object: "a") { $0.opacity = 0.4 }), on: added)
        XCTAssertNil(PaintOperations.update(newID, in: twoLayers, object: "a") { _ in })
        let deleted = try XCTUnwrap(PaintOperations.deleteLayer("l1", from: ObjectPaint(surface: paint.surface, layers: [paint.layers[0]]),
                                                                object: "a"))
        guard case let .setPaint(_, left) = deleted else { return XCTFail("a layer change") }
        XCTAssertEqual(left?.layers.count, 1, "the last layer is replaced by an empty one")
        let (duplicate, copyID) = try XCTUnwrap(PaintOperations.duplicateLayer("l1", in: twoLayers, object: "a"))
        guard case let .setPaint(_, copied) = duplicate else { return XCTFail("a layer change") }
        XCTAssertEqual(copied?.layer(copyID)?.tiles, twoLayers.layers[0].tiles)
        var full = twoLayers
        while let added = PaintOperations.addLayer(to: full, above: nil, object: "a"), case let .setPaint(_, more?) = added.0 {
            full = more
        }
        XCTAssertEqual(full.layers.count, ObjectPaint.maximumLayers)
    }

    func testMergeDownCompositesTheTwoLayers() throws {
        let surface = PaintSurface(size: 256, unwrap: "u", mesh: "m")
        var bottom = PaintLayer(id: "l1", name: "Bottom")
        bottom.tiles["0,0"] = "blue"
        var top = PaintLayer(id: "l2", name: "Top", opacity: 0.5)
        top.tiles["0,0"] = "red"
        let pictures = ["blue": RGBAImage(width: 256, height: 256, color: RGBA(0, 0, 1, 1)),
                        "red": RGBAImage(width: 256, height: 256, color: RGBA(1, 0, 0, 1))]
        let paint = ObjectPaint(surface: surface, layers: [bottom, top])
        let merged = try XCTUnwrap(PaintOperations.mergeDown("l2", in: paint, object: "a") { layer in
            PaintComposer.layerImage(layer, surface: surface) { pictures[$0] }
        })
        guard case let .setPaint(_, result?) = merged.command else { return XCTFail("a layer change") }
        XCTAssertEqual(result.layers.map(\.id), ["l1"])
        let file = try XCTUnwrap(result.layers[0].tiles["0,0"])
        let pixel = try PNGCodec.decode(XCTUnwrap(merged.files[file])).pixel(0, 0)
        XCTAssertEqual(pixel.r, 0.5, accuracy: 0.01)
        XCTAssertEqual(pixel.b, 0.5, accuracy: 0.01)
        XCTAssertNil(PaintOperations.mergeDown("l1", in: paint, object: "a") { _ in .clear(width: 1, height: 1) }, "nothing under the bottom layer")
    }

    func testBakeAndCarryPaintOntoANewShape() throws {
        let old = PrimitiveMesh.make(.sphere, shading: .smooth)
        let oldUnwrap = try PaintUnwrap.unwrap(old)
        let size = 128
        // Paint the top half of the sphere red, by position.
        let paintedMesh = try XCTUnwrap(oldUnwrap.mesh(over: old))
        let image = PaintTransfer.bake(oldUnwrap, size: size) { triangle, weights in
            let i = (Int(paintedMesh.indices[triangle * 3]), Int(paintedMesh.indices[triangle * 3 + 1]), Int(paintedMesh.indices[triangle * 3 + 2]))
            let y = paintedMesh.positions[i.0].y * weights.x + paintedMesh.positions[i.1].y * weights.y + paintedMesh.positions[i.2].y * weights.z
            return y > 0.75 ? RGBA(1, 0, 0, 1) : nil
        }
        XCTAssertFalse(image.isClear)
        // The same sphere, unwrapped again after a stretch: the paint must land on the top again.
        let new = old
        let newUnwrap = try PaintUnwrap.unwrap(new, scale: SIMD3<Float>(1, 2, 1))
        let map = PaintTransfer.correspondence(from: oldUnwrap, to: newUnwrap, size: size)
        let carried = PaintTransfer.carry(image, through: map, size: size)
        let newMesh = try XCTUnwrap(newUnwrap.mesh(over: new))
        var top = 0, topRed = 0, bottomRed = 0
        for triangle in 0 ..< newMesh.triangleCount {
            let i = (Int(newMesh.indices[triangle * 3]), Int(newMesh.indices[triangle * 3 + 1]), Int(newMesh.indices[triangle * 3 + 2]))
            let center = (newMesh.uvs[i.0] + newMesh.uvs[i.1] + newMesh.uvs[i.2]) / 3 * Float(size)
            let y = (newMesh.positions[i.0].y + newMesh.positions[i.1].y + newMesh.positions[i.2].y) / 3
            let pixel = carried.pixel(min(Int(center.x), size - 1), min(Int(center.y), size - 1))
            if y > 0.85 {
                top += 1
                if pixel.a > 0.5, pixel.r > 0.9 { topRed += 1 }
            } else if y < 0.6, pixel.a > 0.5 {
                bottomRed += 1
            }
        }
        XCTAssertGreaterThan(top, 0)
        XCTAssertGreaterThan(Double(topRed) / Double(top), 0.8, "the paint follows the surface")
        XCTAssertEqual(bottomRed, 0, "and stays where it was")
    }
}
