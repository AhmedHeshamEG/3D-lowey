import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Cast ▸ Rig (CONTEXT §10.5): a Pencil stroke through a limb, tail or rope becomes a chain of bones, the weights are
/// worked out by bone heat, and the brush paints them by hand if wanted. Every change is one `setRig` (its weights'
/// file written first). While the Rig tool is on, the object stands as it was made (its rest pose), so bones and
/// weights land where they're drawn.
extension EditorModel {
    // MARK: What can be rigged

    /// Why an object can't take a drawn skeleton (nil when it can).
    func rigBlocker(_ object: SceneObject) -> String? {
        // Something with a drawn rig is in the cast too, and is exactly what goes on being rigged: more bones, its
        // skin, its pose.
        if let type = castType(of: object.id, object: object), type != .drawn {
            return type == .rigged ? "This model has its own skeleton: drag its joints to pose it"
                : "A \(type.title) has its skeleton built in: drag its hands and feet to pose it"
        }
        switch object.kind {
        case .primitive(.plane):
            return "A flat plane has nothing to bend: draw on it, then rig the drawing"
        case .primitive, .mesh, .drawing:
            return nil
        case let .asset(id):
            guard let model = loadedModel(id) else { return "This model hasn't loaded yet" }
            return model.parts.contains(where: \.isSkinned) ? "This model has its own skeleton: drag its joints to pose it" : nil
        default:
            return "Rig a shape, a modelled part, a drawing or a placed model"
        }
    }

    func loadedModel(_ id: AssetID) -> ImportedModel? {
        guard let asset = library.catalog.manifest.asset(id) else { return nil }
        return library.models.model(asset, catalog: library.catalog)
    }

    /// The object Cast ▸ Rig works on: the one being rigged while it's there, else the selection when it can be rigged.
    var rigTarget: SceneObject? {
        if let id = rigging.target, let object = baseScene.objects[id], rigBlocker(object) == nil { return object }
        return singleSelection.flatMap { rigBlocker($0) == nil ? $0 : nil }
    }

    /// Where the object's rig lives in the world, as it was made (the edited scene, unposed).
    func rigFrame(_ id: ObjectID) -> CoreTransform {
        RigSpace.frame(of: id, in: baseScene)
    }

    /// A ray on the stage, in the rig's space.
    func rigRay(at point: CGPoint, frame: CoreTransform) -> Ray? {
        guard let ray = stage?.worldRay(at: point) else { return nil }
        let origin = frame.inverseApply(to: ray.origin)
        let ahead = frame.inverseApply(to: ray.origin + ray.direction)
        return Ray(origin: origin, direction: (ahead - origin).normalized)
    }

    /// Whether the rig's weights still fit the object (its shape may have been modelled since).
    func rigFits(_ object: SceneObject) -> Bool {
        guard let rig = object.rig else { return true }
        if case .drawing = object.kind { return RigOperations.fits(rig, object: object, mesh: nil) }
        return RigOperations.fits(rig, object: object, mesh: paintSource(of: object))
    }

    // MARK: Draw a bone

    /// Starts rigging an object: the Rig tool with Draw a bone.
    func startRigging(_ id: ObjectID) {
        guard let object = baseScene.objects[id] else { return }
        if let blocker = rigBlocker(object) {
            app.show(String.LocalizationValue(blocker))
            return
        }
        rigging.target = id
        rigging.mode = .bone
        rigging.step = .bones
        rigging.person = nil
        tool = .rig
        openPanel = nil
        app.show("Draw a bone through the part that should bend")
    }

    /// A stroke on the stage (its points) becomes a chain of bones in the rig's object.
    func drawBone(along points: [CGPoint]) {
        drawBone(rays: points.compactMap { stage?.worldRay(at: $0) })
    }

    /// A stroke's rays into the scene (one per Pencil sample) become a chain of bones in the rig's object.
    func drawBone(rays worldRays: [Ray]) {
        guard let object = rigTarget else {
            app.show("Choose what to rig first")
            return
        }
        defer { endBonePreview() }
        guard let surface = boneSurface(of: object) else {
            app.show("This model hasn't loaded yet")
            return
        }
        let samples = boneSamples(worldRays, through: surface, of: object)
        do {
            let rig = try BoneStroke.addingChain(samples, to: rigFits(object) ? object.rig : nil, surface: surface.points)
            // Drawing along a chain again replaces it: what its joints held (poses, keys) goes with them.
            let gone = object.rig.map { jointsGone(from: $0, in: rig) } ?? []
            let label = object.rig == nil ? "Rig \(object.name)" : (gone.isEmpty ? "Add a bone" : "Redraw a bone")
            weigh(rig, on: object, label: label, also: forgetting(gone, of: object))
        } catch {
            app.show(String.LocalizationValue(error.description))
        }
    }

    /// Works out the rig's weights (in the background: bone heat over a big model takes a moment), then stores it and
    /// says `done` when there's something to say.
    func weigh(_ rig: ObjectRig, on object: SceneObject, label: String, also commands: [EditCommand] = [], done: String.LocalizationValue? = nil) {
        let id = object.id
        let mesh: MeshData? = if case .drawing = object.kind {
            nil
        } else {
            paintSource(of: object)
        }
        rigging.busy.insert(id)
        let folder = assetsFolder
        Task {
            let result = await Task.detached(priority: .userInitiated) { RigOperations.weighted(rig, object: object, mesh: mesh) }.value
            rigging.busy.remove(id)
            guard let result else {
                app.show("This can't be rigged", kind: .error)
                return
            }
            do {
                try await Self.write(result.files, to: folder)
            } catch {
                app.show("Couldn't save the rig's weights: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id] != nil else { return }
            perform(.batch(label, [.setRig(id, result.rig)] + commands))
            if let done { app.show(done) }
            if rigging.joint == nil || rigging.joint ?? 0 >= result.rig.skeleton.joints.count { rigging.joint = result.rig.skeleton.joints.count - 1 }
            HmmHaptics.play(.commit)
        }
    }

    /// The weights worked out again for the object's shape as it is now.
    func refitRig(_ id: ObjectID) {
        guard let object = baseScene.objects[id], let rig = object.rig else { return }
        var fresh = rig
        fresh.skin = nil
        fresh.points = nil
        weigh(fresh, on: object, label: "Fit the weights")
    }

    /// Removes the skeleton, its pose and its keys (one undo step).
    func removeRig(_ id: ObjectID) {
        guard let object = baseScene.objects[id], object.rig != nil else { return }
        var commands: [EditCommand] = [.setRig(id, nil)]
        let turns = object.properties.keys.filter { $0.boneJoint != nil }.sorted().map { PropertyChange(object: id, key: $0, value: nil) }
        if !turns.isEmpty { commands.append(.setProperties(turns)) }
        let tracks = timeline.tracks.filter { $0.target == id && $0.property.boneJoint != nil }.map { TrackEdit(id: $0.id, track: nil) }
        if !tracks.isEmpty { commands.append(.setTracks(tracks)) }
        perform(.batch("Remove the rig", commands))
        rigging.joint = nil
        if tool == .rig { tool = .select }
    }

    /// Puts every joint back as it was made (one undo step).
    func resetPose(_ id: ObjectID) {
        guard let rig = CharacterRig.of(id, in: baseScene, rigs: libraryRigs()) else { return }
        let changes = rig.resetting(in: baseScene)
        guard !changes.isEmpty else { return }
        perform(.batch("Reset the pose", [.setProperties(changes)]))
    }

    // MARK: Weights

    /// The rig's current weights (from its file, or inline for a drawing).
    func rigWeights(_ object: SceneObject) -> SkinWeights? {
        guard let rig = object.rig else { return nil }
        if let points = rig.points { return points }
        guard let file = rig.skin, let data = paintFiles(file) else { return nil }
        return try? SkinWeights(data: data)
    }

    /// A weight brush stroke (stage points, pressure): the chosen joint's weight added (or taken away) under it.
    func paintWeights(_ samples: [(point: CGPoint, pressure: Double)]) {
        guard let object = rigTarget, let rig = object.rig, let joint = rigging.joint, let weights = rigWeights(object), let stage else { return }
        let frame = rigFrame(object.id)
        let mesh: MeshData?
        let positions: [Vec3]
        if case let .drawing(recipe) = object.kind {
            mesh = nil
            positions = recipe.strokes.flatMap(\.points)
        } else {
            mesh = paintSource(of: object)
            positions = mesh?.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) } ?? []
        }
        let bvh = mesh.map(TriangleBVH.init)
        let plane = if case let .drawing(recipe) = object.kind {
            RigOperations.drawingPlane(recipe)
        } else { (origin: Vec3.zero, normal: Vec3.unitZ) }
        let scale = max((abs(frame.scale.x) + abs(frame.scale.y) + abs(frame.scale.z)) / 3, 1e-6)
        let dabs: [WeightPaint.Dab] = samples.compactMap { sample in
            guard let ray = rigRay(at: sample.point, frame: frame) else { return nil }
            let centre: Vec3? = if let bvh {
                bvh.hits(origin: ray.origin, direction: ray.direction).first.map { ray.origin + ray.direction * $0 }
            } else {
                GuideSurface.plane(origin: plane.origin, normal: plane.normal).intersect(ray)?.point
            }
            guard let centre else { return nil }
            let radius = stage.worldPerPoint(at: frame.apply(to: centre)) * rigging.size / 2 / scale
            return WeightPaint.Dab(centre: centre, radius: radius, amount: rigging.strength * max(sample.pressure, 0.2))
        }
        guard !dabs.isEmpty else { return }
        let painted = WeightPaint.apply(dabs, joint: joint, erase: rigging.erase, to: weights, positions: positions)
        let stored = RigOperations.stored(painted, in: rig, object: object, mesh: mesh)
        let id = object.id
        let folder = assetsFolder
        Task {
            do {
                try await Self.write(stored.files, to: folder)
            } catch {
                app.show("Couldn't save the rig's weights: \(error.localizedDescription)", kind: .error)
                return
            }
            perform(.batch("Paint weights", [.setRig(id, stored.rig)]))
        }
    }

    // MARK: On the stage

    /// The weight view while painting weights: the object in the colours of the chosen bone's weight.
    var weightView: WeightView? {
        guard tool == .rig, rigging.mode == .weights, rigging.person == nil, let object = rigTarget, object.rig != nil,
              let joint = rigging.joint else { return nil }
        return WeightView(object: object.id, joint: joint)
    }

    /// The bones of the object being rigged, as it was made: a line along each bone and a dot at each joint, the bone
    /// whose weight is being painted in the accent colour. Drawn over everything, so bones inside the body show.
    func rigOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard rigging.person == nil, let object = rigTarget else { return [] }
        let drawing = bonePreviewOverlays(stage)
        guard let rig = object.rig, !rig.skeleton.isEmpty else { return drawing }
        let frame = rigFrame(object.id)
        let joints = rig.restPositions.map { frame.apply(to: $0) }
        let width = stage.worldPerPoint(at: joints[0]) * 2
        var lines = MeshData()
        var picked = MeshData()
        var dots = MeshData()
        for segment in rig.segments {
            let head = frame.apply(to: segment.head)
            let tail = frame.apply(to: segment.tail)
            if rigging.mode == .weights, segment.joint == rigging.joint {
                ModelOverlay.line(head, tail, width: width * 1.6, into: &picked)
            } else {
                ModelOverlay.line(head, tail, width: width, into: &lines)
            }
        }
        for joint in joints {
            ModelOverlay.dot(joint, radius: width * 2.2, into: &dots)
        }
        var overlays = [EditorOverlay(mesh: lines, color: RGBA(1, 1, 1), opacity: 0.9, onTop: true),
                        EditorOverlay(mesh: dots, color: Self.modelAccent, onTop: true)]
        if !picked.isEmpty { overlays.append(EditorOverlay(mesh: picked, color: Self.modelAccent, onTop: true)) }
        return overlays + drawing
    }

    /// The library's rigged models in the scene (imported characters pose by their joints even without clips).
    func libraryRigs() -> [AssetID: RigAsset] {
        var result = rigs()
        for object in baseScene.objects.values {
            // Only models the library knows are rigged: most placed models aren't, and this runs on every redraw.
            guard let id = object.kind.assetID, result[id] == nil, library.manifest.asset(id)?.rig.isRigged == true,
                  let rig = library.models.rig(id) else { continue }
            result[id] = rig
        }
        return result
    }
}
