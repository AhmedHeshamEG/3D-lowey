import Foundation

/// The timeline's rows as a tree: animated objects appear under the groups they live in, so the timeline is
/// organised the way the scene is (Procreate Dreams-style track groups). A group row stands for everything
/// animated inside it; collapsed, it shows all their keys on one line and moves them together.
public enum TimelineOutline {
    public struct Entry: Hashable, Sendable {
        public var id: ObjectID
        /// Nesting among the rows shown (0 = top level).
        public var depth: Int
        /// Has rows under it (a group with something animated inside).
        public var isGroup: Bool
        /// Its children are hidden.
        public var isCollapsed: Bool
    }

    /// Rows for every object in `include` (animated or selected) and the groups that contain them, in outliner order.
    public static func entries(scene: Scene, include: Set<ObjectID>, collapsed: Set<ObjectID>) -> [Entry] {
        var shown: [ObjectID: Bool] = [:]
        func shows(_ id: ObjectID) -> Bool {
            if let known = shown[id] { return known }
            let result = include.contains(id) || (scene.objects[id]?.children ?? []).contains { shows($0) }
            shown[id] = result
            return result
        }
        var result: [Entry] = []
        func visit(_ id: ObjectID, depth: Int) {
            guard shows(id) else { return }
            let children = (scene.objects[id]?.children ?? []).filter { shows($0) }
            let isGroup = !children.isEmpty
            let isCollapsed = isGroup && collapsed.contains(id)
            result.append(Entry(id: id, depth: depth, isGroup: isGroup, isCollapsed: isCollapsed))
            guard !isCollapsed else { return }
            for child in children {
                visit(child, depth: depth + 1)
            }
        }
        for root in scene.roots {
            visit(root, depth: 0)
        }
        return result
    }

    /// The animated objects a row stands for: a group's whole subtree, or just the object.
    public static func members(of id: ObjectID, scene: Scene, animated: Set<ObjectID>) -> [ObjectID] {
        scene.subtree(of: id).filter { animated.contains($0) }
    }
}
