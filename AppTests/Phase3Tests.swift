import AVFoundation
import CoreImage
import LoweyCore
@testable import LoweyRender
import RealityKit
import Speech
import UIKit
import XCTest

/// Phase 3 on the simulator: post-processing, overlays, captions, particles, characters, the depth pass,
/// soundtracks in exports and on-device word timing. Frames are attached as visual evidence.
@MainActor
final class Phase3Tests: XCTestCase {
    private func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private func variety(_ image: CGImage) -> Double {
        let bytes = pixels(image)
        guard bytes.count > 8 else { return 0 }
        var different = 0
        var total = 0
        for index in stride(from: 0, to: bytes.count - 4, by: 4 * 29) {
            if abs(Int(bytes[index]) - Int(bytes[0])) + abs(Int(bytes[index + 1]) - Int(bytes[1])) + abs(Int(bytes[index + 2]) - Int(bytes[2])) > 24 {
                different += 1
            }
            total += 1
        }
        return Double(different) / Double(max(total, 1))
    }

    private func difference(_ a: CGImage, _ b: CGImage) -> Double {
        let x = pixels(a)
        let y = pixels(b)
        guard x.count == y.count, !x.isEmpty else { return 1 }
        var sum = 0
        for index in stride(from: 0, to: x.count, by: 4) {
            sum += abs(Int(x[index]) - Int(y[index])) + abs(Int(x[index + 1]) - Int(y[index + 1])) + abs(Int(x[index + 2]) - Int(y[index + 2]))
        }
        return Double(sum) / Double(x.count / 4 * 3 * 255)
    }

    private func story() throws -> Document {
        let (info, scenes) = try EnigmaSample.buildFull()
        return try Document(project: info, scene: XCTUnwrap(scenes.last))
    }

    private func wordStart(_ word: String, in document: Document) throws -> Double {
        try XCTUnwrap(document.scene.timeline.words.first { $0.normalized == word }).start
    }

    // MARK: The narrated story, rendered

    func testNarratedStoryRendersWithPostOverlaysAndCaptions() async throws {
        let document = try story()
        let exporter = VideoExporter(document: document, library: nil, rigs: RigCache())
        let beats: [(String, Double, String)] = [
            ("1941", 0.6, "label-typing"), ("enigma", 0.2, "enigma-glitch"), ("nobody", 0.05, "nobody-flash-x"),
            ("ai", 0.4, "ai-sparks"), ("secret", 0.4, "narrator-question")
        ]
        for (word, offset, name) in beats {
            let time = try wordStart(word, in: document) + offset
            let images = try await exporter.images(at: time, framings: [.landscape, .portrait], longSide: 720)
            for (image, framing) in zip(images, ["16x9", "9x16"]) {
                XCTAssertGreaterThan(variety(image), 0.03, "\(name) \(framing) looks blank")
                attach(image, name: "story-\(name)-\(framing)")
            }
        }
        // Post, overlays and captions really change the picture.
        var plain = document
        plain.scene.look?.post = PostSettings()
        plain.scene.timeline.captions = nil
        plain.scene.timeline.effects = []
        for (id, object) in plain.scene.objects where object.kind.isOverlay {
            plain.scene.objects[id]?[.visible] = .bool(false)
        }
        let time = try wordStart("nobody", in: document) + 0.05
        let styled = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: time, framings: [.landscape], longSide: 480)
        let raw = try await VideoExporter(document: plain, library: nil, rigs: RigCache()).images(at: time, framings: [.landscape], longSide: 480)
        attach(raw[0], name: "story-nobody-without-post")
        XCTAssertGreaterThan(difference(styled[0], raw[0]), 0.02, "post / overlays / captions changed the frame")
    }

    // MARK: Depth pass (lens blur and outlines depend on it)

    func testDepthPassEncodesInverseDistance() async throws {
        var scene = CoreScene(id: "depth", name: "Depth")
        var look = Look.default
        look.ground.visible = false
        scene.look = look
        // Three walls straight ahead, left / middle / right, at 1, 2.5 and 6 metres.
        for (index, (x, distance)) in [(-1.0, 1.0), (0.0, 2.5), (1.0, 6.0)].enumerated() {
            let width = distance * 0.9
            var wall = SceneObject(id: ObjectID(raw: "wall-\(index)"), name: "Wall", kind: .primitive(.cube),
                                   transform: LoweyCore.Transform(
                                       position: Vec3(x * width * 1.02, -distance, -distance),
                                       scale: Vec3(width, distance * 2, 0.01)
                                   ))
            wall[.color] = .color(.rgba(RGBA(1, 1, 1)))
            scene.objects[wall.id] = wall
            scene.roots.append(wall.id)
        }
        let document = Document(project: ProjectInfo(id: "p", name: "Depth"), scene: scene)
        let world = SceneRenderer()
        world.showsHelpers = false
        world.depthPass = true
        world.load(document)
        let session = try RenderSession(device: XCTUnwrap(MTLCreateSystemDefaultDevice()), world: world, background: .black)
        session.renderer.lighting.resource = nil
        let target = try session.target(width: 300, height: 100)
        let camera = OffscreenRenderer.Camera(position: .zero, orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), fieldOfView: 60)
        for _ in 0 ..< 3 {
            try await session.render(camera: camera, target: target, world: world, deltaTime: 1 / 30)
        }
        let image = try target.image(transparent: false)
        attach(image, name: "depth-pass")
        XCTAssertTrue(MaterialFactory.shared.depthShaderAvailable, "the loweyDepth shader compiled")
        let bytes = target.bytes()
        func v(atX x: Int) -> Double {
            let index = (50 * 300 + x) * 4
            return Double(VideoExporter.srgbToLinear[Int(bytes[index + 2])]) / 255
        }
        let near = v(atX: 50)
        let middle = v(atX: 150)
        let far = v(atX: 250)
        print("depth v: \(near) \(middle) \(far)")
        XCTAssertGreaterThan(near, middle, "nearer is brighter")
        XCTAssertGreaterThan(middle, far)
        XCTAssertEqual(near, 0.5, accuracy: 0.08)
        XCTAssertEqual(middle, 0.2, accuracy: 0.05)
        XCTAssertEqual(far, 0.083, accuracy: 0.04)
    }

    func testLensBlurAndInkOutlines() async throws {
        let (info, scenes) = try EnigmaSample.buildWithOpening()
        var document = try Document(project: info, scene: XCTUnwrap(scenes.last))
        guard let camera = document.scene.objects.values.first(where: { $0.name == "Desk camera" })?.id else { return XCTFail("no desk camera") }
        let sharp = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: 0.1, framings: [.landscape], longSide: 480)
        document.scene.objects[camera]?[.aperture] = .float(1.2)
        document.scene.objects[camera]?[.focusDistance] = .float(1.2)
        var look = document.effectiveLook
        look.post.outline = 0.7
        document.scene.look = look
        let styled = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: 0.1, framings: [.landscape], longSide: 480)
        attach(sharp[0], name: "desk-sharp")
        attach(styled[0], name: "desk-lens-blur-and-outlines")
        XCTAssertGreaterThan(difference(sharp[0], styled[0]), 0.01)
    }

    // MARK: Particles, characters

    func testParticlesAndCharacterRender() async throws {
        var scene = CoreScene(id: "fx", name: "FX")
        var look = Look.default.applying(.night)
        look.post = PostSettings.Preset.cinematic.settings
        scene.look = look
        var ids = IDFactory.sequential("fx")
        let fragment = CharacterBuilder.build(CharacterRecipe(name: "Me", extras: [.glasses]), ids: &ids)
        for object in fragment.objects {
            scene.objects[object.id] = object
        }
        scene.roots += fragment.roots
        let root = fragment.roots[0]
        scene.objects[root]?[.mouth] = .enumeration("D")
        scene.objects[root]?[.brows] = .float(0.8)
        for (index, preset) in [ParticleRecipe.Preset.fire, .magic].enumerated() {
            var fx = SceneObject(id: ObjectID(raw: "particles-\(index)"), name: preset.title, kind: .particles(.preset(preset)),
                                 transform: LoweyCore.Transform(position: Vec3(index == 0 ? -1.2 : 1.2, 0, 0.5)))
            fx[.visible] = .bool(true)
            scene.objects[fx.id] = fx
            scene.roots.append(fx.id)
        }
        var cam = SceneObject(id: "cam", name: "Camera", kind: .camera,
                              transform: LoweyCore.Transform(position: Vec3(0, 1.3, 3.6), rotation: Quat(angle: -0.08, axis: .unitX)))
        cam[.fieldOfView] = .float(40)
        scene.objects[cam.id] = cam
        scene.roots.append(cam.id)
        scene.activeCamera = cam.id
        scene.timeline.clipTracks = [ClipTrack(id: "talk", target: root, segments: [
            ClipSegment(id: "s", clip: ClipRef(asset: BuiltinClips.assetID, name: "Talk"), start: 0, duration: 5)
        ])]
        let document = Document(project: ProjectInfo(id: "p", name: "FX"), scene: scene)
        let exporter = VideoExporter(document: document, library: nil, rigs: RigCache())
        let first = try await exporter.images(at: 1.5, framings: [.landscape, .portrait], longSide: 720)
        attach(first[0], name: "character-fire-magic-16x9")
        attach(first[1], name: "character-fire-magic-9x16")
        XCTAssertGreaterThan(variety(first[0]), 0.05)
        let again = try await VideoExporter(document: document, library: nil, rigs: RigCache()).images(at: 1.5, framings: [.landscape], longSide: 720)
        XCTAssertLessThan(difference(first[0], again[0]), 0.01, "particles are the same every time")
    }

    // MARK: Overlays and transitions (drawing code shared with the live stage)

    func testEveryOverlayShapeDraws() throws {
        let size = CGSize(width: 960, height: 540)
        var scene = CoreScene(id: "o", name: "O")
        for (index, shape) in OverlayRecipe.Shape.allCases.filter({ $0 != .image }).enumerated() {
            let column = Double(index % 4)
            let row = Double(index / 4)
            var recipe = OverlayRecipe.default(shape)
            if shape.hasText { recipe.text = shape.title }
            let object = SceneObject(id: ObjectID(raw: "o\(index)"), name: shape.title, kind: .overlay(recipe),
                                     transform: LoweyCore.Transform(position: Vec3(-0.75 + column * 0.5, 0.6 - row * 0.6, 0), scale: Vec3(0.6, 0.6, 1)))
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        let placements = OverlayLayout.placements(in: scene, palette: .starter, width: Double(size.width), height: Double(size.height))
        let compositor = FrameCompositor()
        var words: [TimelineWord] = []
        for (index, text) in ["Nobody", "could", "read", "it."].enumerated() {
            words.append(TimelineWord(clip: "vo", index: index, text: text, start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25))
        }
        let page = try XCTUnwrap(Captions.pages(words, maxCharacters: 30, maxLines: 2).first)
        let overlay = try XCTUnwrap(compositor.overlayImage(size: size) { context in
            OverlayRenderer.draw(placements, in: context, size: size)
            OverlayRenderer.drawCaption(page, activeWord: 1, settings: CaptionSettings(), in: context, size: size)
        })
        let background = CIImage(color: CIColor(red: 0.12, green: 0.14, blue: 0.2)).cropped(to: CGRect(origin: .zero, size: size))
        let image = try XCTUnwrap(compositor.context.createCGImage(overlay.composited(over: background), from: background.extent))
        attach(image, name: "overlays-and-caption")
        XCTAssertGreaterThan(variety(image), 0.05)
        // Transitions blend two shots.
        let a = CIImage(color: .red).cropped(to: background.extent)
        let b = CIImage(color: .blue).cropped(to: background.extent)
        for kind in TransitionSpec.Kind.allCases {
            let mid = compositor.transition(from: a, to: b, kind: kind, progress: 0.5)
            XCTAssertEqual(mid.extent, background.extent, kind.rawValue)
        }
        // Screen effects and the film look run.
        var state = ScreenState()
        state.flash = 0.5
        state.shake = SIMD3(0.01, 0.01, 0.01)
        state.glitch = 0.8
        state.speedLines = 0.7
        let finished = compositor.finish(background, look: FrameLook(post: PostSettings.Preset.oldFilm.settings, screen: state, frame: 3), overlays: overlay)
        let final = try XCTUnwrap(compositor.context.createCGImage(finished, from: background.extent))
        attach(final, name: "screen-effects-old-film")
    }

    // MARK: Sound

    func testVideoExportCarriesTheSoundtrack() async throws {
        let (info, scenes) = try EnigmaSample.buildWithOpening()
        let document = try Document(project: info, scene: XCTUnwrap(scenes.last))
        let rate = 48000
        let seconds = 1.0
        let tone = (0 ..< Int(Double(rate) * seconds)).flatMap { index -> [Float] in
            let sample = Float(sin(Double(index) / Double(rate) * 2 * .pi * 440) * 0.3)
            return [sample, sample]
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-p3-\(UUID().uuidString)")
        let settings = VideoExportSettings(framings: [.landscape], longSide: 320, range: TimeRange(start: 0, end: seconds), fps: 24,
                                           audio: tone, audioSampleRate: rate)
        let urls = try await VideoExporter(document: document, library: nil, rigs: RigCache())
            .export(settings: settings, to: folder, baseName: "Sound") { _ in }
        let asset = try AVURLAsset(url: XCTUnwrap(urls.first))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "the soundtrack is in the video")
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, seconds, accuracy: 0.15)
    }

    /// Word timing with Apple's on-device SpeechAnalyzer (no Whisper): a synthesized sentence is transcribed with word times.
    func testSpeechAnalyzerGivesWordTimes() async throws {
        guard SpeechTranscriber.isAvailable else { throw XCTSkip("SpeechTranscriber isn't available on this simulator") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw XCTSkip("en-US transcription isn't supported here")
        }
        // A voice to transcribe.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lowey-voice-\(UUID().uuidString).caf")
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "This is a German army message from nineteen forty one. Nobody could read it.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let written: Bool = await withCheckedContinuation { continuation in
            var file: AVAudioFile?
            var done = false
            synthesizer.write(utterance) { buffer in
                guard !done else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    done = true
                    continuation.resume(returning: file != nil)
                    return
                }
                if file == nil { file = try? AVAudioFile(
                    forWriting: url,
                    settings: pcm.format.settings,
                    commonFormat: pcm.format.commonFormat,
                    interleaved: false
                ) }
                try? file?.write(from: pcm)
            }
        }
        guard written else { throw XCTSkip("No speech voice on this simulator") }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw XCTSkip("Couldn't install the speech model here: \(error)")
        }
        let collector = Task { () throws -> [TranscriptWord] in
            var words: [TranscriptWord] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    words += TranscriptEditing.words(from: String(result.text[run.range].characters), start: range.start.seconds, end: range.end.seconds)
                }
            }
            return words
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let words = try await collector.value
        let texts = words.map { TimelineWord.normalize($0.text) }
        print("SpeechAnalyzer words: \(words.map { "\($0.text)@\(String(format: "%.2f", $0.start))" }.joined(separator: " "))")
        XCTAssertTrue(texts.contains("german"), "heard: \(texts)")
        XCTAssertTrue(texts.contains("message"))
        XCTAssertTrue(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start + 1e-6 }, "word times go forward")
        let add = XCTAttachment(string: words.map { "\($0.text) \(String(format: "%.2f–%.2f", $0.start, $0.end))" }.joined(separator: "\n"))
        add.name = "speechanalyzer-words"
        add.lifetime = .keepAlways
        self.add(add)
    }
}
