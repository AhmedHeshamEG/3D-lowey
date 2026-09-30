import Foundation

public extension EditCommand {
    /// Applies the command and returns its exact inverse plus what changed.
    /// Atomic: on error the document is left untouched.
    func apply(to document: inout Document) throws -> (inverse: EditCommand, changes: ChangeSet) {
        var working = document
        let result = try applyUnchecked(to: &working)
        document = working
        return result
    }

    private func applyUnchecked(to document: inout Document) throws -> (inverse: EditCommand, changes: ChangeSet) {
        switch self {
        case let .insert(fragment, parent, index):
            let ids = try Self.insert(fragment, parent: parent, index: index, into: &document.scene)
            return (.delete(fragment.roots), ChangeSet(objects: ids, hierarchy: true))

        case let .delete(ids):
            var entries: [RestoreEntry] = []
            var changed = Set<ObjectID>()
            for id in ids {
                // Already removed as a descendant of an earlier id in the list.
                guard document.scene.objects[id] != nil else { continue }
                let entry = try Self.remove(id, from: &document.scene)
                changed.formUnion(entry.fragment.objects.map(\.id))
                entries.append(entry)
            }
            return (.restore(entries.reversed()), ChangeSet(objects: changed, hierarchy: true))

        case let .restore(entries):
            var roots: [ObjectID] = []
            var changed = Set<ObjectID>()
            for entry in entries {
                let ids = try Self.insert(entry.fragment, parent: entry.parent, index: entry.index, into: &document.scene)
                changed.formUnion(ids)
                roots.append(contentsOf: entry.fragment.roots)
            }
            return (.delete(roots.reversed()), ChangeSet(objects: changed, hierarchy: true))

        case let .setProperties(changes):
            var inverse: [PropertyChange] = []
            var changed = Set<ObjectID>()
            for change in changes {
                guard var object = document.scene.objects[change.object] else {
                    throw CommandError.objectNotFound(change.object)
                }
                if let value = change.value, let spec = change.key.spec, spec.type != value.type,
                   !(spec.type == .float && value.type == .int) {
                    throw CommandError.typeMismatch(key: change.key, expected: spec.type, got: value.type)
                }
                inverse.append(PropertyChange(object: change.object, key: change.key, value: object.properties[change.key]))
                object.properties[change.key] = change.value
                document.scene.objects[change.object] = object
                changed.insert(change.object)
            }
            return (.setProperties(inverse.reversed()), ChangeSet(objects: changed))

        case let .rename(id, name):
            guard var object = document.scene.objects[id] else { throw CommandError.objectNotFound(id) }
            let old = object.name
            object.name = name
            document.scene.objects[id] = object
            return (.rename(id, old), ChangeSet(objects: [id], hierarchy: true))

        case let .setKind(id, kind):
            guard var object = document.scene.objects[id] else { throw CommandError.objectNotFound(id) }
            let old = object.kind
            object.kind = kind
            document.scene.objects[id] = object
            return (.setKind(id, old), ChangeSet(objects: [id]))

        case let .reparent(entries):
            var inverse: [ReparentEntry] = []
            var changed = Set<ObjectID>()
            for entry in entries {
                try inverse.append(Self.reparent(entry, in: &document.scene))
                changed.formUnion(document.scene.subtree(of: entry.object))
            }
            return (.reparent(inverse.reversed()), ChangeSet(objects: changed, hierarchy: true))

        case let .setLook(look, scope):
            switch scope {
            case .project:
                guard let look else { throw CommandError.empty }
                let old = document.project.look
                document.project.look = look
                return (.setLook(old, scope: .project), ChangeSet(objects: Set(document.scene.objects.keys), look: true))
            case .scene:
                let old = document.scene.look
                document.scene.look = look
                return (.setLook(old, scope: .scene), ChangeSet(objects: Set(document.scene.objects.keys), look: true))
            }

        case let .renameScene(name):
            let old = document.scene.name
            document.scene.name = name
            document.project.sceneNames[document.scene.id] = name
            return (.renameScene(old), ChangeSet(scene: true))

        case let .setActiveCamera(camera):
            if let camera, document.scene.objects[camera] == nil { throw CommandError.objectNotFound(camera) }
            let old = document.scene.activeCamera
            document.scene.activeCamera = camera
            return (.setActiveCamera(old), ChangeSet(scene: true))

        case let .setTimeline(timeline):
            let old = document.scene.timeline
            document.scene.timeline = timeline
            return (.setTimeline(old), ChangeSet(objects: Set(timeline.tracks.map(\.target) + old.tracks.map(\.target)), scene: true))

        case let .setShadowPaint(id, dabs):
            guard var object = document.scene.objects[id] else { throw CommandError.objectNotFound(id) }
            let old = object.shadowDabs
            object.shadowDabs = dabs
            document.scene.objects[id] = object
            return (.setShadowPaint(id, old), ChangeSet(objects: [id]))

        case let .setCustomLooks(looks):
            let old = document.project.customLooks
            document.project.customLooks = looks
            return (.setCustomLooks(old), ChangeSet(objects: Set(document.scene.objects.keys), look: true))

        case let .setTracks(edits):
            var inverse: [TrackEdit] = []
            var changed = Set<ObjectID>()
            for edit in edits {
                if let track = edit.track, track.id != edit.id { throw CommandError.empty }
                var tracks = document.scene.timeline.tracks
                if let existing = tracks.firstIndex(where: { $0.id == edit.id }) {
                    let old = tracks[existing]
                    changed.insert(old.target)
                    if let track = edit.track {
                        tracks[existing] = track
                        changed.insert(track.target)
                        inverse.append(TrackEdit(id: edit.id, track: old, index: existing))
                    } else {
                        tracks.remove(at: existing)
                        inverse.append(TrackEdit(id: edit.id, track: old, index: existing))
                    }
                } else if let track = edit.track {
                    let at = min(max(edit.index ?? tracks.count, 0), tracks.count)
                    tracks.insert(track, at: at)
                    changed.insert(track.target)
                    inverse.append(TrackEdit(id: edit.id, track: nil))
                } else {
                    // Removing a track that isn't there: a no-op (keeps scripts forgiving).
                    continue
                }
                document.scene.timeline.tracks = tracks
            }
            return (.setTracks(inverse.reversed()), ChangeSet(objects: changed, scene: true))

        case let .batch(label, commands):
            var inverses: [EditCommand] = []
            var changes = ChangeSet()
            for command in commands {
                let result = try command.applyUnchecked(to: &document)
                inverses.append(result.inverse)
                changes.formUnion(result.changes)
            }
            return (.batch(label, inverses.reversed()), changes)
        }
    }

    // MARK: Hierarchy primitives

    private static func insert(
        _ fragment: SceneFragment, parent: ObjectID?, index: Int?, into scene: inout Scene
    ) throws -> Set<ObjectID> {
        if let parent, scene.objects[parent] == nil { throw CommandError.objectNotFound(parent) }
        let rootSet = Set(fragment.roots)
        var ids = Set<ObjectID>()
        for var object in fragment.objects {
            if scene.objects[object.id] != nil || ids.contains(object.id) {
                throw CommandError.duplicateObject(object.id)
            }
            if rootSet.contains(object.id) { object.parent = parent }
            scene.objects[object.id] = object
            ids.insert(object.id)
        }
        // Attach roots in order at the requested index.
        var siblings = scene.childIDs(of: parent)
        let insertAt = min(max(index ?? siblings.count, 0), siblings.count)
        siblings.insert(contentsOf: fragment.roots, at: insertAt)
        setChildren(siblings, of: parent, in: &scene)
        return ids
    }

    private static func remove(_ id: ObjectID, from scene: inout Scene) throws -> RestoreEntry {
        guard let object = scene.objects[id] else { throw CommandError.objectNotFound(id) }
        let parent = object.parent
        var siblings = scene.childIDs(of: parent)
        let index = siblings.firstIndex(of: id) ?? siblings.count
        siblings.removeAll { $0 == id }
        setChildren(siblings, of: parent, in: &scene)
        let subtree = scene.subtree(of: id)
        let objects = subtree.compactMap { scene.objects[$0] }
        for node in subtree {
            scene.objects[node] = nil
        }
        return RestoreEntry(fragment: SceneFragment(objects: objects, roots: [id]), parent: parent, index: index)
    }

    private static func reparent(_ entry: ReparentEntry, in scene: inout Scene) throws -> ReparentEntry {
        guard var object = scene.objects[entry.object] else { throw CommandError.objectNotFound(entry.object) }
        if let newParent = entry.parent {
            guard scene.objects[newParent] != nil else { throw CommandError.objectNotFound(newParent) }
            if newParent == entry.object || scene.isAncestor(entry.object, of: newParent) {
                throw CommandError.cycle(entry.object)
            }
        }
        let oldParent = object.parent
        var oldSiblings = scene.childIDs(of: oldParent)
        let oldIndex = oldSiblings.firstIndex(of: entry.object) ?? oldSiblings.count
        let oldTransform = object.transform
        oldSiblings.removeAll { $0 == entry.object }
        setChildren(oldSiblings, of: oldParent, in: &scene)

        object = scene.objects[entry.object] ?? object
        object.parent = entry.parent
        if let transform = entry.transform { object.transform = transform }
        scene.objects[entry.object] = object

        var newSiblings = scene.childIDs(of: entry.parent)
        let insertAt = min(max(entry.index ?? newSiblings.count, 0), newSiblings.count)
        newSiblings.insert(entry.object, at: insertAt)
        setChildren(newSiblings, of: entry.parent, in: &scene)

        return ReparentEntry(
            object: entry.object, parent: oldParent, index: oldIndex,
            transform: entry.transform != nil ? oldTransform : nil
        )
    }

    private static func setChildren(_ children: [ObjectID], of parent: ObjectID?, in scene: inout Scene) {
        if let parent {
            scene.objects[parent]?.children = children
        } else {
            scene.roots = children
        }
    }
}
