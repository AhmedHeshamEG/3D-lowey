import HmmDesign
import LoweyCore
import SwiftUI

/// Look: which Look (Ink, Comic, Sketch, Clay, Low-poly or a My Look), the Mood, the palette, the finish. Few
/// decisions first; fine tuning one tap deeper.
struct LookPanel: View {
    @Bindable var editor: EditorModel
    @State private var savingLook = false
    @State private var lookName = ""
    @State private var showsFineTune = false

    private var look: Look { editor.look }

    var body: some View {
        HmmPanel("Look", width: 380, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                Toggle("Only this scene", isOn: Binding(get: { editor.lookIsSceneOnly }, set: { editor.setLookSceneOnly($0) }))
                    .font(.hmm(.body, weight: .semibold))
                looks
                if let mine = editor.document.project.customLooks.first(where: { $0.id == look.presetID }) {
                    MyLookEditor(editor: editor, preset: mine)
                }
                moods
                PaletteSection(editor: editor)
                FinishSection(editor: editor)
                DisclosureGroup("Fine tune the world", isExpanded: $showsFineTune) {
                    WorldSection(editor: editor).padding(.top, HmmSpacing.xs)
                }
                .font(.hmm(.body, weight: .semibold))
                saved
            }
        }
        .alert("Save the world to your library", isPresented: $savingLook) {
            TextField("Name", text: $lookName)
            Button("Save") {
                let name = lookName.isEmpty ? "My world" : lookName
                Task { await editor.library.saveLook(look, name: name) }
                editor.app.show("Saved “\(name)” to your library")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var looks: some View {
        PanelSection("Look") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(editor.allLooks) { preset in
                        Button {
                            editor.setLookPreset(preset.id)
                        } label: {
                            LookCard(preset: preset, selected: preset.id == look.presetID, mood: look.lightingPreset ?? .day)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { lookMenu(preset) }
                    }
                }
            }
            HStack {
                HmmPillButton("Duplicate as My Look", systemName: "plus.square.on.square") { editor.duplicateLook(editor.lookPreset) }
                    .accessibilityIdentifier("duplicate-look")
            }
            Hint("Touch and hold a Look for its options. Built-in Looks stay as they are; duplicate one to change it.")
        }
    }

    @ViewBuilder
    private func lookMenu(_ preset: LookPreset) -> some View {
        Button("Duplicate as My Look", systemImage: "plus.square.on.square") { editor.duplicateLook(preset) }
        if !preset.isBuiltIn {
            Button("Delete", systemImage: "trash", role: .destructive) { editor.deleteCustomLook(preset.id) }
        }
    }

    private var moods: some View {
        PanelSection("Mood") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(LightingPreset.allCases, id: \.self) { mood in
                        Button {
                            editor.setMood(mood)
                        } label: {
                            MoodCard(mood: mood, selected: look.lightingPreset == mood)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var saved: some View {
        PanelSection("Library") {
            HmmPillButton("Save this world to the library", systemName: "tray.and.arrow.down") {
                lookName = look.lightingPreset?.displayName ?? "My world"
                savingLook = true
            }
            let savedLooks = editor.library.manifest.looks
            if !savedLooks.isEmpty {
                ForEach(savedLooks) { saved in
                    Button(saved.name) { editor.place(.look(saved)) }.font(.hmm(.body))
                }
            }
        }
    }
}

/// The palette: linked colours (change one and everything using it follows), Pick, add and remove.
struct PaletteSection: View {
    @Bindable var editor: EditorModel
    @State private var editingSlot: Int?
    @State private var slotColor = Color.white

    private var palette: Palette { editor.look.palette }

    var body: some View {
        PanelSection("Palette") {
            HStack {
                HmmButton("eyedropper.halffull", label: "Pick a colour", isOn: editor.pickActive, size: 36) {
                    editor.pickSlot = editingSlot ?? 0
                    editor.pickActive.toggle()
                    if editor.pickActive { editor.app.show("Tap an object to take its colour into slot \(editor.pickSlot + 1)") }
                }
                HmmButton("plus", label: "Add a colour", size: 36) { editor.addPaletteSwatch() }
                Spacer()
            }
            PaletteRow(palette: palette, selected: editingSlot, remove: { slot in
                if editingSlot == slot { editingSlot = nil }
                editor.removePaletteSwatch(slot)
            }) { slot in
                editingSlot = slot
                slotColor = palette.color(at: slot).color
                editor.currentColor = .palette(slot)
            }
            if let slot = editingSlot, palette.swatches.indices.contains(slot) {
                ColorPicker(palette.swatches[slot].name, selection: $slotColor, supportsOpacity: false)
                    .onChange(of: slotColor) { _, value in
                        editor.updateLook(coalesce: "palette-\(slot)") { $0.palette.swatches[slot].color = RGBA(value) }
                    }
                Hint("Everything using this colour updates.")
            }
        }
    }
}
