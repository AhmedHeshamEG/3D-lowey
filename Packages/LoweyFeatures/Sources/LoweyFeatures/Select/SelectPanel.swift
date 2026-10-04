import HmmDesign
import LoweyCore
import SwiftUI

/// Select: tap or lasso, select similar or everything, and the outliner (the scene's hierarchy: tap to select,
/// eye and lock, touch and hold to rename, move or delete).
struct SelectPanel: View {
    @Bindable var editor: EditorModel
    @State private var expanded: Set<ObjectID> = []
    @State private var renaming: ObjectID?
    @State private var renameText = ""

    var body: some View {
        HmmPanel("Select", width: 340, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                HStack(spacing: HmmSpacing.xs) {
                    ChoiceChip(title: "Tap", systemName: "hand.point.up.left", isOn: editor.tool == .select) { editor.tool = .select }
                    ChoiceChip(title: "Lasso", systemName: "lasso", isOn: editor.tool == .lasso) { editor.tool = .lasso }
                        .accessibilityIdentifier("tool-lasso")
                }
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Similar", systemName: "square.on.square") { editor.selectSimilar() }
                        .disabled(editor.selection.isEmpty)
                    HmmPillButton("All", systemName: "checkmark.circle") { editor.selectAll() }
                    HmmPillButton("None", systemName: "xmark.circle") { editor.setSelection([]) }
                }
                Hint("Touch and hold an object on the stage to add it to the selection.")
                HmmSectionHeader("Outliner · \(editor.scene.objects.count)")
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.id) { row in
                        OutlinerRow(object: row.object, depth: row.depth, isExpanded: expanded.contains(row.id),
                                    isSelected: editor.selection.contains(row.id),
                                    toggleExpanded: { expanded.formSymmetricDifference([row.id]) },
                                    select: { editor.select(row.id) }, toggleVisible: { editor.toggleVisible(row.id) },
                                    toggleLock: { editor.toggleLock(row.id) })
                            .contextMenu { menu(for: row.object) }
                    }
                }
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming { editor.rename(renaming, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onChange(of: editor.selection) { _, selection in
            for id in selection {
                expanded.formUnion(editor.scene.ancestors(of: id))
            }
        }
    }

    private var rows: [(id: ObjectID, object: SceneObject, depth: Int)] {
        var result: [(id: ObjectID, object: SceneObject, depth: Int)] = []
        func visit(_ id: ObjectID, depth: Int) {
            guard let object = editor.scene.objects[id] else { return }
            result.append((id, object, depth))
            guard expanded.contains(id) else { return }
            for child in object.children {
                visit(child, depth: depth + 1)
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
            Button("Move to top level", systemImage: "arrow.up.left") { editor.reparent([object.id], to: nil) }
        }
        let groups = editor.scene.orderedIDs().filter { id in
            editor.scene.objects[id]?.kind == .group && id != object.id && !editor.scene.isAncestor(object.id, of: id) && object.parent != id
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
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            Color.clear.frame(width: CGFloat(depth) * 14, height: 1)
            Button(action: toggleExpanded) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 32)
                    .opacity(object.children.isEmpty ? 0 : 1)
            }
            .buttonStyle(.plain)
            .disabled(object.children.isEmpty)
            .accessibilityLabel(isExpanded ? "Fold \(object.name)" : "Unfold \(object.name)")
            Text(object.name)
                .font(.hmm(.body, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(object.isVisible ? theme.text : theme.text3)
                .lineLimit(1)
            Spacer(minLength: HmmSpacing.xxs)
            icon(object.isLocked ? "lock.fill" : "lock.open", on: object.isLocked, label: object.isLocked ? "Unlock" : "Lock", action: toggleLock)
            icon(object.isVisible ? "eye" : "eye.slash", on: !object.isVisible, label: object.isVisible ? "Hide" : "Show", action: toggleVisible)
        }
        .padding(.horizontal, HmmSpacing.xxs)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(isSelected ? theme.accent.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func icon(_ name: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13)).foregroundStyle(on ? theme.accent : theme.text3).frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(object.name)")
    }
}
