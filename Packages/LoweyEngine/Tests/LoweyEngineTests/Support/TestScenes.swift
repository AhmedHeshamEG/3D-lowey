import Foundation
import LoweyCore
@testable import LoweyEngine

/// Small, fixed scenes the render tests draw.
enum TestScenes {
    /// The Look check: ground, a bevelled cube, a sphere, a cylinder, a cone and a blob character under one camera,
    /// in a given Look and mood. Every Look × mood golden image is this scene.
    static func lookCheck(look presetID: String, mood: LightingPreset) -> Document {
        var ids = IDFactory.sequential("look")
        var look = MoodPresets.look(for: mood)
        look.presetID = presetID
        let info = ProjectInfo(id: "look-project", name: "Look check", look: look)
        var scene = Scene(id: "look-scene", name: "Look check")
        var objects: [SceneObject] = []
        func primitive(_ shape: PrimitiveShape, _ name: String, at position: Vec3, size: Vec3, color: Int) {
            var object = SceneObject(id: ids.next(), name: name, kind: .primitive(shape), transform: Transform(position: position, scale: size))
            object[.color] = .color(.palette(color))
            if BevelSpec.applies(to: shape) {
                object[.bevel] = .float(BevelSpec.standard.radius)
                object[.bevelSegments] = .int(BevelSpec.standard.segments)
            }
            objects.append(object)
        }
        primitive(.cube, "Cube", at: Vec3(-1.6, 0, 0.2), size: Vec3(1, 1, 1), color: 0)
        primitive(.sphere, "Sphere", at: Vec3(0, 0, -0.6), size: Vec3(1.1, 1.1, 1.1), color: 1)
        primitive(.cylinder, "Cylinder", at: Vec3(1.5, 0, 0.3), size: Vec3(0.7, 1.3, 0.7), color: 2)
        primitive(.cone, "Cone", at: Vec3(0.4, 0, 1.4), size: Vec3(0.6, 0.9, 0.6), color: 3)
        var blob = BlobCharacter.build(BlobRecipe(name: "Pip", hat: .beret), ids: &ids)
        if let root = blob.fragment.roots.first, let slot = blob.fragment.objects.firstIndex(where: { $0.id == root }) {
            blob.fragment.objects[slot].transform.position = Vec3(-0.4, 0, 1.6)
        }
        objects += blob.fragment.objects
        let camera = Self.camera(ids: &ids, view: Viewpoint(target: Vec3(0, 0.55, 0.3), yaw: 30, pitch: 18, distance: 6.4))
        objects.append(camera)
        for object in objects {
            scene.objects[object.id] = object
        }
        scene.roots = objects.filter { $0.parent == nil }.map(\.id)
        scene.activeCamera = camera.id
        scene.timeline = Timeline(fps: 30, duration: 2)
        return Document(project: info, scene: scene)
    }

    /// A camera object placed like a stage viewpoint.
    static func camera(ids: inout IDFactory, view: Viewpoint, focalLength: Double = 35) -> SceneObject {
        var camera = SceneObject(id: ids.next(), name: "Camera", kind: .camera, transform: Transform(position: view.eye, rotation: view.rotation))
        camera[.fieldOfView] = .float(CameraLens.fieldOfView(focalLength: focalLength))
        return camera
    }

    /// One walker of the benchmark, close up, so skinning shows.
    static func walker() -> Document {
        var ids = IDFactory.sequential("walk")
        var look = MoodPresets.look(for: .day)
        look.presetID = LookPreset.ink.id
        let info = ProjectInfo(id: "walk-project", name: "Walker", look: look)
        var scene = Scene(id: "walk-scene", name: "Walker")
        let walker = SceneObject(id: ids.next(), name: "Walker", kind: .asset(NightMarket.walkerAsset),
                                 transform: Transform(rotation: Quat(angle: .pi / 2, axis: .unitY)))
        let camera = Self.camera(ids: &ids, view: Viewpoint(target: Vec3(0, 0.9, 0), yaw: 0, pitch: 4, distance: 3.6))
        scene.objects[walker.id] = walker
        scene.objects[camera.id] = camera
        scene.roots = [walker.id, camera.id]
        scene.activeCamera = camera.id
        var timeline = Timeline(fps: 30, duration: 2)
        timeline.clipTracks = [ClipTrack(id: "walk", target: walker.id, segments: [
            ClipSegment(id: "walk-a", clip: ClipRef(asset: NightMarket.walkerAsset, name: NightMarket.walkClip), start: 0, duration: 2)
        ])]
        scene.timeline = timeline
        return Document(project: info, scene: scene)
    }

    /// A version-1 project as 1.x wrote it (schema 3, no Look preset), opened by this version.
    static func migratedV1() throws -> Document {
        let current = lookCheck(look: LookPreset.ink.id, mood: .day)
        var json = try LoweyJSON.decode(JSONValue.self, from: SchemaCoder.shared.encode(current.project, kind: .project))
        json["schemaVersion"] = .number(3)
        var payload = json["payload"] ?? .null
        if case var .object(look) = payload["look"] ?? .null {
            look.removeValue(forKey: "presetID")
            payload["look"] = .object(look)
        }
        json["payload"] = payload
        let project = try SchemaCoder.shared.decode(ProjectInfo.self, kind: .project, from: LoweyJSON.encode(json))
        return Document(project: project, scene: current.scene)
    }
}
