import Foundation

/// The performance benchmark (Diagnostics ▸ Run benchmark): a night market street with ~400 objects, lanterns,
/// three point lights, four blob characters, six walking rigged figures and a slow dolly down the street, in the
/// Ink Look with lines and contact shading. Deterministic, so every run renders the same frames.
///
/// The rigged figures use the asset `NightMarket.walkerAsset`, which the engine provides (a generated skinned
/// figure with a walk cycle), so the benchmark needs nothing from the library.
public enum NightMarket {
    public static let projectName = "Night Market (benchmark)"
    public static let walkerAsset = AssetID(raw: "benchmark-walker")
    public static let walkClip = "Walk"
    public static let duration = 20.0

    public static func build() -> (ProjectInfo, Scene) {
        var ids = IDFactory.sequential("market")
        var look = MoodPresets.look(for: .night)
        look.presetID = LookPreset.ink.id
        look.palette = Palette(swatches: [
            .init(name: "Timber", color: RGBA.hex("#7A4A2E")), .init(name: "Canvas", color: RGBA.hex("#D8C39A")),
            .init(name: "Awning red", color: RGBA.hex("#C0413A")), .init(name: "Awning teal", color: RGBA.hex("#2F8C8C")),
            .init(name: "Lantern", color: RGBA.hex("#FFB85C")), .init(name: "Stone", color: RGBA.hex("#4B4F5C")),
            .init(name: "Fruit", color: RGBA.hex("#F07A3C")), .init(name: "Leaf", color: RGBA.hex("#5E8C4A"))
        ])
        look.ground.color = RGBA.hex("#3A3F4B")
        let info = ProjectInfo(id: "market-project", name: projectName, look: look)
        var scene = Scene(id: "market-scene", name: "Night Market")
        var objects: [SceneObject] = []
        func add(_ object: SceneObject) { objects.append(object) }
        for index in 0 ..< 24 {
            stall(index, ids: &ids, add: add)
        }
        for index in 0 ..< 60 {
            crate(index, ids: &ids, add: add)
        }
        for index in 0 ..< 30 {
            lantern(index, ids: &ids, add: add)
        }
        for (index, x) in [-8.0, 0, 8].enumerated() {
            var light = SceneObject(id: ids.next(), name: "Street light \(index + 1)", kind: .light(.point),
                                    transform: Transform(position: Vec3(x, 3.2, 0)))
            light[.lightColor] = .color(.rgba(RGBA.hex("#FFB85C")))
            light[.lightIntensity] = .float(2.2)
            light[.lightRange] = .float(9)
            add(light)
        }
        objects += shoppers(ids: &ids)
        let (figures, clipTracks) = walkers(ids: &ids)
        objects += figures
        let camera = dolly(ids: &ids)
        add(camera)
        for object in objects {
            scene.objects[object.id] = object
        }
        scene.roots = objects.filter { $0.parent == nil }.map(\.id)
        scene.activeCamera = camera.id
        scene.timeline = timeline(camera: camera.id, clipTracks: clipTracks)
        scene.viewpoint = Viewpoint(target: Vec3(0, 1, 0), yaw: 25, pitch: 18, distance: 18)
        return (info, scene)
    }

    /// Four blob characters along the street.
    static func shoppers(ids: inout IDFactory) -> [SceneObject] {
        var objects: [SceneObject] = []
        for index in 0 ..< 4 {
            var build = BlobCharacter.build(BlobRecipe(name: "Shopper \(index + 1)", hat: index.isMultiple(of: 2) ? .beret : .cap), ids: &ids)
            if let root = build.fragment.roots.first, let slot = build.fragment.objects.firstIndex(where: { $0.id == root }) {
                build.fragment.objects[slot].transform.position = Vec3(Double(index) * 3 - 4.5, 0, 1.2 * (index.isMultiple(of: 2) ? 1 : -1))
            }
            objects += build.fragment.objects
        }
        return objects
    }

    /// Six rigged figures walking both ways, each with its walk clip slightly out of step.
    static func walkers(ids: inout IDFactory) -> ([SceneObject], [ClipTrack]) {
        var objects: [SceneObject] = []
        var clipTracks: [ClipTrack] = []
        for index in 0 ..< 6 {
            let id: ObjectID = ids.next()
            let side = index.isMultiple(of: 2) ? 1.0 : -1.0
            objects.append(SceneObject(id: id, name: "Walker \(index + 1)", kind: .asset(walkerAsset),
                                       transform: Transform(position: Vec3(Double(index) * 2.6 - 7, 0, side * 0.6),
                                                            rotation: Quat(angle: side > 0 ? .pi / 2 : -.pi / 2, axis: .unitY))))
            clipTracks.append(ClipTrack(id: "walk-\(index)", target: id, segments: [
                ClipSegment(id: "walk-\(index)-a", clip: ClipRef(asset: walkerAsset, name: walkClip), start: 0, duration: duration,
                            offset: Double(index) * 0.17)
            ]))
        }
        return (objects, clipTracks)
    }

    static func dolly(ids: inout IDFactory) -> SceneObject {
        var camera = SceneObject(id: ids.next(), name: "Dolly", kind: .camera,
                                 transform: Transform(position: Vec3(-12, 2.2, 7), rotation: Quat(angle: -0.5, axis: .unitY)))
        camera[.fieldOfView] = .float(CameraLens.fieldOfView(focalLength: 32))
        return camera
    }

    /// The walk clips and a slow dolly down the street.
    static func timeline(camera: ObjectID, clipTracks: [ClipTrack]) -> Timeline {
        var timeline = Timeline(fps: 30, duration: duration)
        timeline.clipTracks = clipTracks
        timeline.cuts = [CameraCut(time: 0, camera: camera)]
        timeline.tracks = [Track(id: "dolly", target: camera, property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(-12, 2.2, 7))), Keyframe(time: duration, value: .vec3(Vec3(10, 2.8, 6)))
        ])]
        return timeline
    }

    /// Facts the benchmark report records.
    public static func facts(_ scene: Scene) -> [String: Double] {
        ["objects": Double(scene.objects.count), "lights": 3, "blobs": 4, "walkers": 6, "seconds": duration]
    }

    private static func primitive(_ shape: PrimitiveShape, _ name: String, at position: Vec3, size: Vec3, color: Int, ids: inout IDFactory,
                                  rotation: Double = 0, glow: Double = 0) -> SceneObject {
        var object = SceneObject(id: ids.next(), name: name, kind: .primitive(shape),
                                 transform: Transform(position: position, rotation: Quat(angle: rotation, axis: .unitY), scale: size))
        object[.color] = .color(.palette(color))
        if BevelSpec.applies(to: shape) {
            object[.bevel] = .float(BevelSpec.standard.radius)
            object[.bevelSegments] = .int(BevelSpec.standard.segments)
        }
        if glow > 0 {
            object[.emissiveIntensity] = .float(glow)
            object[.emissive] = .color(.palette(4))
        }
        return object
    }

    private static func stall(_ index: Int, ids: inout IDFactory, add: (SceneObject) -> Void) {
        let row = index < 12 ? 1.0 : -1.0
        let x = Double(index % 12) * 2.4 - 13
        let z = row * 3.2
        let facing = row > 0 ? Double.pi : 0
        add(primitive(.cube, "Counter \(index + 1)", at: Vec3(x, 0, z), size: Vec3(2, 0.9, 1), color: 0, ids: &ids, rotation: facing))
        for post in [-0.9, 0.9] {
            add(primitive(.cylinder, "Post", at: Vec3(x + post, 0, z + row * 0.45), size: Vec3(0.1, 2.3, 0.1), color: 0, ids: &ids))
        }
        add(primitive(.ramp, "Awning \(index + 1)", at: Vec3(x, 2.1, z), size: Vec3(2.2, 0.45, 1.3), color: index.isMultiple(of: 2) ? 2 : 3,
                      ids: &ids, rotation: facing))
        for item in 0 ..< 6 {
            let shape: PrimitiveShape = item.isMultiple(of: 2) ? .sphere : .cube
            add(primitive(shape, "Goods", at: Vec3(x - 0.75 + Double(item) * 0.3, 0.9, z), size: Vec3(0.22, 0.22, 0.22),
                          color: item.isMultiple(of: 3) ? 7 : 6, ids: &ids))
        }
        add(primitive(.sphere, "Stall lantern", at: Vec3(x, 1.75, z - row * 0.3), size: Vec3(0.28, 0.34, 0.28), color: 4, ids: &ids, glow: 3))
    }

    private static func crate(_ index: Int, ids: inout IDFactory, add: (SceneObject) -> Void) {
        var random = SeededRandom(seed: UInt64(1941 + index))
        let x = random.range(-15, 15)
        let z = (random.unit() > 0.5 ? 1 : -1) * random.range(4.4, 6.5)
        let barrel = index.isMultiple(of: 3)
        add(primitive(barrel ? .cylinder : .cube, barrel ? "Barrel" : "Crate", at: Vec3(x, 0, z),
                      size: barrel ? Vec3(0.55, 0.8, 0.55) : Vec3(0.7, 0.6, 0.7), color: barrel ? 0 : 1, ids: &ids,
                      rotation: random.range(0, .pi)))
    }

    private static func lantern(_ index: Int, ids: inout IDFactory, add: (SceneObject) -> Void) {
        let x = Double(index) * 1.05 - 15.5
        let sag = sin(Double(index % 10) / 9 * .pi) * 0.35
        add(primitive(.sphere, "String lantern", at: Vec3(x, 3.9 - sag, 0), size: Vec3(0.24, 0.3, 0.24), color: 4, ids: &ids, glow: 2.5))
    }
}
