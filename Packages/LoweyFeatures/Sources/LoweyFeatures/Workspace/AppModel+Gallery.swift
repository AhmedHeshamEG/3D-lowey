import Foundation
import HmmDocuments
import LoweyCore

/// Home's arrangement: stacks, the sort, and acting on several projects at once.
extension AppModel {
    /// The projects as the gallery sees them.
    var galleryItems: [GalleryItem] {
        projects.map { GalleryItem(id: $0.id.raw, name: $0.info.name, created: $0.info.created, modified: $0.info.modified) }
    }

    func project(_ id: String) -> ProjectSummary? {
        projects.first { $0.id.raw == id }
    }

    func setGallerySort(_ sort: GallerySort) {
        guard gallery.sort != sort else { return }
        gallery.sort = sort
        saveGallery()
    }

    /// Stacks projects together and returns the stack's id.
    @discardableResult
    func stackProjects(_ ids: [String], named name: String? = nil) -> String? {
        guard !ids.isEmpty else { return nil }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = gallery.stack(ids, name: title?.isEmpty == false ? title ?? "" : String(localized: "Stack"))
        saveGallery()
        return id
    }

    /// Drops one project onto another (a new stack of the two) or onto a stack (it joins).
    func drop(_ project: String, onto target: GalleryEntry) {
        switch target {
        case let .item(item):
            guard item.id != project else { return }
            stackProjects([item.id, project])
        case let .stack(stack, _):
            gallery.add([project], to: stack.id)
            saveGallery()
        }
    }

    func addToStack(_ ids: [String], stack: String) {
        gallery.add(ids, to: stack)
        saveGallery()
    }

    func moveOutOfStacks(_ ids: [String]) {
        gallery.remove(ids)
        saveGallery()
    }

    func unstack(_ stack: String) {
        gallery.unstack(stack)
        saveGallery()
    }

    func renameStack(_ stack: String, to name: String) {
        gallery.rename(stack, to: name)
        saveGallery()
    }

    // MARK: Several at once

    func duplicate(_ ids: [String]) {
        for id in ids {
            if let summary = project(id) { duplicate(summary) }
        }
    }

    func archive(_ ids: [String]) {
        let chosen = ids.compactMap(project)
        for summary in chosen {
            _ = try? projectStore.archiveProject(at: summary.url)
        }
        refreshProjects()
        refreshArchived()
        if !chosen.isEmpty { show(chosen.count == 1 ? "Archived. Find it in Home ▸ Archive" : "Archived \(chosen.count) projects") }
    }

    func delete(_ ids: [String]) {
        for summary in ids.compactMap(project) {
            delete(summary)
        }
    }
}
