import Foundation

/// A trigger: one tap (or one key of a keyboard) puts a character in an expression or a saved pose, or swaps what it
/// holds or wears. While a take records, triggers are performed like everything else: pressed and let go in time.
public struct Trigger: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A whole face in one go (`FaceExpression`).
        case expression
        /// One of the character's saved poses (`PoseLibrary`).
        case pose
        /// Shows one thing and hides the others it takes turns with (props, hand shapes, drawn mouths).
        case swap
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// The key that fires it on a keyboard ("1", "a"…), if any.
    public var key: String?
    /// Only while held (let go and the character returns to what it was); otherwise it stays.
    public var holds: Bool
    public var expression: FaceExpression?
    /// A saved pose's id.
    public var pose: String?
    public var show: ObjectID?
    public var hide: [ObjectID]

    public init(id: String, name: String, kind: Kind, key: String? = nil, holds: Bool = false, expression: FaceExpression? = nil,
                pose: String? = nil, show: ObjectID? = nil, hide: [ObjectID] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.key = key
        self.holds = holds
        self.expression = expression
        self.pose = pose
        self.show = show
        self.hide = hide
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, key, holds, expression, pose, show, hide }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        holds = try c.decodeIfPresent(Bool.self, forKey: .holds) ?? false
        expression = try c.decodeIfPresent(FaceExpression.self, forKey: .expression)
        pose = try c.decodeIfPresent(String.self, forKey: .pose)
        show = try c.decodeIfPresent(ObjectID.self, forKey: .show)
        hide = try c.decodeIfPresent([ObjectID].self, forKey: .hide) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(key, forKey: .key)
        if holds { try c.encode(holds, forKey: .holds) }
        try c.encodeIfPresent(expression, forKey: .expression)
        try c.encodeIfPresent(pose, forKey: .pose)
        try c.encodeIfPresent(show, forKey: .show)
        if !hide.isEmpty { try c.encode(hide, forKey: .hide) }
    }
}

public extension PropertyKey {
    /// A character's triggers (JSON list of `Trigger`), kept on it like its poses, so they travel with it.
    static let triggers: PropertyKey = "triggers"
}

/// A character's deck of triggers.
public enum TriggerDeck {
    /// The keys offered to new triggers, in order.
    public static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    public static func triggers(of character: SceneObject) -> [Trigger] {
        guard let text = character[.triggers]?.stringValue, let data = text.data(using: .utf8) else { return [] }
        return (try? LoweyJSON.decode([Trigger].self, from: data)) ?? []
    }

    /// The property change that stores `triggers` on the character.
    public static func storing(_ triggers: [Trigger], on character: ObjectID) -> PropertyChange {
        let text = (try? LoweyJSON.encode(triggers)).flatMap { String(bytes: $0, encoding: .utf8) }
        return PropertyChange(object: character, key: .triggers, value: triggers.isEmpty ? nil : text.map(PropertyValue.string))
    }

    /// The first key no trigger in the deck uses.
    public static func freeKey(in deck: [Trigger]) -> String? {
        let used = Set(deck.compactMap(\.key))
        return keys.first { !used.contains($0) }
    }

    /// One trigger per object: each shows its own and hides the rest. Named after the objects.
    public static func swap(of objects: [ObjectID], in scene: Scene, deck: [Trigger], ids: inout IDFactory) -> [Trigger] {
        var result: [Trigger] = []
        for object in objects where scene.objects[object] != nil {
            let trigger = Trigger(id: ids.next(TrackID.self).raw, name: scene.objects[object]?.name ?? "Swap", kind: .swap, key: freeKey(in: deck + result),
                                  show: object, hide: objects.filter { $0 != object })
            result.append(trigger)
        }
        return result
    }

    /// What firing the trigger sets (on the character, its joints and its swapped things), in `scene` as shown.
    public static func changes(for trigger: Trigger, on character: ObjectID, in scene: Scene, rigs: [AssetID: RigAsset] = [:]) -> [PropertyChange] {
        switch trigger.kind {
        case .expression:
            guard let expression = trigger.expression else { return [] }
            return expression.values.sorted { $0.key.rawValue < $1.key.rawValue }.map { PropertyChange(object: character, key: $0.key, value: $0.value) }
        case .pose:
            guard let root = scene.objects[character], let pose = PoseLibrary.poses(of: root).first(where: { $0.id == trigger.pose }) else { return [] }
            // Every dial and joint the pose names, whether or not it differs now: the trigger is a state to return from.
            var changes = pose.dials.sorted { $0.key.rawValue < $1.key.rawValue }.map { PropertyChange(object: character, key: $0.key, value: $0.value) }
            changes += PoseLibrary.applying(CharacterPose(id: pose.id, name: pose.name, joints: pose.joints, hips: pose.hips), to: character,
                                            in: scene, rigs: rigs).filter { $0.value != nil && !PoseLibrary.dialKeys.contains($0.key) }
            return changes
        case .swap:
            var changes: [PropertyChange] = []
            if let show = trigger.show, scene.objects[show] != nil { changes.append(PropertyChange(object: show, key: .visible, value: .bool(true))) }
            for id in trigger.hide where scene.objects[id] != nil {
                changes.append(PropertyChange(object: id, key: .visible, value: .bool(false)))
            }
            return changes
        }
    }

    /// The changes that undo `changes`: each property back to what `scene` shows now (the value a held trigger
    /// returns to when it's let go).
    public static func restoring(_ changes: [PropertyChange], in scene: Scene) -> [PropertyChange] {
        changes.map { change in
            let object = scene.objects[change.object]
            let current: PropertyValue? = switch change.key {
            case .position: object.map { .vec3($0.transform.position) }
            case .rotation: object.map { .quat($0.transform.rotation) }
            case .scale: object.map { .vec3($0.transform.scale) }
            case .visible: .bool(object?.isVisible ?? true)
            default: object?[change.key] ?? Self.resting(change)
            }
            return PropertyChange(object: change.object, key: change.key, value: current)
        }
    }

    /// A value that means "as at rest" for a property the object doesn't carry yet.
    static func resting(_ change: PropertyChange) -> PropertyValue? {
        switch change.value {
        case .float: .float(0)
        case .quat: change.key.boneJoint != nil ? nil : .quat(.identity)
        case .enumeration where change.key == .mouth: .enumeration(Viseme.X.rawValue)
        default: nil
        }
    }

    /// The timeline with the trigger's state as held keys at `time` (a channel keyed for the first time also gets its
    /// present value at 0, so nothing before the trigger changes).
    public static func keyed(_ changes: [PropertyChange], at time: Double, in scene: Scene, timeline: Timeline, ids: inout IDFactory) -> [TrackEdit] {
        let before = restoring(changes, in: scene)
        return zip(changes, before).compactMap { change, old in
            guard let value = change.value else { return nil }
            var track = timeline.track(for: change.object, change.key) ?? Track(id: ids.next(TrackID.self), target: change.object, property: change.key)
            if track.keyframes.isEmpty, time > 1e-6, let rest = old.value {
                track.setKey(Keyframe(time: 0, value: rest, easing: .step))
            }
            track.setKey(Keyframe(time: time, value: value, easing: .step))
            return TrackEdit(track)
        }
    }
}
