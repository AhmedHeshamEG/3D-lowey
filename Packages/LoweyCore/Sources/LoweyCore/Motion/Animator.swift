import Foundation

/// The scene as it looks at one moment: keyed values, behaviours and character poses applied.
public struct AnimatedScene: Sendable {
    public var time: Double
    public var scene: Scene
    /// Objects whose values differ from the edited ("base") scene at this time.
    public var animated: Set<ObjectID>
    /// The camera the shot is seen through (cut track, else the scene's active camera).
    public var camera: ObjectID?
    /// Local joint transforms per character, in skeleton order.
    public var poses: [ObjectID: [Transform]]
}

/// Evaluates timelines. Pure and deterministic: the same document and time always give the same
/// result, which is what makes preview and export identical and makes everything unit-testable.
public enum Animator {
    /// Evaluates `document` at `time`. `rigs` supplies skeletons and clips for characters.
    /// `overrides` are live values (a slider or your face being performed) applied on top of the keys, before
    /// behaviours, clips and faces — so a performed face moves the character's eyes and mouth like keyed values do.
    public static func evaluate(_ document: Document, at time: Double, rigs libraryRigs: [AssetID: RigAsset] = [:],
                                overrides: [ObjectID: [PropertyKey: PropertyValue]] = [:]) -> AnimatedScene {
        let timeline = document.scene.timeline
        // Built-in humanoid clips play on any humanoid (built characters and imported rigs).
        let rigs = timeline.clipTracks.isEmpty ? libraryRigs : libraryRigs.merging(BuiltinClips.rigs) { library, _ in library }
        var scene = document.scene
        let palette = document.palette
        var animated = Set<ObjectID>()
        let rates = FrameRates(document)
        applyTracks(timeline, to: &scene, at: time, palette: palette, rates: rates, animated: &animated)
        for (id, values) in overrides {
            guard var object = scene.objects[id] else { continue }
            for (key, value) in values {
                object[key] = value
            }
            scene.objects[id] = object
            animated.insert(id)
        }
        if !timeline.behaviors.isEmpty {
            // Where a target was earlier (for `follow` with lag): keys only — no recursion into behaviours.
            let history: (ObjectID, Double) -> Vec3? = { id, earlier in
                var past = document.scene
                var ignored = Set<ObjectID>()
                applyTracks(timeline, to: &past, at: earlier, palette: palette, rates: rates, animated: &ignored)
                return past.objects[id] != nil ? past.worldTransform(of: id).position : nil
            }
            for behavior in timeline.behaviors where behavior.enabled && scene.objects[behavior.target] != nil {
                let sampleTime = rates.sampleTime(time, for: behavior.target, in: scene)
                BehaviorEvaluator.apply(behavior, to: &scene, at: sampleTime, history: history)
                animated.insert(behavior.target)
            }
        }
        var poses: [ObjectID: [Transform]] = [:]
        for track in timeline.clipTracks {
            guard let object = scene.objects[track.target] else { continue }
            let sampleTime = rates.sampleTime(time, for: track.target, in: scene)
            let world = scene.worldTransform(of: track.target)
            let snapshot = scene
            let target: (ObjectID) -> Vec3? = { id in snapshot.objects[id] != nil ? snapshot.worldTransform(of: id).position : nil }
            if let assetID = object.kind.assetID, let character = rigs[assetID] {
                if let pose = ClipMixer.pose(track: track, character: character, rigs: rigs, at: sampleTime, world: world, targetPosition: target) {
                    poses[track.target] = pose
                    animated.insert(track.target)
                }
            } else if let pose = RigPoses.clipPose(track, object: object, rigs: rigs, at: sampleTime, world: world, target: target) {
                poses[track.target] = pose
                animated.insert(track.target)
            } else if object[.rigStandard] != nil, let puppet = PuppetRig.build(track.target, in: document.scene),
                      let pose = ClipMixer.pose(track: track, character: puppet.rig, rigs: rigs, at: sampleTime, world: world, targetPosition: target) {
                // Built characters: the pose moves their joint objects.
                puppet.apply(pose, to: &scene, animated: &animated)
                animated.insert(track.target)
            }
        }
        // Skeletons posed by hand (`bone.<joint>`) over their clips; drawn puppets bend their strokes.
        RigPoses.apply(to: &scene, poses: &poses, rigs: rigs, animated: &animated)
        // Faces: blink, brows, look, mouth shapes (lip sync), head turns.
        FaceRig.apply(to: &scene, base: document.scene, animated: &animated)
        // Blobs: their clips (dials, lift, lean), then the cartoon face (springy, squash & stretch, auto blink).
        var blobLive = overrides
        let current = scene
        BlobClips.apply(to: &scene, document: document, sampleTime: { rates.sampleTime(time, for: $0, in: current) }, overrides: &blobLive,
                        animated: &animated)
        BlobRig.apply(to: &scene, document: document, time: time, overrides: blobLive, animated: &animated)
        // Rubber-hose limbs follow wherever their hands went.
        RubberHose.apply(to: &scene, animated: &animated)
        let camera = timeline.cutCamera(at: time).flatMap { scene.objects[$0] != nil ? $0 : nil }
            ?? scene.activeCamera.flatMap { scene.objects[$0] != nil ? $0 : nil }
        return AnimatedScene(time: time, scene: scene, animated: animated, camera: camera, poses: poses)
    }

    /// Keyed values only (no behaviours, no clips) — cheap, used for lag history and key editing.
    public static func keyedScene(_ document: Document, at time: Double) -> Scene {
        var scene = document.scene
        var ignored = Set<ObjectID>()
        applyTracks(document.scene.timeline, to: &scene, at: time, palette: document.palette, rates: FrameRates(document), animated: &ignored)
        return scene
    }

    static func applyTracks(_ timeline: Timeline, to scene: inout Scene, at time: Double, palette: Palette, rates: FrameRates,
                            animated: inout Set<ObjectID>) {
        var steppedTimes: [ObjectID: Double] = [:]
        for track in timeline.tracks {
            guard var object = scene.objects[track.target] else { continue }
            let sampleTime: Double
            if let cached = steppedTimes[track.target] {
                sampleTime = cached
            } else {
                sampleTime = rates.sampleTime(time, for: track.target, in: scene)
                steppedTimes[track.target] = sampleTime
            }
            guard let value = track.value(at: sampleTime, palette: palette) else { continue }
            if let spec = track.property.spec, spec.type != value.type, !(spec.type == .float && value.type == .int) { continue }
            if object.properties[track.property] != value {
                object.properties[track.property] = value
                scene.objects[track.target] = object
            }
            animated.insert(track.target)
        }
    }
}

public extension SceneObject {
    var opacity: Double { properties[.opacity]?.floatValue ?? 1 }
}

/// Camera optics shared by the stage, snapshots and export.
public struct CameraLens: Hashable, Sendable {
    /// Vertical field of view (degrees) of the 16:9 frame.
    public var fieldOfView: Double
    public var focusDistance: Double
    /// f-number; 0 = no depth of field.
    public var aperture: Double
    public var portraitZoom: Double
    public var portraitShift: Double

    public init(fieldOfView: Double = 50, focusDistance: Double = 5, aperture: Double = 0, portraitZoom: Double = 1, portraitShift: Double = 0) {
        self.fieldOfView = fieldOfView
        self.focusDistance = focusDistance
        self.aperture = aperture
        self.portraitZoom = portraitZoom
        self.portraitShift = portraitShift
    }

    public init(_ object: SceneObject) {
        self.init(
            fieldOfView: object[.fieldOfView]?.floatValue ?? 50,
            focusDistance: object[.focusDistance]?.floatValue ?? 5,
            aperture: object[.aperture]?.floatValue ?? 0,
            portraitZoom: object[.portraitZoom]?.floatValue ?? 1,
            portraitShift: object[.portraitShift]?.floatValue ?? 0
        )
    }

    /// 35 mm-equivalent focal length for the vertical field of view (24 mm frame height).
    public var focalLength: Double { 12 / tan(fieldOfView * .pi / 360) }

    public static func fieldOfView(focalLength: Double) -> Double {
        2 * atan(12 / max(focalLength, 1)) * 180 / .pi
    }

    /// Vertical field of view and extra yaw (radians) for an output aspect ratio (width / height).
    /// Wide frames use the camera as framed; tall frames (9:16) apply the portrait zoom and pan.
    public func framing(aspect: Double) -> (fieldOfView: Double, yaw: Double) {
        guard aspect < 1 else { return (fieldOfView, 0) }
        let vertical = min(max(fieldOfView * portraitZoom, 5), 150)
        let landscapeHalfWidth = tan(fieldOfView * .pi / 360) * 16 / 9
        let yaw = -atan(portraitShift * landscapeHalfWidth)
        return (vertical, yaw)
    }
}
