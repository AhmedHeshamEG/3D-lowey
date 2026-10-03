import Foundation
@testable import LoweyCore
import XCTest

final class FrameRateTests: XCTestCase {
    /// A document with a blob-like character (rigStandard), a prop and a camera, the project on ones at 24 fps.
    private func document(look: String) -> Document {
        var document = makeDocument()
        document.scene["a"]?[.rigStandard] = .enumeration("blob")
        document.scene["camera"] = SceneObject(id: "camera", name: "Camera", kind: .camera)
        document.scene.roots.append("camera")
        document.scene.timeline.fps = 24
        document.project.look.presetID = look
        return document
    }

    func testFoursQuantise() {
        XCTAssertEqual(Stepping.onFours.quantize(7.0 / 24, fps: 24), 4.0 / 24, accuracy: 1e-12)
        XCTAssertEqual(Stepping(name: "fours"), .onFours)
        XCTAssertEqual(Stepping.onFours.name, "fours")
    }

    func testComicPutsCharactersOnTwosAndKeepsTheCameraOnOnes() {
        let comic = FrameRates(document(look: LookPreset.comic.id))
        let scene = document(look: LookPreset.comic.id).scene
        XCTAssertEqual(comic.stepping(for: "a", in: scene, at: 0), .onTwos, "a character in the Comic Look")
        XCTAssertEqual(comic.stepping(for: "b", in: scene, at: 0), .onTwos, "a character's part steps with it")
        XCTAssertEqual(comic.stepping(for: "c", in: scene, at: 0), .onOnes, "props follow the project")
        XCTAssertEqual(comic.stepping(for: "camera", in: scene, at: 0), .onOnes)
        let ink = FrameRates(document(look: LookPreset.ink.id))
        XCTAssertEqual(ink.stepping(for: "a", in: scene, at: 0), .onOnes)
    }

    func testOwnFrameRateWinsAndCanBeKeyed() {
        var doc = document(look: LookPreset.comic.id)
        doc.scene["a"]?[.stepping] = .enumeration("fours")
        XCTAssertEqual(FrameRates(doc).stepping(for: "b", in: doc.scene, at: 0), .onFours)
        doc.scene.timeline.tracks.append(Track(id: "rate", target: "a", property: .stepping, keyframes: [
            Keyframe(time: 0, value: .enumeration("threes"), easing: .step),
            Keyframe(time: 1, value: .enumeration("ones"), easing: .step)
        ]))
        let rates = FrameRates(doc)
        XCTAssertEqual(rates.stepping(for: "a", in: doc.scene, at: 0.5), .onThrees)
        XCTAssertEqual(rates.stepping(for: "a", in: doc.scene, at: 1.5), .onOnes)
        XCTAssertEqual(rates.sampleTime(5.0 / 24, for: "a", in: doc.scene), 3.0 / 24, accuracy: 1e-12)
    }

    func testAnimatorSamplesStepped() {
        var doc = document(look: LookPreset.comic.id)
        doc.scene.timeline.tracks.append(Track(id: "move", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(.zero), easing: .linear), Keyframe(time: 1, value: .vec3(Vec3(24, 0, 0)))
        ]))
        let atOne = Animator.evaluate(doc, at: 1.0 / 24).scene.objects["a"]?.transform.position.x ?? -1
        let atTwo = Animator.evaluate(doc, at: 2.0 / 24).scene.objects["a"]?.transform.position.x ?? -1
        XCTAssertEqual(atOne, 0, accuracy: 1e-9, "held on twos")
        XCTAssertEqual(atTwo, 2, accuracy: 1e-9)
    }
}
