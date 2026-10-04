import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// What the stage shows of the selection's animation: its motion path (the arc it travels, a dot per position key that
/// can be dragged to reshape the arc) and the 3D onion skin (tinted ghosts of its neighbouring keyed poses).
extension EditorModel {
    /// The single selected object whose path or ghosts are shown (select tool, not while performing).
    private var motionSubject: ObjectID? {
        guard tool == .select, performPhase == .idle, selection.count == 1, let id = selection.first else { return nil }
        return id
    }

    /// The selection's motion path (cached until the document or the selection changes).
    func selectionMotionPath() -> MotionPath? {
        guard animationView.motionPath, let id = motionSubject else { return nil }
        let key = MotionViewCache.PathKey(revision: session.revision, object: id)
        if motionCache.pathKey == key { return motionCache.path }
        let path = MotionPath.compute(document, object: id)
        motionCache.pathKey = key
        motionCache.path = path
        return path
    }

    /// The path and its key dots on screen.
    func motionPathOnScreen() -> (points: [CGPoint], dots: [(time: Double, point: CGPoint)]) {
        guard let stage, let path = selectionMotionPath() else { return ([], []) }
        let points = path.points.compactMap { stage.screenPoint(of: $0) }
        let dots = path.keys.compactMap { key in stage.screenPoint(of: key.world).map { (key.time, $0) } }
        return (points, dots)
    }

    /// The position key whose dot is under a touch (within 22 pt).
    func motionPathKey(at point: CGPoint) -> Double? {
        motionPathOnScreen().dots.filter { hypot($0.point.x - point.x, $0.point.y - point.y) < 22 }
            .min { hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y) }?.time
    }

    /// Drags the key at `time` so the object passes under the finger then (on the plane facing the camera through the
    /// dot). One undo step per drag.
    func moveMotionPathKey(at time: Double, to point: CGPoint, gesture: String) {
        guard let stage, let id = selection.first, let path = selectionMotionPath(),
              let dot = path.keys.first(where: { abs($0.time - time) < 0.0005 }), let ray = stage.worldRay(at: point) else { return }
        let normal = (Vec3(stage.camera.position) - dot.world).normalized
        guard let hit = GuideSurface.plane(origin: dot.world, normal: normal).intersect(ray)?.point, hit.distance(to: dot.world) < 50,
              let edit = MotionPath.movingKey(at: time, of: id, to: hit, in: document) else { return }
        perform(.setTracks([edit]), coalesceKey: gesture)
    }

    /// How much the selection stretches along fast moves (0 = off).
    func setSmear(_ amount: Double) {
        let value: PropertyValue? = amount < 0.01 ? nil : .float(amount)
        perform(.setProperties(selection.map { PropertyChange(object: $0, key: .smear, value: value) }), coalesceKey: "smear")
    }

    // MARK: Onion skin

    /// Ghosts of the selection at its neighbouring keys: earlier ones red, later ones green, fading with distance.
    func onionGhosts() -> [Ghost] {
        guard animationView.onionSkin, let id = motionSubject else { return [] }
        let key = MotionViewCache.GhostKey(revision: session.revision, object: id, frame: timeline.frame(for: time),
                                           before: animationView.onionBefore, after: animationView.onionAfter)
        if motionCache.ghostKey == key { return motionCache.ghosts }
        let times = MotionPath.neighbourKeyTimes(of: id, in: baseScene, around: time, before: animationView.onionBefore,
                                                 after: animationView.onionAfter)
        let rigs = rigs()
        func ghosts(_ list: [Double], tint: RGBA) -> [Ghost] {
            list.enumerated().map { offset, moment in
                Ghost(scene: Animator.evaluate(document, at: moment, rigs: rigs).scene, root: id, tint: tint, opacity: 0.38 / Double(offset + 1))
            }
        }
        let result = ghosts(times.before, tint: RGBA(1, 0.36, 0.32)) + ghosts(times.after, tint: RGBA(0.32, 0.86, 0.5))
        motionCache.ghostKey = key
        motionCache.ghosts = result
        return result
    }
}

/// The selection's motion path and onion-skin ghosts, kept while nothing they depend on changes.
struct MotionViewCache {
    struct PathKey: Equatable {
        var revision: Int
        var object: ObjectID
    }

    struct GhostKey: Equatable {
        var revision: Int
        var object: ObjectID
        var frame: Int
        var before: Int
        var after: Int
    }

    var pathKey: PathKey?
    var path: MotionPath?
    var ghostKey: GhostKey?
    var ghosts: [Ghost] = []
}
