import HmmDesign
import LoweyCore
import SwiftUI

/// Cast ▸ Rig: give anything a skeleton. Draw a bone through a limb, tail or rope with the Pencil (its weights are
/// worked out by bone heat), rig a human-like model as a person, paint the weights by hand if wanted.
struct RigSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if let object = editor.singleSelection, editor.castType(of: object.id) == nil || object.rig != nil {
            PanelSection("Rig") {
                if editor.rigging.busy.contains(object.id) {
                    HStack(spacing: HmmSpacing.xs) {
                        ProgressView()
                        Text("Working out how it bends…").font(.hmm(.body))
                    }
                } else if let blocker = editor.rigBlocker(object) {
                    Hint(blocker)
                } else {
                    actions(object)
                }
            }
        }
    }

    @ViewBuilder private func actions(_ object: SceneObject) -> some View {
        HStack(spacing: HmmSpacing.xs) {
            HmmPillButton("Draw a bone", systemName: RigSettings.Mode.bone.systemImage, prominent: object.rig == nil) {
                editor.rigging.mode = .bone
                editor.startRigging(object.id)
            }
            .accessibilityIdentifier("rig-draw-bone")
            if case .drawing = object.kind {} else {
                HmmPillButton("Rig as a person", systemName: "figure.stand") { editor.startPersonRig(object.id) }
                    .accessibilityIdentifier("rig-person")
            }
        }
        if let rig = object.rig {
            Hint("\(rig.skeleton.joints.count) joints. Select it and drag its joints on the stage to pose it; keys land at the playhead in Keyframe.")
            if !editor.rigFits(object) {
                HmmPillButton("Fit the weights to the new shape", systemName: "arrow.triangle.2.circlepath", prominent: true) {
                    editor.refitRig(object.id)
                }
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Paint weights", systemName: RigSettings.Mode.weights.systemImage) {
                    editor.startRigging(object.id)
                    editor.rigging.mode = .weights
                    if editor.rigging.joint.map({ $0 >= rig.skeleton.joints.count }) ?? true { editor.rigging.joint = rig.skeleton.joints.count - 1 }
                }
                .accessibilityIdentifier("rig-weights")
                HmmPillButton("Reset the pose", systemName: "arrow.uturn.backward") { editor.resetPose(object.id) }
            }
            HmmPillButton("Remove the rig", systemName: "trash", role: .destructive) { editor.removeRig(object.id) }
                .accessibilityIdentifier("rig-remove")
        } else {
            Hint("Draw through a limb, tail or rope with the Pencil: it bends there. A human-like model can be rigged as a person.")
        }
    }
}

/// Under the stage while Cast ▸ Rig is on: what the Pencil does, the bone whose weight is painted, and the person rig's
/// Rig button.
struct RigOptionsBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            if let person = editor.rigging.person {
                Text(person.next.map { "Tap \($0.title)" } ?? "Drag any dot, then Rig").font(.hmm(.body, weight: .semibold))
                HmmPillButton("Rig", systemName: "checkmark", prominent: person.next == nil) { editor.finishPersonRig() }
                    .disabled(person.next != nil)
                    .accessibilityIdentifier("rig-person-done")
                HmmButton("xmark", label: "Cancel", size: 36) {
                    editor.cancelPersonRig()
                    editor.tool = .select
                }
            } else {
                ForEach(RigSettings.Mode.allCases) { mode in
                    ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.rigging.mode == mode) { editor.rigging.mode = mode }
                        .disabled(mode == .weights && editor.rigTarget?.rig == nil)
                }
                if editor.rigging.mode == .weights, let rig = editor.rigTarget?.rig {
                    jointMenu(rig)
                    ChoiceChip(title: "Erase", systemName: "eraser", isOn: editor.rigging.erase) { editor.rigging.erase.toggle() }
                }
                HmmButton("xmark", label: "Done rigging", size: 36) { editor.tool = .select }
            }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }

    private func jointMenu(_ rig: ObjectRig) -> some View {
        Menu {
            ForEach(rig.skeleton.joints.indices, id: \.self) { index in
                Button(rig.skeleton.joints[index].name) { editor.rigging.joint = index }
            }
        } label: {
            Label(editor.rigging.joint.flatMap { rig.skeleton.joints[safe: $0]?.name } ?? "Choose a bone", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.hmm(.body, weight: .semibold))
                .foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("rig-joint")
    }
}

/// The person rig's dots over the stage: drag any of them; the next one to tap glows.
struct PersonDotMarks: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let dots = revision >= 0 ? editor.personDotsOnScreen() : []
        let next = editor.rigging.person?.next
        let placed = editor.rigging.person?.placed ?? []
        ZStack {
            ForEach(dots, id: \.dot) { item in
                Circle()
                    .fill(placed.contains(item.dot) || next == nil ? theme.accent : theme.surface2.opacity(0.7))
                    .overlay(Circle().stroke(item.dot == next ? theme.accent : Color.white.opacity(0.8), lineWidth: item.dot == next ? 3 : 1.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle().inset(by: -10))
                    .position(item.point)
                    .gesture(DragGesture(coordinateSpace: .named("person-dots")).onChanged { editor.movePersonDot(item.dot, to: $0.location) })
                    .accessibilityLabel(item.dot.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named("person-dots"))
    }
}
