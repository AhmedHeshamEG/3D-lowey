import HmmDesign
import LoweyCore
import SwiftUI

/// Cast: every character in the scene (Blob, Puppet or Rigged), adding one, and what the selected character can do —
/// clips, expressions, lip sync, your face.
struct CastPanel: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmPanel("Cast", width: 360, sizing: HmmPanelSizing(id: "cast"), close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                PanelSection("Add") {
                    TileGrid {
                        TileButton(title: "Blob", systemName: "face.smiling", identifier: "add-blob") { openSheet(.blobBuilder) }
                        TileButton(title: "Me", systemName: "person.crop.circle", identifier: "add-me") { editor.buildBlob(.hesham) }
                        TileButton(title: "Puppet", systemName: "figure.stand", identifier: "add-character") {
                            editor.characterBuilderTarget = nil
                            openSheet(.characterBuilder)
                        }
                    }
                }
                castList
                if let character = currentCharacter { CharacterSections(editor: editor, character: character) }
                PartSection(editor: editor)
                RigSection(editor: editor)
            }
        }
    }

    private var currentCharacter: ObjectID? {
        editor.selectedPuppet ?? editor.selectedCharacter?.object.id
            ?? editor.selection.first.flatMap { editor.isBlob($0) || editor.baseScene.objects[$0]?.rig != nil ? $0 : nil }
    }

    private var castList: some View {
        PanelSection("In this scene") {
            if editor.cast.isEmpty {
                Hint("No characters yet. A Blob is the house character: it talks, emotes and lip-syncs.")
            }
            ForEach(editor.cast, id: \.id) { member in
                Button {
                    editor.select(member.id)
                } label: {
                    HStack(spacing: HmmSpacing.s) {
                        Image(systemName: member.type.systemImage).foregroundStyle(theme.accent).frame(width: 24)
                        Text(member.name).font(.hmm(.body, weight: editor.selection.contains(member.id) ? .semibold : .regular)).lineLimit(1)
                        Spacer()
                        Badge(text: member.type.title.uppercased())
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cast-\(member.name)")
            }
        }
    }

    private func openSheet(_ sheet: EditorSheet) {
        editor.openPanel = nil
        editor.sheet = sheet
    }
}

/// What the selected character can do.
struct CharacterSections: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            if editor.isBlob(character) { ExpressionTriggers(editor: editor, character: character) }
            if PoseLibrary.character(of: character, in: editor.baseScene, rigs: editor.libraryRigs()) == character {
                PoseSection(editor: editor, character: character)
            }
            ClipsSection(editor: editor, character: character)
            FaceSection(editor: editor, character: character)
            TriggersSection(editor: editor, character: character)
            LifeSection(editor: editor, character: character)
            if editor.castType(of: character) == .puppet {
                HmmPillButton("Edit this puppet", systemName: "person.crop.circle") {
                    editor.characterBuilderTarget = character
                    editor.openPanel = nil
                    editor.sheet = .characterBuilder
                }
            }
        }
    }
}

/// One tap poses the whole face at the playhead; the springs overshoot into it and settle.
struct ExpressionTriggers: View {
    let editor: EditorModel
    let character: ObjectID

    var body: some View {
        PanelSection("Expressions at the playhead") {
            TileGrid(minimum: 80) {
                ForEach(FaceExpression.allCases) { expression in
                    TileButton(title: expression.title, systemName: expression.symbol, identifier: "expression-\(expression.rawValue)") {
                        editor.keyExpression(expression, on: character)
                    }
                }
            }
            LabeledSlider(title: "Cartoon", value: editor.baseScene.objects[character]?[.cartoon]?.floatValue ?? 0.8, range: 0 ... 1,
                          format: NumberFormat.percent, set: { editor.setCartoon($0, on: character) }, done: editor.endGesture)
        }
    }
}

/// Lip sync and face performance.
struct FaceSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        PanelSection("Voice & face") {
            HmmPillButton(editor.wordSelection == nil ? "Lip sync to the voiceover" : "Lip sync these words", systemName: "mouth",
                          prominent: !editor.words.isEmpty) { editor.lipSync(character) }
                .accessibilityIdentifier("lip-sync")
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton(editor.live.voiceOn ? "Stop the microphone" : "Mouth from the microphone",
                              systemName: editor.live.voiceOn ? "mic.slash.fill" : "mic.fill") { editor.toggleVoice() }
                    .accessibilityIdentifier("voice-live")
                if editor.live.voiceOn { VoiceLevel(meter: editor.live.meter) }
            }
            if editor.faceActive {
                Text(editor.faceStatus ?? "Face on").font(.hmm(.body, weight: .semibold))
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Set rest pose", systemName: "scope") { editor.setRestPose() }
                    HmmPillButton("Stop", systemName: "stop.fill") { editor.stopFaceCapture() }
                }
                Toggle("Mirror", isOn: Binding(get: { editor.facePerformer.mirror }, set: { editor.facePerformer.mirror = $0 }))
                Hint("Your face and hands drive the character live. Record in Perform to capture a take; every take is kept.")
            } else {
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Front camera", systemName: "camera.fill") { editor.startFaceCapture(useIPhone: false) }
                        .accessibilityIdentifier("face-camera")
                    HmmPillButton("My iPhone", systemName: "iphone") { editor.startFaceCapture(useIPhone: true) }
                }
            }
        }
    }
}
