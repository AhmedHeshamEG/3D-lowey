import LoweyCore
import LoweyRender
import SwiftUI

/// Hierarchy: tap to select, eye/lock toggles, context menu to rename, group, move.
struct OutlinerPanel: View {
    @Bindable var editor: EditorModel
    @State private var expanded: Set<ObjectID> = []
    @State private var renaming: ObjectID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Outliner").font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(editor.scene.objects.count)").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.id) { row in
                        OutlinerRow(
                            object: row.object, depth: row.depth,
                            isExpanded: expanded.contains(row.id),
                            isSelected: editor.selection.contains(row.id),
                            toggleExpanded: {
                                if expanded.contains(row.id) {
                                    expanded.remove(row.id)
                                } else {
                                    expanded.insert(row.id)
                                }
                            },
                            select: { editor.select(row.id) },
                            toggleVisible: { editor.toggleVisible(row.id) },
                            toggleLock: { editor.toggleLock(row.id) }
                        )
                        .contextMenu { menu(for: row.object) }
                    }
                }
            }
        }
        .padding(14)
        .panelStyle()
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming { editor.rename(renaming, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onChange(of: editor.selection) { _, selection in
            // Reveal selected objects.
            for id in selection {
                for ancestor in editor.scene.ancestors(of: id) {
                    expanded.insert(ancestor)
                }
            }
        }
    }

    private struct Row {
        var id: ObjectID
        var object: SceneObject
        var depth: Int
    }

    private var rows: [Row] {
        var result: [Row] = []
        func visit(_ id: ObjectID, depth: Int) {
            guard let object = editor.scene.objects[id] else { return }
            result.append(Row(id: id, object: object, depth: depth))
            if expanded.contains(id) {
                for child in object.children {
                    visit(child, depth: depth + 1)
                }
            }
        }
        for root in editor.scene.roots {
            visit(root, depth: 0)
        }
        return result
    }

    @ViewBuilder
    private func menu(for object: SceneObject) -> some View {
        Button("Rename", systemImage: "pencil") {
            renameText = object.name
            renaming = object.id
        }
        if object.parent != nil {
            Button("Move to top level", systemImage: "arrow.up.left") { editor.moveToTopLevel(object.id) }
        }
        let groups = editor.scene.orderedIDs().filter { id in
            editor.scene.objects[id]?.kind == .group && id != object.id && !editor.scene.isAncestor(object.id, of: id)
                && editor.scene.objects[object.id]?.parent != id
        }
        if !groups.isEmpty {
            Menu("Move into…") {
                ForEach(groups, id: \.self) { group in
                    Button(editor.scene.objects[group]?.name ?? "Group") { editor.reparent([object.id], to: group) }
                }
            }
        }
        Button("Frame", systemImage: "viewfinder") {
            editor.select(object.id)
            editor.frameSelection()
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            editor.setSelection([object.id])
            editor.deleteSelection()
        }
    }
}

private struct OutlinerRow: View {
    let object: SceneObject
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let toggleExpanded: () -> Void
    let select: () -> Void
    let toggleVisible: () -> Void
    let toggleLock: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(depth) * 14, height: 1)
            if object.children.isEmpty {
                Color.clear.frame(width: 22, height: 22)
            } else {
                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            Text(object.name)
                .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                .foregroundStyle(object.isVisible ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: toggleLock) {
                Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 12))
                    .foregroundStyle(object.isLocked ? Theme.accent : Theme.secondaryText.opacity(0.5))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            Button(action: toggleVisible) {
                Image(systemName: object.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(object.isVisible ? Theme.secondaryText : Theme.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Theme.accent.opacity(0.18) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}
