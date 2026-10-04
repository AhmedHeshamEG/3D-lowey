import Foundation

/// Where the editor camera was looking. Saved with the scene so reopening a scene
/// puts you exactly where you left it.
public struct Viewpoint: Codable, Hashable, Sendable {
    public enum Projection: String, Codable, Sendable {
        case perspective, orthographic
    }

    public var target: Vec3
    /// Degrees around Y.
    public var yaw: Double
    /// Degrees above the horizon (-89...89).
    public var pitch: Double
    public var distance: Double
    public var projection: Projection
    public var fieldOfView: Double

    public init(
        target: Vec3 = Vec3(0, 0.5, 0), yaw: Double = 35, pitch: Double = 28, distance: Double = 9,
        projection: Projection = .perspective, fieldOfView: Double = 50
    ) {
        self.target = target
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.projection = projection
        self.fieldOfView = fieldOfView
    }

    /// Camera position implied by target/yaw/pitch/distance.
    public var eye: Vec3 {
        let yawRad = yaw * .pi / 180
        let pitchRad = pitch * .pi / 180
        let offset = Vec3(sin(yawRad) * cos(pitchRad), sin(pitchRad), cos(yawRad) * cos(pitchRad)) * distance
        return target + offset
    }

    /// Camera orientation looking at the target (camera looks down its -Z).
    public var rotation: Quat {
        let yawRad = yaw * .pi / 180
        let pitchRad = pitch * .pi / 180
        return (Quat(angle: yawRad, axis: .unitY) * Quat(angle: -pitchRad, axis: .unitX)).normalized
    }

    public static let `default` = Viewpoint()
}

/// A scene: objects (a forest of trees with parents and children), its look,
/// its cameras and its timeline.
public struct Scene: Codable, Hashable, Sendable, Identifiable {
    public var id: SceneID
    public var name: String
    public var objects: [ObjectID: SceneObject]
    /// Top-level objects in outliner order.
    public var roots: [ObjectID]
    /// Scene-specific look. `nil` inherits the project look.
    public var look: Look?
    public var activeCamera: ObjectID?
    public var viewpoint: Viewpoint
    public var timeline: Timeline

    public init(
        id: SceneID, name: String, objects: [ObjectID: SceneObject] = [:], roots: [ObjectID] = [],
        look: Look? = nil, activeCamera: ObjectID? = nil, viewpoint: Viewpoint = .default, timeline: Timeline = Timeline()
    ) {
        self.id = id
        self.name = name
        self.objects = objects
        self.roots = roots
        self.look = look
        self.activeCamera = activeCamera
        self.viewpoint = viewpoint
        self.timeline = timeline
    }

    public subscript(id: ObjectID) -> SceneObject? {
        get { objects[id] }
        set { objects[id] = newValue }
    }

    /// Camera objects in outliner order.
    public var cameras: [ObjectID] {
        orderedIDs().filter { objects[$0]?.kind == .camera }
    }

    /// Children list of `parent` (roots when `nil`).
    public func childIDs(of parent: ObjectID?) -> [ObjectID] {
        guard let parent else { return roots }
        return objects[parent]?.children ?? []
    }

    /// Depth-first, outliner order.
    public func orderedIDs() -> [ObjectID] {
        var result: [ObjectID] = []
        result.reserveCapacity(objects.count)
        func visit(_ id: ObjectID) {
            result.append(id)
            for child in objects[id]?.children ?? [] {
                visit(child)
            }
        }
        for root in roots {
            visit(root)
        }
        return result
    }

    /// `id` and all its descendants, depth-first.
    public func subtree(of id: ObjectID) -> [ObjectID] {
        var result: [ObjectID] = []
        func visit(_ node: ObjectID) {
            guard objects[node] != nil else { return }
            result.append(node)
            for child in objects[node]?.children ?? [] {
                visit(child)
            }
        }
        visit(id)
        return result
    }

    /// Chain of ancestors from the parent up to the root.
    public func ancestors(of id: ObjectID) -> [ObjectID] {
        var result: [ObjectID] = []
        var current = objects[id]?.parent
        var guardCount = 0
        while let node = current, guardCount < 10000 {
            result.append(node)
            current = objects[node]?.parent
            guardCount += 1
        }
        return result
    }

    public func isAncestor(_ ancestor: ObjectID, of id: ObjectID) -> Bool {
        ancestors(of: id).contains(ancestor)
    }

    /// World transform (parent chain composed).
    public func worldTransform(of id: ObjectID) -> Transform {
        guard let object = objects[id] else { return .identity }
        guard let parent = object.parent else { return object.transform }
        return worldTransform(of: parent) * object.transform
    }

    /// Effective visibility (hidden parents hide children).
    public func isEffectivelyVisible(_ id: ObjectID) -> Bool {
        guard let object = objects[id] else { return false }
        if !object.isVisible { return false }
        return ancestors(of: id).allSatisfy { objects[$0]?.isVisible ?? true }
    }

    /// Effective lock (locked parents lock children).
    public func isEffectivelyLocked(_ id: ObjectID) -> Bool {
        guard let object = objects[id] else { return false }
        if object.isLocked { return true }
        return ancestors(of: id).contains { objects[$0]?.isLocked ?? false }
    }

    /// Structural integrity check used by tests and by the loader (repairs are the migrator's job).
    public func validate() -> [String] {
        var problems: [String] = []
        var seen = Set<ObjectID>()
        for id in orderedIDs() where !seen.insert(id).inserted {
            problems.append("\(id) appears twice in the hierarchy")
        }
        for (id, object) in objects {
            if object.id != id { problems.append("\(id) key mismatch") }
            if !seen.contains(id) { problems.append("\(id) is orphaned") }
            if let parent = object.parent {
                if objects[parent]?.children.contains(id) != true {
                    problems.append("\(id) missing from parent \(parent)")
                }
            } else if !roots.contains(id) {
                problems.append("\(id) has no parent but is not a root")
            }
        }
        return problems
    }

    // MARK: Codable (objects as an id-keyed JSON object, stable key order via the encoder)

    private enum CodingKeys: String, CodingKey {
        case id, name, objects, roots, look, activeCamera, viewpoint, timeline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SceneID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        objects = try container.decodeIfPresent([ObjectID: SceneObject].self, forKey: .objects) ?? [:]
        roots = try container.decodeIfPresent([ObjectID].self, forKey: .roots) ?? []
        look = try container.decodeIfPresent(Look.self, forKey: .look)
        activeCamera = try container.decodeIfPresent(ObjectID.self, forKey: .activeCamera)
        viewpoint = try container.decodeIfPresent(Viewpoint.self, forKey: .viewpoint) ?? .default
        timeline = try container.decodeIfPresent(Timeline.self, forKey: .timeline) ?? Timeline()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(objects, forKey: .objects)
        try container.encode(roots, forKey: .roots)
        try container.encodeIfPresent(look, forKey: .look)
        try container.encodeIfPresent(activeCamera, forKey: .activeCamera)
        try container.encode(viewpoint, forKey: .viewpoint)
        try container.encode(timeline, forKey: .timeline)
    }
}

/// Project-level settings and look. Stored in `project.json`.
public struct ProjectInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: ProjectID
    public var name: String
    public var created: Date
    public var modified: Date
    public var look: Look
    public var sceneOrder: [SceneID]
    public var sceneNames: [SceneID: String]
    public var lastOpenedScene: SceneID?
    /// The project's own Looks ("My Look"), stored only when there are some.
    private var looks: [LookPreset]?

    /// The project's own Looks ("My Look" duplicates of the built-ins).
    public var customLooks: [LookPreset] {
        get { looks ?? [] }
        set { looks = newValue.isEmpty ? nil : newValue }
    }

    public init(
        id: ProjectID, name: String, created: Date = Date(), modified: Date = Date(), look: Look = .default,
        sceneOrder: [SceneID] = [], sceneNames: [SceneID: String] = [:], lastOpenedScene: SceneID? = nil
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.modified = modified
        self.look = look
        self.sceneOrder = sceneOrder
        self.sceneNames = sceneNames
        self.lastOpenedScene = lastOpenedScene
    }
}

/// What an editing session mutates: the project's info (look, palette) and one scene.
/// Every change goes through an `EditCommand` applied to a `Document`.
public struct Document: Codable, Hashable, Sendable {
    public var project: ProjectInfo
    public var scene: Scene

    public init(project: ProjectInfo, scene: Scene) {
        self.project = project
        self.scene = scene
    }

    /// The look in effect for this scene.
    public var effectiveLook: Look { scene.look ?? project.look }

    public var palette: Palette { effectiveLook.palette }
}
