import HmmDesign
import LoweyCore
import SwiftUI

/// A hold-menu row's action when the thing can do it; nil, a dimmed row, when it can't. (A closure and `nil` in a
/// ternary is more than the type checker will work out for a main-actor action.)
@MainActor
func holdAction(if possible: Bool, _ action: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)? {
    possible ? action : nil
}

/// The hold menus of the things in a scene, in the one grammar (CONTEXT §4.1; the kit's `HmmHoldMenu`): Duplicate,
/// Rename, Copy and Paste first, then what fits the thing, Delete last. An object has the same menu on the stage, in
/// the outliner and on its timeline row.
extension EditorModel {
    /// The menu of some objects. Acting on it makes them the selection first.
    func holdMenu(for ids: [ObjectID], extras custom: [HmmHoldMenu.Item]? = nil) -> HmmHoldMenu {
        let objects = ids.compactMap { scene.objects[$0] }
        return HmmHoldMenu(duplicate: on(ids) { $0.duplicateSelection() },
                           rename: holdAction(if: objects.count == 1) { [weak self] in self?.renamingObject = ids.first },
                           copy: on(ids) { $0.copySelection() },
                           paste: holdAction(if: canPaste) { [weak self] in self?.paste() },
                           extras: custom ?? objectExtras(ids, objects),
                           delete: on(ids) { $0.deleteSelection() })
    }

    /// A finger held still on the stage with the Select tool: the menu of the object under it (nil: nothing there, or
    /// a tool that holds for something else). The held object becomes the selection unless it's already part of it;
    /// when other things were selected, the first extra adds it to them instead.
    func stageHoldMenu(at point: CGPoint) -> HmmHoldMenu? {
        guard tool == .select, !pickActive, performPhase == .idle, !flying, historyScrub == nil, let stage else { return nil }
        guard let id = overlayHit(at: point) ?? stage.pickObject(at: point)?.0 else { return nil }
        HmmHaptics.play(.selection)
        if selection.contains(id) { return holdMenu(for: selection) }
        let before = selection
        select(id)
        var menu = holdMenu(for: [id])
        if !before.isEmpty {
            let add = HmmHoldMenu.Item("Add to the selection", systemName: "plus.circle") { [weak self] in self?.setSelection(before + [id]) }
            menu.extras = [add] + menu.extras.prefix(HmmHoldMenu.maximumExtras - 1)
        }
        return menu
    }

    /// A key on the timeline (with the other picked keys, when it is one of them).
    func holdMenu(forKey key: KeyRef) -> HmmHoldMenu {
        if !selectedKeys.contains(key) { selectedKeys = [key] }
        let easing = HmmHoldMenu.Item("Easing", systemName: "point.topleft.down.to.point.bottomright.curvepath", children: EasingChoice.allCases.map { choice in
            HmmHoldMenu.Item(choice.title) { [weak self] in self?.setEasing(choice.easing) }
        })
        let several = selectedKeys.count > 1
        return HmmHoldMenu(copy: { [weak self] in self?.copyKeys() },
                           paste: holdAction(if: hasKeyClipboard) { [weak self] in self?.pasteKeys() },
                           extras: [easing,
                                    HmmHoldMenu.Item("Reverse", systemName: "arrow.uturn.backward", isEnabled: several) { [weak self] in self?.reverseKeys() },
                                    HmmHoldMenu.Item("Mirror (there and back)", systemName: "arrow.left.and.right", isEnabled: several) { [weak self] in
                                        self?.mirrorKeys()
                                    }],
                           delete: { [weak self] in self?.deleteSelectedKeys() })
    }

    /// A clip on a character's timeline row (with the other picked clips, when it is one of them).
    func holdMenu(forClip segment: ClipSegment) -> HmmHoldMenu {
        if !selectedClips.contains(segment.id) { selectedClips = [segment.id] }
        let inside = time > segment.start + 0.01 && time < segment.end - 0.01
        return HmmHoldMenu(extras: [
            HmmHoldMenu.Item("Split at the playhead", systemName: "scissors", isEnabled: inside) { [weak self] in self?.splitClip(segment.id) },
            HmmHoldMenu.Item(segment.loop ? "Play once" : "Loop", systemName: "repeat") { [weak self] in self?.setPickedClips(loop: !segment.loop) }
        ], delete: { [weak self] in self?.removePickedClips() })
    }

    /// One drawing of a flipbook.
    func holdMenu(forFlipbookDrawing index: Int, of track: String) -> HmmHoldMenu {
        func there(_ action: @escaping @MainActor (EditorModel) -> Void) -> @MainActor () -> Void {
            { [weak self] in
                guard let self else { return }
                showFlipbookDrawing(index, of: track)
                action(self)
            }
        }
        return HmmHoldMenu(duplicate: there { $0.duplicateFlipbookDrawing() }, extras: [
            HmmHoldMenu.Item("Hold longer", systemName: "plus", action: there { $0.changeFlipbookHold(by: 1) }),
            HmmHoldMenu.Item("Hold shorter", systemName: "minus", action: there { $0.changeFlipbookHold(by: -1) })
        ], delete: there { $0.deleteFlipbookDrawing() })
    }

    /// Cuts a clip in two at the playhead; the second half goes on from where the first stops.
    func splitClip(_ id: String) {
        let moment = time
        updateTimeline("Split clip") { timeline in
            for track in timeline.clipTracks.indices {
                guard let index = timeline.clipTracks[track].segments.firstIndex(where: { $0.id == id }) else { continue }
                let whole = timeline.clipTracks[track].segments[index]
                guard moment > whole.start + 0.01, moment < whole.end - 0.01 else { return }
                var first = whole
                first.duration = moment - whole.start
                var second = whole
                second.id = UUID().uuidString.lowercased()
                second.start = moment
                second.duration = whole.end - moment
                second.offset = whole.offset + (moment - whole.start) * whole.speed
                second.blend = 0
                timeline.clipTracks[track].segments[index] = first
                timeline.clipTracks[track].segments.insert(second, at: index + 1)
            }
        }
    }

    private func on(_ ids: [ObjectID], _ action: @escaping @MainActor (EditorModel) -> Void) -> @MainActor () -> Void {
        { [weak self] in
            guard let self else { return }
            if selection != ids { setSelection(ids) }
            action(self)
        }
    }

    /// Hide, Lock and Group (Show, Unlock, Ungroup when that's what they'd undo).
    private func objectExtras(_ ids: [ObjectID], _ objects: [SceneObject]) -> [HmmHoldMenu.Item] {
        let hidden = !objects.isEmpty && objects.allSatisfy { !$0.isVisible }
        let locked = !objects.isEmpty && objects.allSatisfy(\.isLocked)
        let grouping = if objects.count == 1, objects[0].kind == .group {
            HmmHoldMenu.Item("Ungroup", systemName: "square.on.square.dashed", action: on(ids) { $0.ungroupSelection() })
        } else {
            HmmHoldMenu.Item("Group", systemName: "square.on.square", isEnabled: objects.count > 1, action: on(ids) { $0.groupSelection() })
        }
        return [
            HmmHoldMenu.Item(hidden ? "Show" : "Hide", systemName: hidden ? "eye" : "eye.slash") { [weak self] in
                guard let self else { return }
                perform(operations.setFlag(ids, key: .visible, hidden))
            },
            HmmHoldMenu.Item(locked ? "Unlock" : "Lock", systemName: locked ? "lock.open" : "lock") { [weak self] in
                guard let self else { return }
                perform(operations.setFlag(ids, key: .locked, !locked))
            },
            grouping
        ]
    }
}

/// Rename, wherever it was asked for (a hold menu on the stage, in the outliner, on a timeline row).
struct ObjectRenameAlert: ViewModifier {
    @Bindable var editor: EditorModel
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: editor.renamingObject) { _, id in
                if let id { name = editor.scene.objects[id]?.name ?? "" }
            }
            .alert("Rename", isPresented: Binding(get: { editor.renamingObject != nil }, set: { if !$0 { editor.renamingObject = nil } })) {
                TextField("Name", text: $name)
                Button("Rename") {
                    if let id = editor.renamingObject { editor.rename(id, to: name) }
                    editor.renamingObject = nil
                }
                Button("Cancel", role: .cancel) { editor.renamingObject = nil }
            }
    }
}
