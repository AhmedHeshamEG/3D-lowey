@testable import LoweyCore
import XCTest

final class PostTests: XCTestCase {
    func testPostSettingsLiveInTheLookAndOldLooksOpen() throws {
        var look = Look.default
        XCTAssertTrue(look.post.isNeutral)
        look.post = PostSettings.Preset.cinematic.settings
        XCTAssertFalse(look.post.isNeutral)
        let data = try LoweyJSON.encode(look)
        XCTAssertEqual(try LoweyJSON.decode(Look.self, from: data), look)
        // A Phase 2 look (no "post") opens with post-processing off.
        var plain = Look.default
        plain.post = PostSettings()
        let old = try LoweyJSON.encode(plain)
        XCTAssertFalse(String(bytes: old, encoding: .utf8)!.contains("\"post\""))
        XCTAssertEqual(try LoweyJSON.decode(Look.self, from: old).post, PostSettings())
        for preset in PostSettings.Preset.allCases {
            XCTAssertEqual(preset.settings.isNeutral, preset == .clean, preset.title)
        }
        XCTAssertTrue(PostSettings(outline: 0.5, depthOfField: false).needsDepth)
    }

    func testScreenEffectsEnvelopesAreDeterministic() {
        let effects = [
            ScreenEffect(id: "f", kind: .flash, start: 1, strength: 1, color: RGBA(1, 0.9, 0.8)),
            ScreenEffect(id: "s", kind: .shake, start: 2, duration: 1),
            ScreenEffect(id: "g", kind: .glitch, start: 4, duration: 1),
            ScreenEffect(id: "l", kind: .speedLines, start: 6, duration: 1),
            ScreenEffect(id: "z", kind: .zoomBlur, start: 8, duration: 1)
        ]
        XCTAssertTrue(ScreenEffects.state(at: 0.5, effects: effects, fps: 30).isEmpty)
        let flash = ScreenEffects.state(at: 1, effects: effects, fps: 30)
        XCTAssertEqual(flash.flash, 1, accuracy: 1e-9)
        XCTAssertEqual(flash.flashColor, RGBA(1, 0.9, 0.8))
        XCTAssertLessThan(ScreenEffects.state(at: 1.2, effects: effects, fps: 30).flash, 0.2)
        let shake = ScreenEffects.state(at: 2.3, effects: effects, fps: 30)
        XCTAssertNotEqual(shake.shake, .zero)
        XCTAssertLessThan(abs(shake.shake.x), 0.04)
        XCTAssertEqual(shake, ScreenEffects.state(at: 2.3, effects: effects, fps: 30), "same time, same shake")
        XCTAssertEqual(ScreenEffects.state(at: 3, effects: effects, fps: 30).shake.x, 0, accuracy: 1e-9, "decays to rest")
        let glitchFrames = (0 ..< 30).map { ScreenEffects.state(at: 4 + Double($0) / 30, effects: effects, fps: 30).glitch }
        XCTAssertTrue(glitchFrames.contains { $0 > 0.5 })
        XCTAssertTrue(glitchFrames.contains(0), "it stutters")
        XCTAssertEqual(ScreenEffects.state(at: 6.5, effects: effects, fps: 30).speedLines, 1, accuracy: 1e-9)
        XCTAssertEqual(ScreenEffects.state(at: 8.5, effects: effects, fps: 30).zoomBlur, 1, accuracy: 1e-9)
        var timeline = Timeline()
        timeline.effects = effects
        XCTAssertEqual(timeline.contentEnd, 9)
    }

    func testTransitionsAreCentredOnTheirCut() throws {
        var timeline = Timeline()
        timeline.cuts = [
            CameraCut(time: 0, camera: "a"),
            CameraCut(time: 2, camera: "b", transition: TransitionSpec(kind: .fade, duration: 1)),
            CameraCut(time: 5, camera: "c")
        ]
        XCTAssertNil(timeline.transition(at: 1.4, fallback: nil))
        let middle = try XCTUnwrap(timeline.transition(at: 2, fallback: nil))
        XCTAssertEqual(middle.from, "a")
        XCTAssertEqual(middle.to, "b")
        XCTAssertEqual(middle.progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(timeline.transition(at: 1.6, fallback: nil)?.progress ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertNil(timeline.transition(at: 5, fallback: nil), "plain cut")
        // The first cut can hand over from the scene's own camera.
        timeline.cuts[0].transition = TransitionSpec(kind: .wipe, duration: 0.5)
        XCTAssertEqual(timeline.transition(at: 0.1, fallback: "main")?.from, "main")
        let data = try LoweyJSON.encode(timeline)
        XCTAssertEqual(try LoweyJSON.decode(Timeline.self, from: data), timeline)
    }

    func testMatchCutPutsTheSubjectInTheSameSpot() {
        let subject = Vec3(2, 1, -3)
        let camera = Vec3(0, 1.5, 6)
        for point in [(0.0, 0.0), (0.5, 0.3), (-0.6, -0.2)] {
            let rotation = MatchCut.aim(cameraAt: camera, subject: subject, framePoint: point, fieldOfView: 50, aspect: 16 / 9)
            let projected = OverlayLayout.project(subject, camera: Transform(position: camera, rotation: rotation), fieldOfView: 50, aspect: 16 / 9)
            XCTAssertEqual(projected?.0 ?? 9, point.0, accuracy: 0.03)
            XCTAssertEqual(projected?.1 ?? 9, point.1, accuracy: 0.03)
        }
    }
}
