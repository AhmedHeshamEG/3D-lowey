import HmmDesign
import LoweyCore
import SwiftUI

/// Cast ▸ Rig: give anything a skeleton, in three steps in order. **Bones**: draw a bone through a limb, tail or rope
/// (or rig a human-like model as a person). **Skin**: the weights are worked out by themselves; paint them only if you
/// want to. **Pose**: drag the joints. Each step shows only its own tools, and the next one lights up when this one is
/// done.
struct RigSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if let object = editor.singleSelection, editor.castType(of: object.id) == nil || object.rig != nil {
            PanelSection("Rig") {
                if let blocker = editor.rigBlocker(object) {
                    Hint(blocker)
                } else {
                    RigStepRow(editor: editor, object: object)
                    if editor.rigging.busy.contains(object.id) {
                        HStack(spacing: HmmSpacing.xs) {
                            ProgressView()
                            Text("Working out how it bends…").font(.hmm(.body))
                        }
                    } else {
                        switch editor.rigStep(for: object) {
                        case .bones: bones(object)
                        case .skin: skin(object)
                        case .pose: pose(object)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func bones(_ object: SceneObject) -> some View {
        HStack(spacing: HmmSpacing.xs) {
            HmmPillButton("Draw a bone", systemName: RigSettings.Mode.bone.systemImage, prominent: object.rig == nil) {
                editor.startRigging(object.id)
            }
            .accessibilityIdentifier("rig-draw-bone")
            if case .drawing = object.kind {} else {
                HmmPillButton("Rig as a person", systemName: "figure.stand") { editor.startPersonRig(object.id) }
                    .accessibilityIdentifier("rig-person")
            }
        }
        if let rig = object.rig {
            Hint("\(rig.skeleton.joints.count) joints. Draw another bone to add one; draw along a bone again to replace it.")
            HmmPillButton("Remove the rig", systemName: "trash", role: .destructive) { editor.removeRig(object.id) }
                .accessibilityIdentifier("rig-remove")
        } else {
            Hint("Draw through a limb, tail or rope: it bends where the stroke bends. A human-like model can be rigged as a person.")
        }
    }

    @ViewBuilder private func skin(_ object: SceneObject) -> some View {
        if editor.rigFits(object) {
            Hint("The skin follows the bones by itself. Paint a bone's weight only where a bend looks wrong.")
        } else {
            Hint("The shape changed since it was rigged.")
            HmmPillButton("Fit the weights to the new shape", systemName: "arrow.triangle.2.circlepath", prominent: true) {
                editor.refitRig(object.id)
            }
            .accessibilityIdentifier("rig-refit")
        }
        HmmPillButton("Paint weights", systemName: RigSettings.Mode.weights.systemImage) { editor.startPaintingWeights(object.id) }
            .accessibilityIdentifier("rig-weights")
    }

    @ViewBuilder private func pose(_ object: SceneObject) -> some View {
        Hint("Drag its joints on the stage. In Keyframe, keys land at the playhead. Saved poses are below.")
        HmmPillButton("Reset the pose", systemName: "arrow.uturn.backward") { editor.resetPose(object.id) }
            .accessibilityIdentifier("rig-reset-pose")
        DangleControl(editor: editor, character: object.id)
    }
}

/// Bones → Skin → Pose. The step you're on is marked; a step that can't be entered yet is dimmed.
struct RigStepRow: View {
    let editor: EditorModel
    let object: SceneObject

    var body: some View {
        let current = editor.rigStep(for: object)
        HStack(spacing: HmmSpacing.xs) {
            ForEach(RigSettings.Step.allCases) { step in
                ChoiceChip(title: step.title, systemName: step.systemImage, isOn: step == current) { editor.setRigStep(step, on: object.id) }
                    .disabled(!editor.rigStepIsOpen(step, for: object))
                    .accessibilityIdentifier("rig-step-\(step.rawValue)")
            }
        }
    }
}

/// Under the stage while Cast ▸ Rig is on: the three steps, the bone whose weight is painted (Skin), and the person
/// rig's Rig button.
struct RigOptionsBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            if let person = editor.rigging.person {
                if let next = person.next {
                    Text("Tap \(String(localized: String.LocalizationValue(next.title)))").font(.hmm(.body, weight: .semibold))
                } else {
                    Text("Drag any dot, then Rig").font(.hmm(.body, weight: .semibold))
                }
                HmmPillButton("Rig", systemName: "checkmark", prominent: person.next == nil) { editor.finishPersonRig() }
                    .disabled(person.next != nil)
                    .accessibilityIdentifier("rig-person-done")
                HmmButton("xmark", label: "Cancel", size: 36) {
                    editor.cancelPersonRig()
                    editor.tool = .select
                }
            } else {
                if let object = editor.rigTarget { RigStepRow(editor: editor, object: object) }
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
            Group {
                if let name = editor.rigging.joint.flatMap({ rig.skeleton.joints[safe: $0]?.name }) {
                    Label(name, systemImage: "point.3.connected.trianglepath.dotted")
                } else {
                    Label("Choose a bone", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
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
