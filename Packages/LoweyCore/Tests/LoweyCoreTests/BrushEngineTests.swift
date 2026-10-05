import Foundation
@testable import LoweyCore
import XCTest

final class BrushEngineTests: XCTestCase {
    private func line(_ count: Int, length: Double, pressure: (Int) -> Double = { _ in 1 }) -> [BrushInput<Vec2>] {
        (0 ..< count).map { index in
            BrushInput(point: Vec2(length * Double(index) / Double(count - 1), 0), pressure: pressure(index), time: Double(index) / 240)
        }
    }

    // MARK: Paths

    func testPressureShapesSizeAndOpacity() {
        var brush = BuiltInBrushes.inkPen
        brush.dynamics = BrushDynamics(pressureSize: 1, pressureOpacity: 1, minimumSize: 0, minimumOpacity: 0)
        brush.stroke.streamline = 0
        let path = BrushStroker.path(line(5, length: 4) { Double($0) / 4 }, brush: brush, size: 2)
        XCTAssertEqual(path.points.count, 5)
        XCTAssertEqual(path.widths.first ?? -1, 0, accuracy: 1e-5)
        XCTAssertEqual(path.widths.last ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(path.alphas[2], 0.5, accuracy: 1e-9)
    }

    func testNoPressureDynamicsKeepsTheFullSize() {
        let path = BrushStroker.path(line(4, length: 3) { _ in 0.1 }, brush: BuiltInBrushes.technicalPen, size: 1.5)
        XCTAssertTrue(path.widths.allSatisfy { abs($0 - 1.5) < 1e-9 })
    }

    func testPressureCurveRemapsBeforeUse() {
        XCTAssertEqual(BrushCurve.soft.value(at: 0.35), 0.6, accuracy: 1e-9)
        XCTAssertEqual(BrushCurve.firm.value(at: 0.3), 0.175, accuracy: 1e-9)
        XCTAssertEqual(BrushCurve([Vec2(0.5, 0.2)]).clamped, .linear)
        XCTAssertEqual(BrushCurve([Vec2(1, 1), Vec2(0, 0)]).clamped.value(at: 0.25), 0.25, accuracy: 1e-9)
    }

    func testStreamlineSmoothsButTheStrokeEndsAtTheLift() {
        var samples = line(40, length: 10)
        for index in samples.indices where index % 2 == 1 {
            samples[index].point.y = 0.5
        }
        var smooth = BuiltInBrushes.technicalPen
        smooth.stroke.streamline = 1
        var raw = smooth
        raw.stroke.streamline = 0
        func wobble(_ path: BrushPath<Vec2>) -> Double { path.points.dropLast().map { abs($0.y - 0.25) }.reduce(0, +) }
        let smoothed = BrushStroker.path(samples, brush: smooth, size: 1)
        XCTAssertLessThan(wobble(smoothed), wobble(BrushStroker.path(samples, brush: raw, size: 1)) * 0.5)
        XCTAssertEqual(smoothed.points.last, samples.last?.point)
    }

    func testTiltAndSpeedChangeTheStamp() {
        var brush = BuiltInBrushes.technicalPen
        brush.dynamics.tiltSize = 1
        let upright = BrushStroker.path([BrushInput(point: Vec2(0, 0), pressure: 1, altitude: .pi / 2)], brush: brush, size: 1)
        let flat = BrushStroker.path([BrushInput(point: Vec2(0, 0), pressure: 1, altitude: 0)], brush: brush, size: 1)
        XCTAssertEqual(upright.widths[0], 1, accuracy: 1e-9)
        XCTAssertEqual(flat.widths[0], 3, accuracy: 1e-9)
        brush.dynamics.tiltSize = 0
        brush.dynamics.speedSize = 1
        let fast = BrushStroker.path(line(10, length: 500), brush: brush, size: 1)
        XCTAssertLessThan(fast.widths.last ?? 1, 0.8)
    }

    func testCloseSamplesMergeButTheLiftIsKept() {
        let samples = line(100, length: 1)
        let path = BrushStroker.path(samples, brush: BuiltInBrushes.technicalPen, size: 1, minimumSpacing: 0.1)
        XCTAssertLessThanOrEqual(path.points.count, 12)
        XCTAssertEqual(path.points.last, Vec2(1, 0))
    }

    // MARK: Dabs

    func testStampsAreSpacedByTheTipSize() {
        var brush = BuiltInBrushes.technicalPen
        brush.stroke.spacing = 0.1
        let path = BrushPath(points: [Vec2(0, 0), Vec2(10, 0)], widths: [1, 1], alphas: [1, 1])
        let dabs = BrushStroker.dabs(path, brush: brush, seed: 1)
        XCTAssertTrue((50 ... 51).contains(dabs.count), "\(dabs.count) stamps")
        XCTAssertEqual(dabs[1].center.x - dabs[0].center.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(dabs[0].direction, Vec2(1, 0))
    }

    func testTheSameSeedDrawsTheSameStroke() {
        let brush = BuiltInBrushes.splatter
        let path = BrushPath(points: [Vec2(0, 0), Vec2(5, 3), Vec2(9, -2)], widths: [1, 1, 1], alphas: [1, 1, 1])
        XCTAssertEqual(BrushStroker.dabs(path, brush: brush, seed: 7), BrushStroker.dabs(path, brush: brush, seed: 7))
        XCTAssertNotEqual(BrushStroker.dabs(path, brush: brush, seed: 7), BrushStroker.dabs(path, brush: brush, seed: 8))
        XCTAssertEqual(BrushStroker.dabs(path, brush: brush, seed: 7).count % 2, 0, "two stamps per step")
    }

    func testTapersThinBothEnds() {
        var brush = BuiltInBrushes.technicalPen
        brush.stroke = BrushStrokeSettings(spacing: 0.05, taperStart: 0.1, taperEnd: 0.1, taperSize: 1, taperOpacity: 1)
        let path = BrushPath(points: [Vec2(0, 0), Vec2(40, 0)], widths: [1, 1], alphas: [1, 1])
        let dabs = BrushStroker.dabs(path, brush: brush, seed: 0)
        let middle = dabs[dabs.count / 2]
        XCTAssertEqual(middle.radius, 1, accuracy: 1e-9)
        XCTAssertLessThan(dabs[0].radius, 0.01)
        XCTAssertLessThan(dabs[dabs.count - 1].opacity, 0.2)
    }

    func testFalloffFadesAlongTheStroke() {
        var brush = BuiltInBrushes.technicalPen
        brush.stroke.falloff = 1
        let dabs = BrushStroker.dabs(BrushPath(points: [Vec2(0, 0), Vec2(30, 0)], widths: [1, 1], alphas: [1, 1]), brush: brush, seed: 0)
        XCTAssertGreaterThan(dabs[0].opacity, dabs[dabs.count - 1].opacity * 3)
    }

    func testFlowScalesEveryStamp() {
        let dabs = BrushStroker.dabs(BrushPath(points: [Vec2(0, 0), Vec2(3, 0)], widths: [1, 1], alphas: [1, 1]),
                                     brush: BuiltInBrushes.airbrush, seed: 0)
        XCTAssertTrue(dabs.allSatisfy { abs($0.opacity - 0.08) < 1e-9 })
    }

    func testOverlappingStampsAddUpToTheStrokesOpacity() {
        var brush = BuiltInBrushes.technicalPen
        brush.stroke.spacing = 0.1
        let dabs = BrushStroker.dabs(BrushPath(points: [Vec2(0, 0), Vec2(10, 0)], widths: [1, 1], alphas: [0.5, 0.5]), brush: brush, seed: 0)
        // About ten stamps cover any point: together they reach the half opacity the stroke asked for.
        let stacked = 1 - pow(1 - dabs[20].opacity, 10)
        XCTAssertEqual(stacked, 0.5, accuracy: 1e-9)
        XCTAssertEqual(BrushStroker.stamped(1, spacing: 0.1), 1)
        XCTAssertEqual(BrushStroker.stamped(0.3, spacing: 1), 0.3, accuracy: 1e-12)
    }

    func testADotIsOneStamp() {
        let dot = BrushStroker.dabs(BrushPath(points: [Vec3(1, 2, 3)], widths: [0.5], alphas: [1]), brush: BuiltInBrushes.inkPen, seed: 0)
        XCTAssertEqual(dot.count, 1)
        XCTAssertEqual(dot[0].center, Vec3(1, 2, 3))
        XCTAssertEqual(dot[0].radius, 0.5)
    }

    func testAHugeStrokeIsCapped() {
        var brush = BuiltInBrushes.technicalPen
        brush.stroke.spacing = 0.02
        let path = BrushPath(points: [Vec2(0, 0), Vec2(1_000_000, 0)], widths: [1, 1], alphas: [1, 1])
        XCTAssertLessThanOrEqual(BrushStroker.dabs(path, brush: brush, seed: 0).count, BrushStroker.maximumDabs + 1)
    }

    // MARK: Pictures

    func testBuiltInPicturesAreDrawnAndDistinct() {
        var seen = Set<[UInt8]>()
        for image in BuiltInBrushImage.allCases {
            let picture = BrushImages.image(image)
            XCTAssertEqual(picture.width, image.isGrain ? BrushImages.grainSize : BrushImages.tipSize)
            XCTAssertGreaterThan(picture.coverage, 0.02, "\(image) is empty")
            XCTAssertTrue(seen.insert(picture.pixels).inserted, "\(image) repeats another picture")
        }
        let hard = BrushImages.image(.hardRound)
        XCTAssertEqual(hard.pixels[64 * 128 + 64], 255)
        XCTAssertEqual(hard.pixels[0], 0)
    }

    func testGrainsTile() {
        let noise = ValueNoise(seed: 3, cells: 32)
        for y in stride(from: 0.0, to: 1.0, by: 0.1) {
            XCTAssertEqual(noise.value(0, y), noise.value(1, y), accuracy: 1e-12)
        }
    }

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

    func testBigTipsAreBoxFilteredDown() {
        let big = GreyImage(width: 1300, height: 600) { _, _ in 1 }
        let fitted = big.fitting(512)
        XCTAssertLessThanOrEqual(max(fitted.width, fitted.height), 512)
        XCTAssertEqual(fitted.coverage, 1, accuracy: 1e-9)
    }

    // MARK: Keys and documents

    func testBrushKeysFollowSettingsNotPlaces() {
        var renamedID = BuiltInBrushes.pencil
        renamedID.id = "somewhere-else"
        XCTAssertEqual(BrushKey.key(for: renamedID), BrushKey.key(for: BuiltInBrushes.pencil))
        var edited = BuiltInBrushes.pencil
        edited.stroke.spacing = 0.5
        XCTAssertNotEqual(BrushKey.key(for: edited), BrushKey.key(for: BuiltInBrushes.pencil))
        XCTAssertTrue(BrushKey.imageKey(for: Data([1, 2, 3])).hasPrefix("brushes/"))
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

    func testLatencyKeepsAMedianAndATail() {
        var latency = StrokeLatency()
        XCTAssertNil(latency.summary)
        for value in 1 ... 100 {
            latency.add(Double(value))
        }
        latency.add(-1)
        latency.add(.nan)
        XCTAssertEqual(latency.samples.count, 100)
        XCTAssertEqual(latency.median, 50)
        XCTAssertEqual(latency.p95, 95)
        XCTAssertEqual(latency.summary, "50.0 ms median · 95.0 ms p95 · 100 samples")
        for _ in 0 ..< StrokeLatency.capacity {
            latency.add(10)
        }
        XCTAssertEqual(latency.samples.count, StrokeLatency.capacity)
        XCTAssertEqual(latency.median, 10)
    }
}
