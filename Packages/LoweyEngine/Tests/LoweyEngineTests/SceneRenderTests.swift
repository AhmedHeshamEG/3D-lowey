import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// What 1.x drew, drawn by LoweyRender 2: the sample sets, every lighting preset, the narrated story's finish, lens
/// blur and ink lines, glow, particles, characters, pictures on cards and every overlay shape. Frames are attached.
@MainActor
final class SceneRenderTests: XCTestCase {
    private func attach(_ image: CGImage, name: String) {
        GoldenImage().attach(image, name: name)
    }

    private func frame(_ document: Document, at time: Double = 0, framing: Framing = .landscape, longSide: Int = 480,
                       still: ((String) -> CGImage?)? = nil) async throws -> CGImage {
        let session = try TestDocuments.session(document)
        if let still { session.stillImage = still }
        return try await session.image(at: time, framing: framing, longSide: longSide)
    }

    // MARK: Sample sets and lighting

    func testEnigmaSetsRenderInBothFramings() async throws {
        let (info, scenes) = try EnigmaSample.build()
        for (index, scene) in scenes.enumerated() {
            for (framing, label) in [(Framing.landscape, "16x9"), (.portrait, "9x16")] {
                let image = try await frame(Document(project: info, scene: scene), framing: framing, longSide: 960)
                let size = framing.pixelSize(longSide: 960)
                XCTAssertEqual(image.width, size.width)
                XCTAssertEqual(image.height, size.height)
                XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.05, "set \(index + 1) \(label) looks blank")
                attach(image, name: "enigma-\(index + 1)-\(label)")
            }
        }
    }

    func testEveryLightingPresetRenders() async throws {
        let (info, scenes) = try EnigmaSample.build()
        var scene = scenes[2]
        var previous: CGImage?
        for preset in LightingPreset.allCases {
            scene.look = info.look.applying(preset)
            let image = try await frame(Document(project: info, scene: scene), framing: .square, longSide: 512)
            attach(image, name: "preset-\(preset.rawValue)")
            XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.02, "\(preset) looks blank")
            if let previous { XCTAssertGreaterThan(ImageChecks.difference(previous, image), 0.002, "\(preset) changes the light") }
            previous = image
        }
    }

    // MARK: The finish

    func testNarratedStoryRendersWithPostOverlaysAndCaptions() async throws {
        let document = try TestDocuments.story()
        func start(_ word: String) throws -> Double {
            try XCTUnwrap(document.scene.timeline.words.first { $0.normalized == word }).start
        }
        let beats = [("1941", 0.6, "label-typing"), ("enigma", 0.2, "enigma-glitch"), ("nobody", 0.05, "nobody-flash-x"),
                     ("ai", 0.4, "ai-sparks"), ("secret", 0.4, "narrator-question")]
        for (word, offset, name) in beats {
            let image = try await frame(document, at: start(word) + offset, longSide: 720)
            XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.03, "\(name) looks blank")
            attach(image, name: "story-\(name)")
        }
        // Post, overlays, captions and screen effects really change the picture.
        var plain = document
        plain.scene.look?.post = PostSettings()
        plain.scene.timeline.captions = nil
        plain.scene.timeline.effects = []
        for (id, object) in plain.scene.objects where object.kind.isOverlay {
            plain.scene.objects[id]?[.visible] = .bool(false)
        }
        let time = try start("nobody") + 0.05
        let styled = try await frame(document, at: time)
        let raw = try await frame(plain, at: time)
        attach(raw, name: "story-nobody-without-finish")
        XCTAssertGreaterThan(ImageChecks.difference(styled, raw), 0.02, "post / overlays / captions / effects changed the frame")
    }

    func testLensBlurAndInkOutlines() async throws {
        var document = try TestDocuments.opening()
        let camera = try XCTUnwrap(document.scene.objects.values.first { $0.name == "Desk camera" }).id
        let paper = try XCTUnwrap(document.scene.objects.values.first { $0.name == "Army message" }).id
        let sharp = try await frame(document, at: 0.1)
        // Focus on the paper: it stays sharp, the dark room behind it melts; ink lines on everything.
        let focus = document.scene.worldTransform(of: camera).position.distance(to: document.scene.worldTransform(of: paper).position)
        document.scene.objects[camera]?[.aperture] = .float(1.4)
        document.scene.objects[camera]?[.focusDistance] = .float(focus)
        var look = document.effectiveLook
        look.post.outline = 0.7
        look.post.depthOfField = true
        document.scene.look = look
        let styled = try await frame(document, at: 0.1)
        attach(sharp, name: "desk-sharp")
        attach(styled, name: "desk-lens-blur-and-outlines")
        XCTAssertGreaterThan(ImageChecks.difference(sharp, styled), 0.002, "the finish changed the frame")
    }

    /// Glow is a halo, not just a brighter surface: the same sphere lights up the dark around it when it glows.
    func testGlowCastsAHalo() async throws {
        func document(glow: Double) -> Document {
            var look = Look.default.applying(.night)
            look.post = PostSettings()
            look.ground.visible = false
            var sphere = SceneObject(id: "orb", name: "Orb", kind: .primitive(.sphere), transform: Transform(position: Vec3(0, 0.5, 0)))
            sphere[.color] = .color(.rgba(RGBA(1, 0.35, 0.2)))
            sphere[.emissiveIntensity] = .float(glow)
            return TestDocuments.document("Glow", objects: [sphere], camera: Vec3(0, 1, 3.5), rotation: Quat(angle: -0.14, axis: .unitX), look: look)
        }
        let plain = try await frame(document(glow: 0))
        let glowing = try await frame(document(glow: 4))
        attach(plain, name: "glow-off")
        attach(glowing, name: "glow-on")
        let core = CGRect(x: 0.46, y: 0.24, width: 0.08, height: 0.14)
        XCTAssertGreaterThan(ImageChecks.brightness(glowing, in: core), ImageChecks.brightness(plain, in: core) + 0.1, "the sphere itself glows")
        // Just outside the sphere's silhouette, level with its middle: lit by the halo.
        let ring = [CGRect(x: 0.33, y: 0.22, width: 0.05, height: 0.18), CGRect(x: 0.62, y: 0.22, width: 0.05, height: 0.18)]
        let lit = ring.map { ImageChecks.brightness(glowing, in: $0) }.reduce(0, +)
        let dark = ring.map { ImageChecks.brightness(plain, in: $0) }.reduce(0, +)
        XCTAssertGreaterThan(lit, dark + 0.02, "the glow spills into the dark around the sphere")
    }

    // MARK: Particles and characters

    func testParticlesAndCharacterRender() async throws {
        var ids = IDFactory.sequential("fx")
        let fragment = CharacterBuilder.build(CharacterRecipe(name: "Me", extras: [.glasses]), ids: &ids)
        var objects = fragment.objects
        let root = fragment.roots[0]
        if let index = objects.firstIndex(where: { $0.id == root }) {
            objects[index][.mouth] = .enumeration("D")
            objects[index][.brows] = .float(0.8)
        }
        for (index, preset) in [ParticleRecipe.Preset.fire, .magic].enumerated() {
            objects.append(SceneObject(id: ObjectID(raw: "particles-\(index)"), name: preset.title, kind: .particles(.preset(preset)),
                                       transform: Transform(position: Vec3(index == 0 ? -1.2 : 1.2, 0, 0.5))))
        }
        var look = Look.default.applying(.night)
        look.post = PostSettings.Preset.cinematic.settings
        var document = TestDocuments.document("FX", objects: objects, camera: Vec3(0, 1.3, 3.6), rotation: Quat(angle: -0.08, axis: .unitX),
                                              look: look)
        document.scene.timeline.clipTracks = [ClipTrack(id: "talk", target: root, segments: [
            ClipSegment(id: "s", clip: ClipRef(asset: BuiltinClips.assetID, name: "Talk"), start: 0, duration: 5)
        ])]
        let first = try await frame(document, at: 1.5, longSide: 720)
        let portrait = try await frame(document, at: 1.5, framing: .portrait, longSide: 720)
        attach(first, name: "character-fire-magic-16x9")
        attach(portrait, name: "character-fire-magic-9x16")
        XCTAssertGreaterThan(GoldenImage.coverage(first).content, 0.05)
        let again = try await frame(document, at: 1.5, longSide: 720)
        XCTAssertLessThan(ImageChecks.difference(first, again), 0.01, "particles are the same every time")
    }

    /// Newton, Hesham and Einstein side by side; then Hesham's expressions, settled, and one caught mid-overshoot.
    func testBlobCharactersAndTheirExpressions() async throws {
        var ids = IDFactory.sequential("b")
        var objects: [SceneObject] = []
        var hesham: ObjectID?
        for (index, recipe) in [Likeness.recipe(for: "newton"), .hesham, Likeness.recipe(for: "einstein")].compactMap({ $0 }).enumerated() {
            var build = BlobCharacter.build(recipe, ids: &ids)
            let root = build.fragment.roots[0]
            if let slot = build.fragment.objects.firstIndex(where: { $0.id == root }) {
                build.fragment.objects[slot].transform.position = Vec3(Double(index - 1) * 1.7, 0, 0)
                build.fragment.objects[slot][.autoBlink] = .bool(false)
            }
            objects += build.fragment.objects
            if recipe == .hesham { hesham = root }
        }
        var look = Look.default.applying(.goldenHour)
        look.post = PostSettings()
        let trio = TestDocuments.document("Blobs", objects: objects, camera: Vec3(0, 1.2, 6.2), rotation: Quat(angle: -0.04, axis: .unitX),
                                          fieldOfView: 38, look: look)
        try await attach(frame(trio, longSide: 1280), name: "blobs-newton-hesham-einstein")
        let root = try XCTUnwrap(hesham)
        var close = trio
        close.scene.objects["cam"]?.transform = Transform(position: Vec3(0, 1.15, 2.9))
        var sheet: [CGImage] = []
        for expression in [FaceExpression.neutral, .happy, .surprised, .shocked, .sad, .wink] {
            var posed = close
            var keyIDs = IDFactory.sequential("e")
            posed.scene.timeline = expression.keyed(on: root, at: 0, in: posed.scene.timeline, ids: &keyIDs)
            let image = try await frame(posed, at: 2, longSide: 640)
            attach(image, name: "blob-face-\(expression.rawValue)")
            sheet.append(image)
        }
        XCTAssertGreaterThan(ImageChecks.difference(sheet[0], sheet[3]), 0.002, "shocked doesn't look like neutral")
        var hit = close
        var hitIDs = IDFactory.sequential("h")
        hit.scene.timeline = FaceExpression.neutral.keyed(on: root, at: 0, in: hit.scene.timeline, ids: &hitIDs)
        hit.scene.timeline = FaceExpression.shocked.keyed(on: root, at: 1, in: hit.scene.timeline, ids: &hitIDs)
        try await attach(frame(hit, at: 1.12, longSide: 640), name: "blob-face-shocked-overshoot")
    }

    // MARK: Pictures and overlays

    func testAPictureCardStandsUprightInTheWorld() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let picture = try XCTUnwrap(renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 32, width: 64, height: 32))
        }.cgImage)
        var card = SceneObject(id: "card", name: "Chart", kind: .card(CardRecipe(image: "chart.png", aspect: 1)))
        card[.color] = .color(.rgba(RGBA(0.96, 0.95, 0.92)))
        var look = Look.default
        look.post = PostSettings()
        let document = TestDocuments.document("Cards", objects: [card], camera: Vec3(0, 0.53, 2.2), look: look)
        let still: (String) -> CGImage? = { $0 == "chart.png" ? picture : nil }
        let image = try await frame(document, longSide: 640, still: still)
        attach(image, name: "card-picture")
        let top = ImageChecks.rgb(image, x: 0.5, y: 0.38)
        let bottom = ImageChecks.rgb(image, x: 0.5, y: 0.62)
        XCTAssertGreaterThan(top.r, top.b + 0.3, "the top of the picture is on top (red): \(top)")
        XCTAssertGreaterThan(bottom.b, bottom.r + 0.3, "and the bottom below (blue): \(bottom)")
        // Seen from the side it's a thin slab, not a sticker on the frame.
        var side = document
        side.scene.objects["cam"]?.transform = Transform(position: Vec3(2.2, 0.53, 0.4), rotation: Quat(angle: .pi / 2 * 0.92, axis: .unitY))
        try await attach(frame(side, longSide: 640, still: still), name: "card-from-the-side")
    }

    /// Every overlay shape and a karaoke caption, drawn by the code the stage and the export share.
    func testEveryOverlayShapeAndACaptionDraw() throws {
        let size = CGSize(width: 960, height: 540)
        var scene = Scene(id: "o", name: "Overlays")
        for (index, shape) in OverlayRecipe.Shape.allCases.filter({ $0 != .image }).enumerated() {
            var recipe = OverlayRecipe.default(shape)
            if shape.hasText { recipe.text = shape.title }
            let position = Vec3(-0.75 + Double(index % 4) * 0.5, 0.6 - Double(index / 4) * 0.6, 0)
            let object = SceneObject(id: ObjectID(raw: "o\(index)"), name: shape.title, kind: .overlay(recipe),
                                     transform: Transform(position: position, scale: Vec3(0.6, 0.6, 1)))
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        let placements = OverlayLayout.placements(in: scene, palette: .starter, width: Double(size.width), height: Double(size.height))
        XCTAssertEqual(placements.count, OverlayRecipe.Shape.allCases.count - 1)
        let words = ["Nobody", "could", "read", "it."].enumerated().map { index, text in
            TimelineWord(clip: "vo", index: index, text: text, start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25)
        }
        let page = try XCTUnwrap(Captions.pages(words, maxCharacters: 30, maxLines: 2).first)
        let image = try XCTUnwrap(UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.12, green: 0.14, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            OverlayRenderer.draw(placements, in: context.cgContext, size: size)
            OverlayRenderer.drawCaption(page, activeWord: 1, settings: CaptionSettings(), in: context.cgContext, size: size)
        }.cgImage)
        attach(image, name: "overlays-and-caption")
        XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.05)
    }
}
