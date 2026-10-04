import Foundation
import HmmPerception
@testable import LoweyCore
import XCTest

/// `observe` and `contact_sheet` on scenes built by hand, where the right answer is known.
final class PerceptionTests: XCTestCase {
    /// A camera 6 m back at eye height looking down −z, and whatever objects are given.
    private func document(_ objects: [SceneObject], camera position: Vec3 = Vec3(0, 1, 6)) -> Document {
        var scene = Scene(id: "s", name: "Perception")
        var camera = SceneObject(id: "cam", name: "Shot", kind: .camera, transform: Transform(position: position))
        camera[.fieldOfView] = .float(40)
        for object in objects + [camera] {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        scene.activeCamera = "cam"
        return Document(project: ProjectInfo(id: "p", name: "P"), scene: scene)
    }

    private func cube(_ id: String, at position: Vec3, size: Double = 1) -> SceneObject {
        SceneObject(id: ObjectID(raw: id), name: id.capitalized, kind: .primitive(.cube),
                    transform: Transform(position: position, scale: Vec3(size, size, size)))
    }

    func testAFloatingCubeIsNotGrounded() throws {
        let report = ShotObserver(document: document([cube("box", at: Vec3(0, 1, 0))])).observe(at: 0)
        let box = try XCTUnwrap(report.object(named: "Box"))
        XCTAssertFalse(box.grounded)
        XCTAssertEqual(box.gap, 100, accuracy: 0.5, "a metre up")
        let ground = try XCTUnwrap(report.checks.first { $0.name == "Ground" })
        XCTAssertEqual(ground.result, .fail)
        XCTAssertTrue(ground.detail.contains("floats 100 cm"), ground.detail)
        XCTAssertNotNil(ground.fix)
        XCTAssertTrue(report.summary.contains("Fails"), report.summary)
    }

    func testACubeOnTheGroundIsCentredAndFullyVisible() throws {
        let report = ShotObserver(document: document([cube("box", at: .zero)])).observe(at: 0)
        let box = try XCTUnwrap(report.object(named: "Box"))
        XCTAssertTrue(box.grounded)
        XCTAssertEqual(box.gap, 0, accuracy: 0.1)
        XCTAssertEqual(box.visible, 100, accuracy: 0.01)
        XCTAssertFalse(box.cutByFrame)
        XCTAssertEqual(box.mark, 1)
        XCTAssertEqual(box.box.midX, 0.5, accuracy: 0.02)
        XCTAssertEqual(box.distance, (Vec3(0, 0.5, 0) - Vec3(0, 1, 6)).length, accuracy: 0.01)
        XCTAssertGreaterThan(box.coverage, 2)
        XCTAssertNil(box.facing, "a cube has no front")
        XCTAssertEqual(report.frame.subject, "Box")
        XCTAssertFalse(report.frame.subjectDeclared)
        XCTAssertEqual(report.frame.thirds, "centre")
        XCTAssertEqual(report.frame.clutter, 1)
        XCTAssertEqual(report.frame.horizonTilt, 0, accuracy: 1e-9)
        XCTAssertEqual(report.camera, "Shot")
        XCTAssertGreaterThan(report.frame.emptyArea, 80)
        XCTAssertEqual(report.checks.first { $0.name == "Ground" }?.result, .pass)
        XCTAssertEqual(report.checks.first { $0.name == "Read" }?.result, .skipped, "no pixels")
    }

    func testCoverageMatchesTheProjectedArea() throws {
        // A 1 m cube 6 m away, front face 5.5 m from the eye: its face spans 1 / (2·5.5·tan 20°) of the frame height.
        let report = ShotObserver(document: document([cube("box", at: Vec3(0, 0.5, 0))], camera: Vec3(0, 1, 6))).observe(at: 0)
        let box = try XCTUnwrap(report.object(named: "Box"))
        let faceHeight = 1 / (2 * 5.5 * tan(20 * Double.pi / 180))
        XCTAssertEqual(box.box.height, faceHeight, accuracy: 0.03)
    }

    func testSomethingInFrontHidesWhatsBehind() throws {
        let front = cube("front", at: Vec3(0, 0, 2))
        let back = cube("back", at: Vec3(0, 0, -2), size: 1.4)
        let report = ShotObserver(document: document([front, back])).observe(at: 0)
        let hidden = try XCTUnwrap(report.object(named: "Back"))
        XCTAssertLessThan(hidden.visible, 40, "mostly behind the front cube")
        XCTAssertGreaterThan(hidden.visible, 10, "its top shows")
        // A smaller one right behind is out of sight, and still reported.
        let gone = ShotObserver(document: document([front, cube("back", at: Vec3(0, 0, -2))])).observe(at: 0)
        XCTAssertEqual(try XCTUnwrap(gone.object(named: "Back")).visible, 0)
        XCTAssertEqual(try XCTUnwrap(gone.object(named: "Back")).coverage, 0)
        XCTAssertEqual(try XCTUnwrap(report.object(named: "Front")).visible, 100, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.object(named: "Front")).mark, 1, "the biggest gets the first mark")
    }

    func testTheFrameEdgeCutsAndTangentsAreReported() throws {
        let cut = cube("cut", at: Vec3(3.4, 0, 0))
        let report = ShotObserver(document: document([cut, cube("hero", at: .zero)])).observe(at: 0, subject: "hero")
        XCTAssertTrue(try XCTUnwrap(report.object(named: "Cut")).cutByFrame)
        XCTAssertFalse(try XCTUnwrap(report.object(named: "Hero")).cutByFrame)
        XCTAssertEqual(report.frame.subject, "Hero")
        XCTAssertTrue(report.frame.subjectDeclared)
        // Move the cube so its right edge just touches the frame's right border.
        let camera = ShotObserver(document: document([])).camera(at: 0, aspect: 16.0 / 9.0)
        let halfWidth = tan(20 * Double.pi / 180) * 16 / 9 * 5.5
        let touching = cube("touch", at: Vec3(halfWidth - 0.5 - 0.005 * 2 * halfWidth, 0, 0))
        let tangent = ShotObserver(document: document([touching, cube("hero", at: .zero)])).observe(at: 0, subject: "hero")
        XCTAssertTrue(tangent.frame.tangents.contains("“Touch” right"), "\(tangent.frame.tangents), camera at \(camera.position)")
        XCTAssertEqual(tangent.checks.first { $0.name == "Frame" }?.result, .fail)
    }

    func testIntersectionsButNotResting() throws {
        let a = cube("a", at: .zero)
        let b = cube("b", at: Vec3(0.6, 0, 0))
        let resting = cube("top", at: Vec3(-3, 1, 0))
        let under = cube("under", at: Vec3(-3, 0, 0))
        let report = ShotObserver(document: document([a, b, resting, under], camera: Vec3(0, 2, 10))).observe(at: 0)
        XCTAssertEqual(try XCTUnwrap(report.object(named: "A")).intersects, ["B"])
        XCTAssertEqual(try XCTUnwrap(report.object(named: "B")).intersects, ["A"])
        XCTAssertEqual(try XCTUnwrap(report.object(named: "Top")).intersects, [], "resting on the cube under it")
        XCTAssertTrue(try XCTUnwrap(report.object(named: "Top")).grounded)
        XCTAssertTrue(try XCTUnwrap(report.checks.first { $0.name == "Ground" }).detail.contains("intersects"))
    }

    func testFacingTheCamera() throws {
        var blob = SceneObject(id: "blob", name: "Blob", kind: .primitive(.sphere), transform: Transform(position: .zero))
        blob[.rigStandard] = .enumeration("blob")
        var turned = blob
        turned.transform.rotation = Quat(angle: .pi / 2, axis: .unitY)
        let facing = ShotObserver(document: document([blob])).observe(at: 0)
        XCTAssertEqual(try XCTUnwrap(facing.object(named: "Blob")?.facing), 0, accuracy: 1)
        XCTAssertTrue(try XCTUnwrap(facing.object(named: "Blob")).isCharacter)
        let side = ShotObserver(document: document([turned])).observe(at: 0)
        XCTAssertEqual(try XCTUnwrap(side.object(named: "Blob")?.facing), 90, accuracy: 1)
    }

    func testPixelsGiveContrastAndPalette() throws {
        let doc = document([cube("box", at: .zero)])
        let observer = ShotObserver(document: doc)
        let plain = observer.observe(at: 0)
        let box = try XCTUnwrap(plain.object(named: "Box")).box
        // A white subject on a near-black frame where the cube is.
        let width = 160
        let height = 90
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let x = (Double(column) + 0.5) / Double(width)
                let y = (Double(row) + 0.5) / Double(height)
                let inside = x >= box.x && x <= box.maxX && y >= box.y && y <= box.maxY
                let value: UInt8 = inside ? 240 : 20
                bytes[(row * width + column) * 4] = value
                bytes[(row * width + column) * 4 + 1] = value
                bytes[(row * width + column) * 4 + 2] = inside ? 240 : 60
                bytes[(row * width + column) * 4 + 3] = 255
            }
        }
        let report = observer.observe(at: 0, pixels: ObservePixels(width: width, height: height, bytes: bytes))
        XCTAssertGreaterThan(try XCTUnwrap(report.frame.contrast), 60)
        XCTAssertEqual(report.checks.first { $0.name == "Read" }?.result, .pass)
        XCTAssertGreaterThan(try XCTUnwrap(report.frame.silhouetteSeparation), 60)
        let palette = try XCTUnwrap(report.frame.palette)
        XCTAssertEqual(palette.colors.first, RGBA(20.0 / 255, 20.0 / 255, 60.0 / 255).hex, "the background dominates")
        XCTAssertEqual(palette.colors.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(report.frame.light.subjectLightness), try XCTUnwrap(report.frame.light.worldLightness))
        // With the renderer's object buffer the subject's pixels come from it: a mask shifted off the cube's box
        // measures the background as the subject, so nothing stands out.
        var buffered = ObservePixels(width: width, height: height, bytes: bytes)
        buffered.objects = (0 ..< width * height).map { index in
            let x = (Double(index % width) + 0.5) / Double(width)
            let y = (Double(index / width) + 0.5) / Double(height)
            return x < 0.2 && y < 0.2 ? "box" : nil
        }
        let shifted = observer.observe(at: 0, pixels: buffered)
        XCTAssertLessThan(try XCTUnwrap(shifted.frame.contrast), 10, "measured where the buffer says the box is")
        // Flat grey: nothing reads.
        let grey = ObservePixels(width: 4, height: 4, bytes: [UInt8](repeating: 128, count: 64))
        let flat = observer.observe(at: 0, pixels: grey)
        XCTAssertEqual(try XCTUnwrap(flat.frame.contrast), 0, accuracy: 1e-9)
        XCTAssertEqual(flat.checks.first { $0.name == "Read" }?.result, .fail)
    }

    func testRasterCountsHiddenPixels() {
        var raster = CoverageRaster(width: 20, height: 20)
        let camera = ObserveCamera(position: Vec3(0, 0, 10), rotation: .identity, fieldOfView: 2, orthographicHeight: 2, aspect: 1)
        let near = ShotObserver.boxTriangles(Bounds(min: Vec3(-0.5, -0.5, 0), max: Vec3(0.5, 0.5, 1)))
        let far = ShotObserver.boxTriangles(Bounds(min: Vec3(-1, -1, -2), max: Vec3(1, 1, -1)))
        raster.draw(far, label: 0, camera: camera)
        raster.draw(near, label: 1, camera: camera)
        XCTAssertEqual(raster.soloCounts[0], 400, "fills the frame")
        XCTAssertEqual(raster.soloCounts[1], 100)
        XCTAssertEqual(raster.visibleCount(of: 1), 100)
        XCTAssertEqual(raster.visibleCount(of: 0), 300, "the near box hides a quarter")
        XCTAssertEqual(raster.label(x: 10, y: 10), 1)
        XCTAssertEqual(raster.label(x: -1, y: 0), -1)
    }

    func testDiagramsLookFromAboveTheFrontAndTheSide() throws {
        let box = Bounds(min: Vec3(-2, 0, -1), max: Vec3(2, 1, 1))
        let top = ObserveCamera.diagram(.top, fitting: box, aspect: 16.0 / 9.0)
        let far = try XCTUnwrap(top.project(Vec3(0, 0, -1)))
        let near = try XCTUnwrap(top.project(Vec3(0, 0, 1)))
        XCTAssertLessThan(far.y, near.y, "far side at the top")
        XCTAssertLessThan(try XCTUnwrap(top.project(Vec3(-2, 0, 0))).x, 0.5)
        let side = ObserveCamera.diagram(.side, fitting: box, aspect: 16.0 / 9.0)
        XCTAssertGreaterThan(try XCTUnwrap(side.project(Vec3(0, 0, -1))).x, try XCTUnwrap(side.project(Vec3(0, 0, 1))).x,
                             "from +x, −z is on the right")
        let front = ObserveCamera.diagram(.front, fitting: box, aspect: 16.0 / 9.0)
        XCTAssertLessThan(try XCTUnwrap(front.project(Vec3(0, 1, 0))).y, try XCTUnwrap(front.project(Vec3(0, 0, 0))).y)
        for camera in [top, side, front] {
            XCTAssertNotNil(camera.orthographicHeight)
            XCTAssertGreaterThan((camera.position - box.center).length, 10, "outside the set")
        }
        XCTAssertTrue(ObserveView.top.isDiagram)
        XCTAssertFalse(ObserveView.value.isDiagram)
    }

    func testTheTopDiagramShowsTheCameraInFront() throws {
        let doc = document([cube("box", at: .zero), cube("crate", at: Vec3(2, 0, -1), size: 0.6)])
        let observer = ShotObserver(document: doc)
        let report = observer.observe(at: 0)
        let top = observer.diagram(.top, at: 0, aspect: 16.0 / 9.0, report: report)
        XCTAssertEqual(top.marks.map(\.number).sorted(), [1, 2])
        let box = try XCTUnwrap(top.marks.first { $0.number == report.object(named: "Box")?.mark })
        let crate = try XCTUnwrap(top.marks.first { $0.number == report.object(named: "Crate")?.mark })
        XCTAssertGreaterThan(crate.x, box.x, "the crate is to the right")
        XCTAssertLessThan(crate.y, box.y, "and further back (up the diagram)")
        let glyph = try XCTUnwrap(top.shotCamera)
        XCTAssertGreaterThan(glyph.eye.y, box.y, "the camera stands in front, at the bottom")
        XCTAssertLessThan(glyph.left.x, glyph.right.x)
        XCTAssertLessThan(glyph.left.y, glyph.eye.y, "it looks up the diagram")
        let side = observer.diagram(.side, at: 0, aspect: 16.0 / 9.0, report: report)
        XCTAssertEqual(side.marks.count, 2)
    }

    func testAMarkPerObjectNumberedBiggestFirst() throws {
        let report = ShotObserver(document: document([cube("small", at: Vec3(1.5, 0, 0), size: 0.4), cube("big", at: .zero)])).observe(at: 0)
        XCTAssertEqual(report.objects.map(\.name), ["Big", "Small"])
        XCTAssertEqual(report.marks.map(\.number), [1, 2])
        let json = try XCTUnwrap(String(data: report.json(), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix("{\"data\""), "summary and data")
        XCTAssertTrue(json.contains("\"summary\""))
    }

    // MARK: Contact sheet

    private func movingDocument(easing: Easing, words: Bool) -> Document {
        var doc = document([cube("box", at: Vec3(-2, 0, 0), size: 0.5)], camera: Vec3(0, 1, 8))
        doc.scene.timeline = Timeline(fps: 24, duration: 4)
        doc.scene.timeline.tracks = [Track(id: "t", target: "box", property: .position, keyframes: [
            Keyframe(time: 0.5, value: .vec3(Vec3(-2, 0, 0)), easing: easing),
            Keyframe(time: 2.5, value: .vec3(Vec3(2, 0, 0)), easing: easing)
        ])]
        if words {
            doc.scene.timeline.audio = [AudioClip(id: "vo", role: .voiceover, name: "VO", file: "vo.m4a", start: 0, offset: 0, duration: 4,
                                                  sourceDuration: 4)]
            doc.scene.timeline.transcripts = [Transcript(clip: "vo", language: "en-US", words: [
                TranscriptWord(text: "Off", start: 0.5, end: 0.8), TranscriptWord(text: "it", start: 1.5, end: 1.6),
                TranscriptWord(text: "goes", start: 2.5, end: 2.9)
            ])]
        }
        return doc
    }

    func testAStraightGlideFailsMotion() throws {
        let sheet = ShotObserver(document: movingDocument(easing: .linear, words: false)).contactSheet(from: 0, to: 4)
        XCTAssertEqual(sheet.frames.count, 6)
        XCTAssertEqual(sheet.frames.first?.time, 0)
        XCTAssertEqual(sheet.frames.last?.time, 4)
        XCTAssertEqual(sheet.frames.first?.timecode, "0:00.00")
        let box = try XCTUnwrap(sheet.motion.first { $0.name == "Box" })
        XCTAssertGreaterThan(box.straightness, 0.99)
        XCTAssertEqual(box.holds, 1, "it stops at 2.5 s and holds")
        XCTAssertFalse(box.leavesFrame)
        XCTAssertLessThan(box.speedVariation, 0.12, "one speed")
        XCTAssertGreaterThan(box.pathLength, 0.4)
        XCTAssertNil(box.onWords)
        let motion = try XCTUnwrap(sheet.checks.first)
        XCTAssertEqual(motion.name, "Motion")
        XCTAssertEqual(motion.result, .fail)
        XCTAssertTrue(motion.detail.contains("ruler-straight"), motion.detail)
        XCTAssertTrue(sheet.summary.contains("Moving: Box"), sheet.summary)
        XCTAssertEqual(sheet.camera?.constantSpeed, false, "the camera holds")
    }

    func testEasedMovesLandOnWords() throws {
        let sheet = ShotObserver(document: movingDocument(easing: .easeInOut, words: true)).contactSheet(from: 0, to: 4, frames: 4)
        XCTAssertEqual(sheet.frames.count, 4)
        let box = try XCTUnwrap(sheet.motion.first)
        XCTAssertGreaterThan(box.speedVariation, 0.13, "eased")
        XCTAssertEqual(box.peaks.count, 1)
        XCTAssertEqual(try XCTUnwrap(box.peaks.first), 1.5, accuracy: 0.1, "peaks mid-move, on “it”")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(box.onWords), 2)
        XCTAssertNil(sheet.frames[0].word, "before the first word")
        XCTAssertEqual(sheet.frames[2].word, "goes")
        XCTAssertTrue(sheet.frames[2].note.contains("“goes”"), sheet.frames[2].note)
    }

    func testAConstantSpeedCameraMoveIsFlagged() throws {
        var doc = document([cube("box", at: .zero)])
        doc.scene.timeline = Timeline(fps: 24, duration: 4)
        doc.scene.timeline.tracks = [Track(id: "c", target: "cam", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(-3, 1, 6)), easing: .linear), Keyframe(time: 4, value: .vec3(Vec3(3, 1, 6)), easing: .linear)
        ])]
        let sheet = ShotObserver(document: doc).contactSheet(from: 0, to: 4)
        let camera = try XCTUnwrap(sheet.camera)
        XCTAssertTrue(camera.constantSpeed)
        XCTAssertEqual(camera.pathLength, 6, accuracy: 0.01)
        XCTAssertFalse(camera.easesIn)
        XCTAssertEqual(sheet.checks.first?.result, .fail)
        XCTAssertTrue(sheet.motion.isEmpty, "the box itself doesn't move")
    }

    func testFrameTimes() {
        XCTAssertEqual(ShotObserver.frameTimes(from: 1, to: 3, count: 3), [1, 2, 3])
        XCTAssertEqual(ShotObserver.frameTimes(from: 1, to: 1, count: 6), [1])
        XCTAssertEqual(ShotObserver.timecode(61.5, fps: 24), "1:01.12")
    }
}
