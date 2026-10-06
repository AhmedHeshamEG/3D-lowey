import Foundation

/// "Rig as a person": a humanoid skeleton from a few points on a front view of the model. The points come from
/// Apple's body-pose model when it finds the person, else from eight taps (one side; the other is mirrored). Each point
/// is a ray into the model; its joint sits in the middle of the limb it crosses. The skeleton follows the humanoid
/// standard, so every built-in clip plays on it.
public enum HumanRig {
    /// The points of a front view (the character's left is +x, facing +z).
    public enum Dot: String, CaseIterable, Codable, Sendable {
        case head, chin
        case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
        case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

        public var title: String {
            switch self {
            case .head: "the top of the head"
            case .chin: "the chin"
            case .leftShoulder, .rightShoulder: "a shoulder"
            case .leftElbow, .rightElbow: "an elbow"
            case .leftWrist, .rightWrist: "a wrist"
            case .leftHip, .rightHip: "a hip"
            case .leftKnee, .rightKnee: "a knee"
            case .leftAnkle, .rightAnkle: "an ankle"
            }
        }

        /// The same point on the other side (head and chin are their own).
        public var mirror: Dot {
            let name = rawValue
            if name.hasPrefix("left") { return Dot(rawValue: "right" + name.dropFirst(4)) ?? self }
            if name.hasPrefix("right") { return Dot(rawValue: "left" + name.dropFirst(5)) ?? self }
            return self
        }
    }

    /// The eight a person taps when the body-pose model can't help: one side, the other mirrored.
    public static let tapped: [Dot] = [.head, .chin, .leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle]

    /// Where the dots start on a model of these bounds (rig space, on the plane through its middle): a person standing
    /// with the arms a little out. The person drags them where they belong.
    public static func template(bounds: Bounds) -> [Dot: Vec3] {
        let height = bounds.size.y
        let centre = bounds.center
        let halfWidth = bounds.size.x / 2
        func point(_ side: Double, _ out: Double, _ up: Double) -> Vec3 {
            Vec3(centre.x + side * min(out * height, halfWidth * 0.95), bounds.min.y + up * height, centre.z)
        }
        var result: [Dot: Vec3] = [.head: point(0, 0, 0.99), .chin: point(0, 0, 0.86)]
        for (side, sign) in [("left", 1.0), ("right", -1.0)] {
            let joints: [(String, Double, Double)] = [("Shoulder", 0.12, 0.81), ("Elbow", 0.17, 0.64), ("Wrist", 0.2, 0.48),
                                                      ("Hip", 0.06, 0.52), ("Knee", 0.065, 0.28), ("Ankle", 0.07, 0.05)]
            for (name, out, up) in joints {
                if let dot = Dot(rawValue: side + name) { result[dot] = point(sign, out, up) }
            }
        }
        return result
    }

    /// The dots with every left/right pair completed from the side that was placed, mirrored across `centreX`.
    public static func mirrored(_ dots: [Dot: Vec3], from placed: Set<Dot>, centreX: Double) -> [Dot: Vec3] {
        var result = dots
        for dot in placed where dot.mirror != dot && !placed.contains(dot.mirror) {
            guard let point = dots[dot] else { continue }
            result[dot.mirror] = Vec3(2 * centreX - point.x, point.y, point.z)
        }
        return result
    }

    /// Each dot's point in the middle of the limb its ray crosses (rays in rig space). A ray that misses the model keeps
    /// its point on the plane through the model's middle.
    public static func points(rays: [Dot: Ray], surface: TriangleBVH, bounds: Bounds) -> [Dot: Vec3] {
        var result: [Dot: Vec3] = [:]
        for (dot, ray) in rays {
            if let middle = BoneStroke.centreline(rays: [ray], surface: surface).first {
                result[dot] = middle.point
            } else if let hit = GuideSurface.plane(origin: bounds.center, normal: ray.direction).intersect(ray) {
                result[dot] = hit.point
            }
        }
        return result
    }

    /// The humanoid skeleton through the points (rig space). Spine, chest and neck are spaced between the hips and the
    /// shoulders; the feet get toes; the head, hands and toes get tips so their bones carry weight.
    public static func rig(from dots: [Dot: Vec3], bounds: Bounds) -> ObjectRig? {
        guard Dot.allCases.allSatisfy({ dots[$0] != nil }) else { return nil }
        func at(_ dot: Dot) -> Vec3 { dots[dot] ?? .zero }
        let height = max(bounds.size.y, 1e-3)
        let hips = at(.leftHip).lerp(to: at(.rightHip), 0.5)
        let shoulders = at(.leftShoulder).lerp(to: at(.rightShoulder), 0.5)
        let ground = bounds.min.y
        var names: [String] = []
        var parents: [Int?] = []
        var positions: [Vec3] = []
        func add(_ name: String, _ parent: String?, _ position: Vec3) {
            names.append(name)
            parents.append(parent.flatMap { names.firstIndex(of: $0) })
            positions.append(position)
        }
        add("hips", nil, hips)
        add("spine", "hips", hips.lerp(to: shoulders, 0.3))
        add("chest", "spine", hips.lerp(to: shoulders, 0.65))
        add("neck", "chest", shoulders.lerp(to: at(.chin), 0.4))
        add("head", "neck", at(.chin).lerp(to: at(.head), 0.15))
        var tips: [String: Vec3] = ["head": at(.head)]
        for side in ["left", "right"] {
            func dot(_ name: String) -> Vec3 { Dot(rawValue: side + name).map(at) ?? .zero }
            add("\(side)Shoulder", "chest", shoulders.lerp(to: dot("Shoulder"), 0.25))
            add("\(side)UpperArm", "\(side)Shoulder", dot("Shoulder"))
            add("\(side)LowerArm", "\(side)UpperArm", dot("Elbow"))
            add("\(side)Hand", "\(side)LowerArm", dot("Wrist"))
            tips["\(side)Hand"] = dot("Wrist") + (dot("Wrist") - dot("Elbow")) * 0.45
            add("\(side)UpperLeg", "hips", dot("Hip"))
            add("\(side)LowerLeg", "\(side)UpperLeg", dot("Knee"))
            add("\(side)Foot", "\(side)LowerLeg", dot("Ankle"))
            let toes = Vec3(dot("Ankle").x, ground + (dot("Ankle").y - ground) * 0.35, dot("Ankle").z + height * 0.07)
            add("\(side)Toes", "\(side)Foot", toes)
            tips["\(side)Toes"] = toes + Vec3(0, 0, height * 0.04)
        }
        return ObjectRig(names: names, parents: parents, positions: positions, standard: .humanoid, tips: tips)
    }
}
