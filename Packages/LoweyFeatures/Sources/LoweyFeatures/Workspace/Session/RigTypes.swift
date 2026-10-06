import Foundation
import LoweyCore

/// Cast ▸ Rig (CONTEXT §10.5): what the Pencil does on the object being rigged, and the person rig being placed.
public struct RigSettings: Equatable {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// A stroke through a limb, tail or rope becomes a chain of bones.
        case bone
        /// The brush adds the chosen bone's weight where it passes (or takes it away).
        case weights

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .bone: "Draw a bone"
            case .weights: "Paint weights"
            }
        }

        public var systemImage: String {
            switch self {
            case .bone: "point.topleft.down.to.point.bottomright.curvepath"
            case .weights: "paintbrush.pointed"
            }
        }
    }

    public var mode: Mode = .bone
    /// The object being rigged.
    public var target: ObjectID?
    /// The joint whose weight the brush paints (skeleton index).
    public var joint: Int?
    /// The weight brush takes weight away instead.
    public var erase = false
    /// The weight brush's size in points and how much one pass gives.
    public var size: Double = 40
    public var strength: Double = 0.5
    /// Objects whose weights are being worked out.
    public var busy: Set<ObjectID> = []
    /// "Rig as a person": the dots on the model's front view.
    public var person: PersonRigging?

    public init() {}
}

/// The dots of "Rig as a person", in the rig's space on the plane through the model's middle (the stage looks at its
/// front). The body-pose model places them all; otherwise they're tapped one side at a time and mirrored.
public struct PersonRigging: Equatable {
    public var target: ObjectID
    public var dots: [HumanRig.Dot: Vec3]
    /// The dots placed by a tap or a drag (their other side follows them until it's placed itself).
    public var placed: Set<HumanRig.Dot>
    /// Whether the body-pose model found the person.
    public var found: Bool
    /// The bounds of the model in the rig's space.
    public var bounds: Bounds

    public init(target: ObjectID, dots: [HumanRig.Dot: Vec3], placed: Set<HumanRig.Dot>, found: Bool, bounds: Bounds) {
        self.target = target
        self.dots = dots
        self.placed = placed
        self.found = found
        self.bounds = bounds
    }

    /// The next dot to tap (none once the body-pose model found them, or every tapped dot is placed).
    public var next: HumanRig.Dot? {
        found ? nil : HumanRig.tapped.first { !placed.contains($0) }
    }
}
