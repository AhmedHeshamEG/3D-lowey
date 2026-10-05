import Foundation

/// A measurement kept on the stage: a line between two points with its length beside it, in the project's units. It
/// belongs to the object it measures (it moves with it) and, like sketches, it's drawn on the stage only: exports and
/// renders never show it.
public struct DimensionRecipe: Codable, Hashable, Sendable {
    /// The two ends, in the dimension object's own space.
    public var start: Vec3
    public var end: Vec3

    public init(start: Vec3, end: Vec3) {
        self.start = start
        self.end = end
    }

    public var length: Double { start.distance(to: end) }
}

public extension ModelingOperations {
    /// Keeps a measurement between two world points. It's put under `owner` (the object both ends are on) so it moves
    /// with it; nil keeps it in the world.
    static func keepDimension(from start: Vec3, to end: Vec3, owner: ObjectID?, in scene: Scene, id: ObjectID) -> EditCommand {
        let parent = owner.flatMap { scene.objects[$0] != nil ? $0 : nil }
        let frame = parent.map { scene.worldTransform(of: $0) } ?? .identity
        let recipe = DimensionRecipe(start: frame.inverseApply(to: start), end: frame.inverseApply(to: end))
        var object = SceneObject(id: id, name: "Dimension", kind: .dimension(recipe))
        object.parent = parent
        return .batch("Keep dimension", [.insert(SceneFragment(objects: [object], roots: [id]), parent: parent, index: nil)])
    }

    /// Every kept dimension with its ends in the world, for the stage to draw.
    static func dimensions(in scene: Scene) -> [(id: ObjectID, start: Vec3, end: Vec3)] {
        scene.objects.values.compactMap { object in
            guard case let .dimension(recipe) = object.kind, scene.isEffectivelyVisible(object.id) else { return nil }
            let world = scene.worldTransform(of: object.id)
            return (object.id, world.apply(to: recipe.start), world.apply(to: recipe.end))
        }
        .sorted { $0.id.raw < $1.id.raw }
    }
}
