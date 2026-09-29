import Foundation
@testable import LoweyCore
import XCTest

/// v1.4: a neutral neutral face, tracked hands, rest pose, body tracking, media cards, picture-side face channels.
final class PolishTests: XCTestCase {
    private func blob() throws -> (Document, ObjectID) {
        var ids = IDFactory.sequential("blob")
        let build = BlobCharacter.build(.hesham, ids: &ids)
        var document = makeDocument()
        let root = try XCTUnwrap(build.fragment.roots.first)
        _ = try EditCommand.insert(build.fragment, parent: nil, index: nil).apply(to: &document)
        return (document, root)
    }

    private func role(_ name: String, in scene: Scene, under root: ObjectID) -> ObjectID? {
        scene.subtree(of: root).first { scene.objects[$0]?[.faceRole]?.stringValue == name }
    }

    func testTheNeutralFaceIsLevelAndSymmetric() throws {
        // Brows: both ends at the same height.
        let brow = BlobRig.browRecipe(side: 1, raise: 0, angle: 0, arch: 0, origin: .zero)
        let browPoints = try XCTUnwrap(brow.strokes.first?.points)
        XCTAssertEqual(try XCTUnwrap(browPoints.first).y, try XCTUnwrap(browPoints.last).y, accuracy: 1e-3, "level brows")
        // Eyes: upright ovals (the top of the eye is over its middle).
        let eye = BlobRig.eyeOutline(open: 1, happy: 0, wide: 0, side: -1)
        let top = try XCTUnwrap(eye.max { $0.y < $1.y })
        XCTAssertEqual(top.x, 0, accuracy: 1e-6, "no tilt")
        // Mouth: a short symmetric line, no smirk curl.
        let layers = BlobRig.mouthLayers(BlobRig.MouthPose.named("X"), origin: .zero)
        XCTAssertNil(layers["mouth.curl"])
        let line = try XCTUnwrap(layers["mouth.lips"]?.strokes.first?.points)
        XCTAssertEqual(try XCTUnwrap(line.first).y, try XCTUnwrap(line.last).y, accuracy: 1e-4, "both corners at the same height")
        XCTAssertEqual(try XCTUnwrap(line.first).x, try -(XCTUnwrap(line.last).x), accuracy: 1e-4, "centred")
        // The smirk lives on as the smug face.
        XCTAssertNotNil(BlobRig.mouthLayers(BlobRig.MouthPose.named("smirk"), origin: .zero)["mouth.curl"])
        XCTAssertEqual(FaceExpression.smug.values[.mouth], .enumeration("smirk"))
        XCTAssertEqual(FaceExpression.neutral.values[.mouth], .enumeration("X"))
        // A freshly built character rests on it: nothing is redrawn at rest.
        let (document, root) = try blob()
        let animated = Animator.evaluate(document, at: 0.5).animated
        for part in ["eye.L", "eye.R", "brow.L", "brow.R", "mouth.lips", "mouth.curl"] {
            XCTAssertFalse(try animated.contains(XCTUnwrap(role(part, in: document.scene, under: root))), "\(part) stays as built")
        }
    }

    func testTrackedHandsRaiseTheHandsAndTheArmsFollow() throws {
        let (document, root) = try blob()
        let hand = try XCTUnwrap(role("hand.R", in: document.scene, under: root))
        let arm = try XCTUnwrap(document.scene.subtree(of: root).first { document.scene.objects[$0]?.name == "Arm R" })
        let rest = Animator.evaluate(document, at: 0)
        let restY = rest.scene.worldTransform(of: hand).position.y
        let raised = Animator.evaluate(document, at: 0, overrides: [root: [.handRightY: .float(1), .handRightX: .float(0.5)]])
        XCTAssertGreaterThan(raised.scene.worldTransform(of: hand).position.y, restY + 0.3, "the hand goes up")
        XCTAssertTrue(raised.animated.contains(arm), "the arm bends to reach it")
        let other = try XCTUnwrap(role("hand.L", in: document.scene, under: root))
        XCTAssertEqual(raised.scene.worldTransform(of: other).position.y, rest.scene.worldTransform(of: other).position.y, accuracy: 1e-9,
                       "the other hand stays")
        XCTAssertTrue(PropertyKey.faceChannels.contains(.handRightY), "hands are performed and recorded with the face")
    }

    func testRestPoseMakesYourRelaxedPoseNeutral() {
        var rest = RestPose()
        XCTAssertFalse(rest.isSet)
        rest.capture([.headPitch: -12, .headYaw: 4, .brows: 0.2, .blinkLeft: 0.1, .jawOpen: 0.05])
        let now = rest.apply([.headPitch: -12, .headYaw: 14, .brows: 0.9, .blinkLeft: 1, .jawOpen: 0.6])
        XCTAssertEqual(now[.headPitch] ?? 9, 0, accuracy: 1e-9, "looking from below is level")
        XCTAssertEqual(now[.headYaw] ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(now[.brows] ?? 0, 0.7, accuracy: 1e-9)
        XCTAssertEqual(now[.blinkLeft], 1, "blinks are absolute")
        XCTAssertEqual(now[.jawOpen], 0.6, "the jaw too")
        XCTAssertEqual(rest.apply([.smile: 5])[.smile], 5, "keys not captured pass through")
    }

    func testBodyTrackingByScreenSide() {
        typealias Point = BodySolver.Joint
        let leftShoulder = Point(x: 0.4, y: 0.55, confidence: 0.9)
        let rightShoulder = Point(x: 0.6, y: 0.55, confidence: 0.9)
        // Hands down by the sides: at rest.
        let down = BodySolver.channels(BodySolver.Arm(shoulder: leftShoulder, wrist: Point(x: 0.36, y: 0.25, confidence: 0.9)),
                                       BodySolver.Arm(shoulder: rightShoulder, wrist: Point(x: 0.64, y: 0.25, confidence: 0.9)))
        XCTAssertEqual(down[.handLeftY] ?? 1, 0, accuracy: 0.05)
        XCTAssertEqual(down[.handRightY] ?? 1, 0, accuracy: 0.05)
        // The hand on the right of the picture goes up high, whatever the tracker called that arm.
        let wave = BodySolver.channels(BodySolver.Arm(shoulder: rightShoulder, wrist: Point(x: 0.66, y: 0.75, confidence: 0.9)),
                                       BodySolver.Arm(shoulder: leftShoulder, wrist: Point(x: 0.36, y: 0.25, confidence: 0.9)))
        XCTAssertGreaterThan(wave[.handRightY] ?? 0, 0.8)
        XCTAssertEqual(wave[.handLeftY] ?? 1, 0, accuracy: 0.05)
        // Out of sight (hands in the lap): rest.
        let unseen = BodySolver.channels(BodySolver.Arm(shoulder: leftShoulder, wrist: Point(x: 0.4, y: 0.9, confidence: 0.05)),
                                         BodySolver.Arm(shoulder: rightShoulder, wrist: nil))
        XCTAssertEqual(unseen[.handLeftY], 0)
        XCTAssertEqual(unseen[.handRightY], 0)
    }

    func testFaceSidesComeFromThePictureNotTheLabels() {
        func eye(_ x: Double) -> [Vec2] { [Vec2(x - 0.08, 0.6), Vec2(x + 0.08, 0.6), Vec2(x, 0.63), Vec2(x, 0.57)] }
        func face(noseX: Double, leftLabelX: Double, rightLabelX: Double, closedX: Double? = nil) -> FaceLandmarks {
            func maybeClosed(_ x: Double) -> [Vec2] {
                x == closedX ? [Vec2(x - 0.08, 0.6), Vec2(x + 0.08, 0.6), Vec2(x, 0.601), Vec2(x, 0.599)] : eye(x)
            }
            return FaceLandmarks(
                leftEye: maybeClosed(leftLabelX), rightEye: maybeClosed(rightLabelX),
                leftBrow: [Vec2(0.25, 0.72), Vec2(0.35, 0.72)], rightBrow: [Vec2(0.65, 0.72), Vec2(0.75, 0.72)],
                outerLips: [Vec2(0.38, 0.25), Vec2(0.62, 0.25), Vec2(0.5, 0.28), Vec2(0.5, 0.22)],
                innerLips: [Vec2(0.42, 0.25), Vec2(0.58, 0.25), Vec2(0.5, 0.255), Vec2(0.5, 0.245)],
                nose: [Vec2(noseX, 0.42)]
            )
        }
        let neutral = FaceSolver.measure(face(noseX: 0.5, leftLabelX: 0.3, rightLabelX: 0.7))!
        // Labels swapped (a mirrored picture): the eye on the left of the picture is still `blinkLeft`.
        let winkLeft = FaceSolver.channels(face(noseX: 0.5, leftLabelX: 0.7, rightLabelX: 0.3, closedX: 0.3), neutral: neutral)
        XCTAssertGreaterThan(winkLeft[.blinkLeft] ?? 0, 0.8)
        XCTAssertLessThan(winkLeft[.blinkRight] ?? 1, 0.2)
        // The nose sliding to the picture's right: turned that way.
        let turned = FaceSolver.channels(face(noseX: 0.58, leftLabelX: 0.3, rightLabelX: 0.7), neutral: neutral)
        let straight = FaceSolver.channels(face(noseX: 0.5, leftLabelX: 0.3, rightLabelX: 0.7), neutral: neutral)
        XCTAssertGreaterThan((turned[.headYaw] ?? 0) - (straight[.headYaw] ?? 0), 10)
        XCTAssertEqual(straight[.headRoll] ?? 1, 0, accuracy: 1e-9, "level eyes, no tilt")
    }

    func testMediaCardsShowTheRightFrame() throws {
        let still = CardRecipe(image: "chart.png", aspect: 1.5)
        XCTAssertEqual(still.frameKey(at: 12), "chart.png")
        XCTAssertEqual(still.bounds.min.y, 0, "base-centred")
        XCTAssertEqual(still.bounds.size.x, 1.5 + 2 * still.border, accuracy: 1e-9)
        let clip = CardRecipe(video: "clip.mov", videoStart: 2, videoDuration: 3)
        XCTAssertEqual(clip.frameKey(at: 0), VideoFrameKey.make(file: "clip.mov", time: 0), "before it starts: its first frame")
        XCTAssertEqual(clip.frameKey(at: 3.5), VideoFrameKey.make(file: "clip.mov", time: 1.5))
        let last = try XCTUnwrap(try VideoFrameKey.parse(XCTUnwrap(clip.frameKey(at: 30)))).time
        XCTAssertLessThan(last, 3, "after the end: holds the last frame")
        var looping = clip
        looping.videoLoop = true
        XCTAssertEqual(looping.frameKey(at: 6.5), VideoFrameKey.make(file: "clip.mov", time: 1.5))
        // A card is a real object: it has a surface (a colour), it's not an overlay, and it survives saving.
        let kind = ObjectKind.card(clip)
        XCTAssertTrue(kind.hasSurface)
        XCTAssertFalse(kind.isOverlay)
        let data = try JSONEncoder().encode(kind)
        XCTAssertEqual(try JSONDecoder().decode(ObjectKind.self, from: data), kind)
        XCTAssertNotNil(SceneBounds(library: LibraryManifest()).localBounds(of: SceneObject(id: "card", name: "Card", kind: kind)))
    }
}
