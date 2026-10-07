import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine

/// The surface a bone is drawn through: built once when the stroke starts, asked for every sample after.
struct BoneSurface {
    var object: ObjectID
    /// nil for a drawing: its bones lie on its plane.
    var tree: TriangleBVH?
    var points: [Vec3]
}

/// Cast ▸ Rig in three steps (Bones → Skin → Pose), and the bone under the Pencil shown as it will land.
extension EditorModel {
    // MARK: Steps

    /// Whether a step can be entered: Bones always, Skin once there are bones and their weights have arrived, Pose
    /// once the skin fits the shape.
    func rigStepIsOpen(_ step: RigSettings.Step, for object: SceneObject) -> Bool {
        switch step {
        case .bones: true
        case .skin: object.rig != nil && !rigging.busy.contains(object.id)
        case .pose: object.rig != nil && !rigging.busy.contains(object.id) && rigFits(object)
        }
    }

    /// The step Cast ▸ Rig shows for an object: where its rigging was left, Bones for something with none yet, Pose
    /// for something rigged earlier.
    func rigStep(for object: SceneObject) -> RigSettings.Step {
        guard object.rig != nil else { return .bones }
        guard rigging.target == object.id else { return rigStepIsOpen(.pose, for: object) ? .pose : .skin }
        return rigStepIsOpen(rigging.step, for: object) ? rigging.step : .bones
    }

    /// Goes to a step. With the Rig tool in the hand the Pencil follows: it draws bones, paints weights, or (Pose) is
    /// put down for the Select tool, which drags joints.
    func setRigStep(_ step: RigSettings.Step, on id: ObjectID) {
        guard let object = baseScene.objects[id], rigStepIsOpen(step, for: object) else { return }
        if rigging.person != nil { cancelPersonRig() }
        rigging.target = id
        rigging.step = step
        switch step {
        case .bones:
            rigging.mode = .bone
        case .skin:
            rigging.mode = .weights
            let count = object.rig?.skeleton.joints.count ?? 0
            if rigging.joint.map({ $0 >= count }) ?? true { rigging.joint = count - 1 }
        case .pose:
            if tool == .rig { tool = .select }
            if selection != [id] { setSelection([id]) }
        }
    }

    /// Skin ▸ Paint weights: the Rig tool with the weight brush.
    func startPaintingWeights(_ id: ObjectID) {
        setRigStep(.skin, on: id)
        guard rigging.step == .skin else { return }
        tool = .rig
        openPanel = nil
    }

    // MARK: The bone under the Pencil

    /// The surface the object's bones are drawn through (kept until the stroke ends).
    func boneSurface(of object: SceneObject) -> BoneSurface? {
        if let boneSurface, boneSurface.object == object.id { return boneSurface }
        let surface: BoneSurface
        if case let .drawing(recipe) = object.kind {
            surface = BoneSurface(object: object.id, tree: nil, points: recipe.strokes.flatMap(\.points))
        } else {
            guard let mesh = paintSource(of: object) else { return nil }
            surface = BoneSurface(object: object.id, tree: TriangleBVH(mesh),
                                  points: mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) })
        }
        boneSurface = surface
        return surface
    }

    /// A stroke's rays (in the world) as the centreline it draws through the object, in the rig's space.
    func boneSamples(_ worldRays: [Ray], through surface: BoneSurface, of object: SceneObject) -> [BoneStroke.Sample] {
        let frame = rigFrame(object.id)
        let rays = worldRays.map { ray in
            let origin = frame.inverseApply(to: ray.origin)
            return Ray(origin: origin, direction: (frame.inverseApply(to: ray.origin + ray.direction) - origin).normalized)
        }
        if let tree = surface.tree { return BoneStroke.centreline(rays: rays, surface: tree) }
        guard case let .drawing(recipe) = object.kind else { return [] }
        let plane = RigOperations.drawingPlane(recipe)
        return BoneStroke.onPlane(rays: rays, origin: plane.origin, normal: plane.normal)
    }

    /// While the Pencil is still down: the joints the stroke so far would make, shown inside the object.
    func previewBone(along points: [CGPoint]) {
        guard let stage, let object = rigTarget, let surface = boneSurface(of: object) else { return }
        let samples = boneSamples(points.compactMap { stage.worldRay(at: $0) }, through: surface, of: object)
        rigging.preview = BoneStroke.preview(samples)
    }

    /// The stroke is over (kept or not): the preview goes and the surface is let go.
    func endBonePreview() {
        boneSurface = nil
        if !rigging.preview.isEmpty { rigging.preview = [] }
    }

    /// The joints of `old` a new rig no longer has (a joint that kept its name but moved is a new joint).
    func jointsGone(from old: ObjectRig, in rig: ObjectRig) -> Set<String> {
        let kept = Dictionary(zip(rig.skeleton.names, rig.restPositions), uniquingKeysWith: { first, _ in first })
        return Set(zip(old.skeleton.names, old.restPositions).compactMap { name, place in
            kept[name].map { $0.distance(to: place) < 1e-9 } == true ? nil : name
        })
    }

    /// Taking away what joints that are gone held: their turns and their keys.
    func forgetting(_ gone: Set<String>, of object: SceneObject) -> [EditCommand] {
        guard !gone.isEmpty else { return [] }
        func isGone(_ key: PropertyKey) -> Bool { key.boneJoint.map(gone.contains) ?? false }
        var commands: [EditCommand] = []
        let turns = object.properties.keys.filter(isGone).sorted().map { PropertyChange(object: object.id, key: $0, value: nil) }
        if !turns.isEmpty { commands.append(.setProperties(turns)) }
        let tracks = timeline.tracks.filter { $0.target == object.id && isGone($0.property) }.map { TrackEdit(id: $0.id, track: nil) }
        if !tracks.isEmpty { commands.append(.setTracks(tracks)) }
        return commands
    }

    /// The bone being drawn, on the stage: its joints and the bones between them, in the accent colour.
    func bonePreviewOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard rigging.preview.count >= 2, let object = rigTarget else { return [] }
        let frame = rigFrame(object.id)
        let joints = rigging.preview.map { frame.apply(to: $0) }
        let width = stage.worldPerPoint(at: joints[0]) * 2.4
        var lines = MeshData()
        var dots = MeshData()
        for (head, tail) in zip(joints, joints.dropFirst()) {
            ModelOverlay.line(head, tail, width: width, into: &lines)
        }
        for joint in joints {
            ModelOverlay.dot(joint, radius: width * 2, into: &dots)
        }
        return [EditorOverlay(mesh: lines, color: Self.modelAccent, onTop: true), EditorOverlay(mesh: dots, color: RGBA(1, 1, 1), onTop: true)]
    }
}
