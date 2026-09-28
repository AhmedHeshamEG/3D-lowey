import Foundation

/// Phase 2's proof: the Enigma opening, animated end to end (context.md §7.1), built only
/// through commands, presets, camera moves, behaviours and a Perform take.
///
///  0.0  "A German army message from 1941"  — paper under a warm lamp, the camera pushes in.
///  3.2  "People have tried since 2005"     — the room of people at PCs (typing, on twos),
///                                            screens light up in a wave; the paper grows huge.
///  7.1  "Nobody could"                     — a big X pops.
///  8.0  "Last week an AI did it"           — the hero robot rises in its cave.
/// 10.4  "What's the big secret?"           — a question mark pops.
public extension EnigmaSample {
    static let openingName = "4 · Opening (animated)"

    /// Offsets of the three sets inside the one opening world (far apart, hidden from each other by fog).
    static let roomOffset = Vec3(30, 0, 0)
    static let caveOffset = Vec3(60, 0, 0)

    /// The sample project with the three static sets plus the animated opening.
    static func buildWithOpening(ids: IDFactory = .sequential("enigma")) throws -> (ProjectInfo, [Scene]) {
        var ids = ids
        let (info, sets) = try build(ids: ids)
        // Continue the id sequence after the sets (deterministic, no collisions).
        for _ in 0 ..< 2000 {
            _ = ids.next() as ObjectID
        }
        let opening = try openingScene(ids: &ids, info: info)
        return (info, sets + [opening])
    }

    static func openingScene(ids: inout IDFactory, info: ProjectInfo) throws -> Scene {
        var desk = ids
        let deskSet = try deskScene(ids: &desk, info: info)
        var room = desk
        let roomSet = try roomScene(ids: &room, info: info)
        var cave = room
        let caveSet = try caveScene(ids: &cave, info: info)
        ids = cave

        var scene = Scene(id: ids.next(), name: openingName)
        var look = info.look
        look.lighting.sunIntensity = 0.18
        look.lighting.ambientIntensity = 0.6
        look.fog = Fog(enabled: true, color: RGBA(hex: "#0D1020")!, distance: 18)
        look.ground = Ground(visible: false, color: RGBA(hex: "#1A1D2B")!, size: 80)
        scene.look = look
        scene.timeline = Timeline(fps: 30, duration: 12)
        var b = Builder(scene: scene, info: info, ids: ids)

        // The three sets, side by side.
        for (set, offset) in [(deskSet, Vec3.zero), (roomSet, roomOffset), (caveSet, caveOffset)] {
            var fragment = FragmentTools.extract(set.roots, from: set)
            fragment = FragmentTools.transformRoots(fragment) { transform in
                var moved = transform
                moved.position += offset
                return moved
            }
            try b.session.perform(.insert(fragment, parent: nil, index: nil))
        }
        try b.box("Cave floor", at: caveOffset + Vec3(0, -0.02, 0), size: Vec3(16, 0.02, 16), color: .rgba(RGBA(hex: "#23262F")!))

        func find(_ name: String, near center: Vec3? = nil) -> ObjectID? {
            let candidates = b.session.document.scene.objects.values.filter { $0.name == name }
            guard let center else { return candidates.min { $0.id < $1.id }?.id }
            let scene = b.session.document.scene
            return candidates
                .min { scene.worldTransform(of: $0.id).position.distance(to: center) < scene.worldTransform(of: $1.id).position.distance(to: center) }?.id
        }
        func all(_ name: String) -> [ObjectID] {
            b.session.document.scene.objects.values.filter { $0.name == name }.map(\.id).sorted()
        }

        // Hero props of this video.
        let giantPaper = try b.box("Giant army message", at: roomOffset + Vec3(1.8, 2.4, 1.4), size: Vec3(0.6, 0.012, 0.84),
                                   color: .palette(0), rotation: Vec3(70, -20, 0))
        let bigX = try b.group("Big X", at: roomOffset + Vec3(1.8, 1.4, 3.6))
        for angle in [45.0, -45.0] {
            try b.box("X bar", at: Vec3(0, -0.9, 0), size: Vec3(0.34, 2.4, 0.2), color: .rgba(RGBA(hex: "#FF3B3B")!),
                      rotation: Vec3(0, 0, angle), parent: bigX, glow: 1.2)
        }
        try b.session.perform(.setProperties([PropertyChange(object: bigX, key: .rotation, value: .quat(Quat(eulerDegrees: Vec3(0, 28, 0))))]))
        let question = try b.group("Question mark", at: caveOffset + Vec3(1.9, 1.5, 0.2))
        var hook: [Vec3] = []
        for step in 0 ... 10 {
            let angle = (160 - Double(step) * 22) * .pi / 180
            hook.append(Vec3(cos(angle) * 0.4, 1.25 + sin(angle) * 0.4, 0))
        }
        hook += [Vec3(0, 0.68, 0), Vec3(0, 0.45, 0)]
        let recipe = DrawingRecipe(style: .tube, strokes: [.init(points: hook, widths: hook.map { _ in 0.07 })], segments: 8)
        try b.drawing("Question hook", recipe, at: .zero, color: .rgba(RGBA(hex: "#FFD24A")!), parent: question)
        try b.box("Question dot", .sphere, at: Vec3(0, 0.12, 0), size: Vec3(0.16, 0.16, 0.16), color: .rgba(RGBA(hex: "#FFD24A")!),
                  parent: question, glow: 1.5)

        // Cameras: one per set.
        func camera(_ name: String, _ viewpoint: Viewpoint) throws -> ObjectID {
            var object = b.factory.camera(at: viewpoint)
            b.operations.ids = b.factory.ids
            object.name = name
            object[.focusDistance] = .float(viewpoint.distance)
            try b.session.perform(.insert(SceneFragment(object: object), parent: nil, index: nil))
            return object.id
        }
        let deskCam = try camera("Desk camera", Viewpoint(target: Vec3(-0.1, 0.8, 0.08), yaw: 20, pitch: 34, distance: 2.6, fieldOfView: 40))
        let roomCam = try camera("Room camera", Viewpoint(target: roomOffset + Vec3(1.8, 1.0, 1.6), yaw: 28, pitch: 24, distance: 8.5, fieldOfView: 48))
        let caveCam = try camera("Cave camera", Viewpoint(target: caveOffset + Vec3(0, 1.4, -0.6), yaw: 0, pitch: 6, distance: 7.5, fieldOfView: 42))
        try b.session.perform(.setActiveCamera(deskCam))

        var timeline = b.session.document.scene.timeline
        timeline.cuts = [CameraCut(time: 0, camera: deskCam), CameraCut(time: 3.2, camera: roomCam), CameraCut(time: 8, camera: caveCam)]
        timeline.markers = [
            Marker(id: "m1", time: 0, name: "A German army message from 1941"),
            Marker(id: "m2", time: 3.2, name: "People have tried since 2005"),
            Marker(id: "m3", time: 7.1, name: "Nobody could"),
            Marker(id: "m4", time: 8, name: "Last week an AI did it"),
            Marker(id: "m5", time: 10.4, name: "What's the big secret?")
        ]
        // Typing: every arm in the room wobbles fast and small (a behaviour, deterministic).
        let arms = all("Arm").filter { b.session.document.scene.worldTransform(of: $0).position.x > roomOffset.x - 5 }
        for (index, arm) in arms.enumerated() {
            timeline.behaviors.append(Behavior(id: "typing-\(index)", target: arm,
                                               kind: .noise(position: .zero, rotation: Vec3(16, 0, 5), frequency: 5)))
        }
        // Handheld feel on the room camera.
        timeline.behaviors.append(Behavior(id: "handheld", target: roomCam,
                                           kind: .noise(position: Vec3(0.02, 0.02, 0.02), rotation: Vec3(0.6, 0.6, 0.3), frequency: 0.7),
                                           start: 3.2, end: 8))
        try b.session.perform(.setTimeline(timeline))
        // People are drawn on twos (Spider-Verse); cameras stay smooth.
        let people = all("Person")
        try b.session.perform(.setProperties(people.map { PropertyChange(object: $0, key: .stepping, value: .enumeration("twos")) }))

        // Separate id streams for the generators (sequential in tests, random in the app).
        let deterministic = (b.ids.next() as TrackID).raw.hasPrefix("enigma")
        var presets = PresetBuilder(ids: deterministic ? .sequential("opening-preset") : .random)
        var cameraIDs: IDFactory = deterministic ? .sequential("opening-camera") : .random
        func run(_ command: EditCommand?) throws {
            if let command { try b.session.perform(command) }
        }
        scene = b.session.document.scene

        // 1 — Desk: the camera pushes in on the paper (keyframes via a camera move).
        let paper = try find("Army message", near: .zero).unwrap("paper")
        try run(CameraMoves.apply(.pushIn, camera: deskCam, subject: scene.worldTransform(of: paper).position, at: 0.2,
                                  options: CameraMoveOptions(duration: 3, strength: 1.4), current: scene, timeline: scene.timeline, ids: &cameraIDs))
        // A Perform take: the envelope nudged by hand (samples → smoothed keys).
        if let envelope = find("Envelope", near: .zero) {
            scene = b.session.document.scene
            let start = scene.objects[envelope]!.transform.position
            var take = PerformTake(object: envelope, property: .position)
            take.begin()
            for index in 0 ... 42 {
                let t = Double(index) / 42
                let wobble = Noise.value(t * 9, seed: 5) * 0.012
                take.add(.init(time: 1 + t * 1.4, value: .vec3(start + Vec3(0.14 * t * t * (3 - 2 * t) + wobble, 0, -0.05 * t))))
            }
            try run(PerformBaker.command(for: [take], fps: 30, smoothing: 0.35, timeline: scene.timeline, ids: &cameraIDs))
        }

        // 2 — Room: screens light up in a wave (mass stagger), the paper appears and grows huge.
        scene = b.session.document.scene
        let screens = all("Screen").filter { scene.worldTransform(of: $0).position.x > roomOffset.x - 5 }
        try run(presets.apply(.popIn, to: screens, at: 3.3, options: PresetOptions(duration: 0.3, amplitude: 1),
                              stagger: StaggerSettings(delay: 0.06, order: .distance(from: roomOffset + Vec3(0, 0, 5)), randomTiming: 0.4),
                              current: scene, timeline: scene.timeline))
        scene = b.session.document.scene
        try run(presets.apply(.popIn, to: [giantPaper], at: 3.9, options: PresetOptions(.popIn), current: scene, timeline: scene.timeline))
        scene = b.session.document.scene
        var keys = KeyOperations(ids: deterministic ? .sequential("opening-key") : .random)
        let paperScale = scene.objects[giantPaper]!.transform.scale
        let grow = keys.setKey(giantPaper, .scale, value: .vec3(paperScale.scaled(by: Vec3(12, 3, 12))), at: 7, previous: nil,
                               easing: .easeInOut, in: scene.timeline)
        try run(.setTracks([grow]))
        scene = b.session.document.scene
        let lift = keys.setKey(giantPaper, .position, value: .vec3(roomOffset + Vec3(1.8, 3.6, 0.6)), at: 7,
                               previous: .vec3(scene.objects[giantPaper]!.transform.position), in: scene.timeline)
        try run(.setTracks([lift]))
        scene = b.session.document.scene
        try run(CameraMoves.apply(.pullOut, camera: roomCam, subject: roomOffset + Vec3(1.8, 1.5, 1.6), at: 4,
                                  options: CameraMoveOptions(duration: 3.6), current: scene, timeline: scene.timeline, ids: &cameraIDs))

        // 3 — Nobody could: the big X pops, the camera shakes.
        scene = b.session.document.scene
        try run(presets.apply(.popIn, to: [bigX], at: 7.1, options: PresetOptions(duration: 0.4, amplitude: 1), current: scene, timeline: scene.timeline))
        scene = b.session.document.scene
        try run(CameraMoves.apply(.shake, camera: roomCam, subject: .zero, at: 7.2, options: CameraMoveOptions(duration: 0.5, strength: 1.2),
                                  current: scene, timeline: scene.timeline, ids: &cameraIDs))

        // 4 — The hero rises; its eyes light up; the camera pushes in.
        scene = b.session.document.scene
        let robot = try find("Hero robot", near: caveOffset).unwrap("robot")
        try run(presets.apply(.slideIn, to: [robot], at: 8.2, options: PresetOptions(duration: 1.4, amplitude: 2.6, direction: Vec3(0, -1, 0)),
                              current: scene, timeline: scene.timeline))
        scene = b.session.document.scene
        for eye in ["Eye L", "Eye R"].compactMap({ find($0, near: caveOffset) }) {
            let dark = keys.setKey(eye, .emissiveIntensity, value: .float(0), at: 9, previous: nil, in: scene.timeline)
            var track = dark.track!
            track.setKey(Keyframe(time: 9.5, value: .float(6), easing: .easeOut))
            try run(.setTracks([TrackEdit(track)]))
            scene = b.session.document.scene
        }
        try run(CameraMoves.apply(.pushIn, camera: caveCam, subject: caveOffset + Vec3(0, 1.6, -0.6), at: 8,
                                  options: CameraMoveOptions(duration: 3.5, strength: 1.1), current: scene, timeline: scene.timeline, ids: &cameraIDs))

        // 5 — The question mark pops, then wiggles.
        scene = b.session.document.scene
        try run(presets.apply(.popIn, to: [question], at: 10.4, options: PresetOptions(.popIn), current: scene, timeline: scene.timeline))
        scene = b.session.document.scene
        try run(presets.apply(.wiggle, to: [question], at: 10.9, options: PresetOptions(.wiggle), current: scene, timeline: scene.timeline))
        ids = b.ids
        return b.session.document.scene
    }
}

private extension Optional {
    func unwrap(_ what: String) throws -> Wrapped {
        guard let value = self else { throw CommandError.empty }
        _ = what
        return value
    }
}
