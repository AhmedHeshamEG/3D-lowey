@testable import LoweyCore
import XCTest

final class TextOverlayTests: XCTestCase {
    func testBlockFontMeshesAndMeasures() {
        let recipe = TextRecipe(text: "Enigma?", size: 1, depth: 0.2, alignment: .center)
        XCTAssertTrue(recipe.coreMeshable)
        let mesh = BlockFont.mesh(for: recipe)
        XCTAssertFalse(mesh.isEmpty)
        let bounds = mesh.bounds!
        XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-5, "stands on the ground")
        XCTAssertEqual(bounds.max.y, 1, accuracy: 1e-5, "letters are `size` tall")
        XCTAssertEqual(bounds.center.x, 0, accuracy: 0.01, "centred")
        XCTAssertEqual(bounds.max.z - bounds.min.z, 0.2, accuracy: 1e-5)
        // Low-poly: runs are merged, so a letter is a few dozen triangles.
        XCTAssertLessThan(mesh.triangleCount / 7, 150)
        XCTAssertFalse(TextRecipe(text: "إنيجما").coreMeshable, "Arabic goes through the system font")
        XCTAssertFalse(TextRecipe(text: "Hi", style: .rounded).coreMeshable)
        XCTAssertTrue(TextRecipe(text: "Two\nlines").coreMeshable)
        let two = BlockFont.mesh(for: TextRecipe(text: "A\nB", alignment: .left)).bounds!
        XCTAssertGreaterThan(two.max.y, 2)
        XCTAssertEqual(two.min.x, 0, accuracy: 1e-5)
        XCTAssertEqual(BlockFont.glyphs.values.filter { $0.count != 7 || $0.contains { $0.count != 5 } }.count, 0, "every glyph is 5×7")
        let estimate = TextRecipe(text: "Hello", size: 2).estimatedBounds
        XCTAssertGreaterThan(estimate.size.x, 5)
        // Bounds, 3D export and object kinds round-trip.
        let object = SceneObject(id: "t", name: "Title", kind: .text(recipe))
        XCTAssertNotNil(SceneBounds().localBounds(of: object))
        XCTAssertTrue(object.kind.hasSurface)
    }

    func testOverlayPlacementProjectionAndOrder() throws {
        var document = makeDocument()
        var title = SceneObject(id: "o1", name: "X", kind: .overlay(.default(.cross)),
                                transform: Transform(position: Vec3(0.5, 0.5, 1), rotation: Quat(angle: .pi / 2, axis: .unitZ), scale: Vec3(2, 2, 1)))
        title[.opacity] = .float(0.5)
        var label = SceneObject(id: "o2", name: "Label", kind: .overlay(OverlayRecipe(shape: .label, text: "Paper", anchor: "a")),
                                transform: Transform(position: Vec3(0, 0.1, 0)))
        label[.reveal] = .float(0.5)
        let hidden = SceneObject(id: "o3", name: "Gone", kind: .overlay(.default(.star)), properties: [.opacity: .float(0)])
        for object in [title, label, hidden] {
            document.scene.objects[object.id] = object
            document.scene.roots.append(object.id)
        }
        let camera = Transform(position: Vec3(1, 0, 10))
        let placements = OverlayLayout.placements(in: document.scene, palette: document.palette, width: 1920, height: 1080) { point in
            OverlayLayout.project(point, camera: camera, fieldOfView: 50, aspect: 16 / 9)
        }
        XCTAssertEqual(placements.map(\.id), ["o2", "o1"], "back to front by layer; invisible skipped")
        let x = placements[1]
        XCTAssertEqual(x.center.x, 1440, accuracy: 1e-6)
        XCTAssertEqual(x.center.y, 270, accuracy: 1e-6)
        XCTAssertEqual(x.unit, 108)
        XCTAssertEqual(x.angle, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(x.opacity, 0.5)
        XCTAssertEqual(x.color, OverlayRecipe.Shape.cross.defaultColor)
        // The label follows object A (at x = 1): straight ahead of the camera → frame centre, plus its offset.
        let anchored = placements[0]
        XCTAssertEqual(anchored.center.x, 960, accuracy: 1e-6)
        XCTAssertEqual(anchored.center.y, 540 - 0.1 * 540, accuracy: 1e-6)
        XCTAssertEqual(anchored.reveal, 0.5)
        XCTAssertNil(OverlayLayout.project(Vec3(0, 0, 20), camera: camera, fieldOfView: 50, aspect: 1), "behind the camera")
        let back = OverlayLayout.framePosition(pixel: SIMD2(1440, 270), width: 1920, height: 1080)
        XCTAssertEqual(back.0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(back.1, 0.5, accuracy: 1e-9)
        // Overlays are objects: they save, and presets animate them in the frame.
        let data = try LoweyJSON.encode(document.scene)
        XCTAssertEqual(try LoweyJSON.decode(Scene.self, from: data), document.scene)
        let spin = PresetBuilder.keys(.spin, for: title, at: 0, options: PresetOptions(.spin))
        let end = try XCTUnwrap(spin.first?.2.last?.value.quatValue)
        XCTAssertEqual(end.act(Vec3(0, 0, 1)).z, 1, accuracy: 1e-6, "overlays spin in the frame (around Z)")
        let typed = PresetBuilder.keys(.typewriter, for: label, at: 1, options: PresetOptions(.typewriter))
        XCTAssertEqual(typed.first?.1, .reveal)
        XCTAssertEqual(typed.first?.2.map(\.value), [.float(0), .float(1)])
    }

    func testParticlesAreDeterministicAndBehave() {
        let fire = ParticleRecipe.preset(.fire, seed: 3)
        let a = ParticleSimulator.particles(fire, at: 2)
        let b = ParticleSimulator.particles(fire, at: 2)
        XCTAssertEqual(a, b, "same time, same particles")
        XCTAssertGreaterThan(a.count, 30)
        XCTAssertTrue(a.allSatisfy { $0.life >= 0 && $0.life <= 1 && $0.position.y > -0.5 }, "fire rises")
        XCTAssertEqual(ParticleSimulator.particles(fire, at: 0.0).count, 1, "nothing before the emitter starts but the first")
        XCTAssertLessThan(ParticleSimulator.particles(fire, at: 2, emission: { _ in 0.3 }).count, a.count / 2)
        XCTAssertTrue(ParticleSimulator.particles(fire, at: 2, emission: { _ in 0 }).isEmpty)
        XCTAssertTrue(ParticleSimulator.particles(fire, at: 2, amount: 0).isEmpty)
        let rain = ParticleSimulator.particles(.preset(.rain), at: 3)
        XCTAssertTrue(rain.allSatisfy { $0.velocity.y < 0 }, "rain falls")
        XCTAssertLessThanOrEqual(ParticleSimulator.particles(.preset(.rain), at: 3, amount: 100).count, ParticleSimulator.maxParticles)
        var boom = ParticleRecipe.preset(.explosion)
        boom.burstTime = 1
        XCTAssertTrue(ParticleSimulator.particles(boom, at: 0.5).isEmpty, "before the burst")
        let burst = ParticleSimulator.particles(boom, at: 1.2)
        XCTAssertEqual(burst.count, 220)
        XCTAssertTrue(ParticleSimulator.particles(boom, at: 4).isEmpty, "all gone")
        let confetti = ParticleSimulator.particles(.preset(.confetti), at: 0.5)
        XCTAssertGreaterThan(Set(confetti.map(\.color)).count, 3, "many colours")
        XCTAssertEqual(fire.color(at: 0), fire.colors[0])
        XCTAssertEqual(fire.color(at: 1), fire.colors.last)
        for preset in ParticleRecipe.Preset.allCases {
            let recipe = ParticleRecipe.preset(preset)
            XCTAssertFalse(ParticleSimulator.bounds(recipe).size.x.isNaN)
            let particles = ParticleSimulator.particles(recipe, at: recipe.burst ? 0.3 : 2)
            XCTAssertFalse(particles.isEmpty, "\(preset) emits")
            XCTAssertTrue(particles.allSatisfy { $0.position.x.isFinite && $0.size >= 0 }, "\(preset) stays finite")
        }
    }

    func testParticleMeshesAreFewLowPolyBands() {
        for preset in ParticleRecipe.Preset.allCases {
            let recipe = ParticleRecipe.preset(preset)
            let particles = ParticleSimulator.particles(recipe, at: recipe.burst ? 0.4 : 2.5)
            let bands = ParticleMesher.bands(particles, recipe: recipe)
            XCTAssertFalse(bands.isEmpty, preset.title)
            XCTAssertLessThanOrEqual(bands.count, ParticleMesher.maxBands)
            let triangles = bands.reduce(0) { $0 + $1.mesh.triangleCount }
            XCTAssertLessThanOrEqual(triangles, particles.count * 8, "8 triangles a particle at most")
            XCTAssertTrue(bands.allSatisfy { $0.opacity > 0 && $0.opacity <= 1 && !$0.mesh.positions.contains { !$0.x.isFinite } })
        }
        XCTAssertTrue(ParticleMesher.bands([], recipe: .preset(.fire)).isEmpty)
    }

    func testCaptionsPagesKaraokeAndSubtitles() {
        let texts = ["This", "is", "a", "German", "army", "message", "from", "1941.", "Encrypted", "with", "Enigma."]
        var words: [TimelineWord] = []
        var t = 0.5
        for (index, text) in texts.enumerated() {
            words.append(TimelineWord(clip: "vo", index: index, text: text, start: t, end: t + 0.3))
            t += text.hasSuffix(".") ? 1.0 : 0.35
        }
        let pages = Captions.pages(words, maxCharacters: 16, maxLines: 2)
        XCTAssertEqual(pages.first?.lines.map { $0.map(\.text) }, [["This", "is", "a", "German"], ["army", "message"]])
        XCTAssertEqual(pages.last?.text, "Encrypted with\nEnigma.")
        XCTAssertTrue(pages.contains { $0.text == "from 1941." }, "a sentence end closes the page")
        for (a, b) in zip(pages, pages.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start + 1e-9, "pages never overlap")
        }
        let now = Captions.page(at: words[4].start + 0.1, in: pages)
        XCTAssertEqual(now?.page.words[now?.word ?? 0].text, "army")
        XCTAssertNil(Captions.page(at: 0.1, in: pages))
        let srt = Captions.srt(Array(pages.prefix(1)))
        XCTAssertTrue(srt.hasPrefix("1\n00:00:00,500 --> 00:00:"))
        XCTAssertTrue(srt.contains("This is a German\narmy message\n"))
        XCTAssertTrue(Captions.vtt(pages).hasPrefix("WEBVTT\n\n00:00:00.500 --> "))
        XCTAssertEqual(Captions.timestamp(3725.042, separator: ","), "01:02:05,042")
    }
}
