import HmmDesign
import LoweyCore
import SwiftUI

/// The character's pose library: save the pose at the playhead, tap one to pose (keyed in Keyframe mode), mirror.
/// In Keyframe and Perform modes the hands and feet on the stage are handles: drag them, the limbs follow.
struct PoseSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID
    @State private var renaming: CharacterPose?
    @State private var name = ""

    var body: some View {
        PanelSection("Poses") {
            let poses = editor.poses(of: character)
            if poses.isEmpty {
                Hint("Pose the character (drag its hands and feet in Keyframe mode, or use expressions), then save the pose to use it again.")
            } else {
                TileGrid(minimum: 96) {
                    ForEach(poses) { pose in
                        TileButton(title: pose.name, systemName: "figure.wave", identifier: "pose-\(pose.name)") { editor.applyPose(pose, to: character) }
                            .hmmHoldMenu(menu(for: pose))
                    }
                }
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Save this pose", systemName: "plus", prominent: poses.isEmpty) { editor.savePose(of: character) }
                    .accessibilityIdentifier("save-pose")
                HmmPillButton("Mirror", systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") { editor.mirrorPose(of: character) }
            }
            if editor.timelineMode == .compose {
                Hint("Switch the timeline to Keyframe to drag hands and feet directly.")
            }
        }
        .alert("Pose name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                if let pose = renaming { editor.renamePose(pose.id, of: character, to: name) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func menu(for pose: CharacterPose) -> HmmHoldMenu {
        HmmHoldMenu(rename: {
            name = pose.name
            renaming = pose
        }, extras: [
            HmmHoldMenu.Item("Apply mirrored", systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                editor.applyPose(PoseLibrary.mirrored(pose), to: character)
            },
            HmmHoldMenu.Item("Save a mirrored copy", systemName: "plus.square.on.square") { editor.saveMirrored(pose, of: character) }
        ], delete: { editor.deletePose(pose.id, of: character) })
    }
}
