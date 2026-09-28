import LoweyCore
import LoweyRender
import SwiftUI

/// Per-project look (or per-scene): mood presets first, then palette, then fine tuning.
struct LookPanel: View {
    @Bindable var editor: EditorModel
    @State private var editingSlot: Int?
    @State private var slotColor = Color.white
    @State private var showFineTune = false
    @State private var savingLook = false
    @State private var lookName = ""

    private var look: Look { editor.look }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Look").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    Menu {
                        Button("Save look to library", systemImage: "tray.and.arrow.down") {
                            lookName = look.lightingPreset?.displayName ?? "My look"
                            savingLook = true
                        }
                        let saved = editor.library.manifest.looks
                        if !saved.isEmpty {
                            Section("Saved looks") {
                                ForEach(saved) { preset in
                                    Button(preset.name) { editor.place(.look(preset)) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 22))
                    }
                }
                Toggle("Only this scene", isOn: Binding(get: { editor.lookIsSceneOnly }, set: { editor.setLookSceneOnly($0) }))
                    .font(.system(size: 14, weight: .medium))

                SectionHeader(title: "Mood")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(LightingPreset.allCases, id: \.self) { preset in
                            Button {
                                Haptics.select()
                                editor.updateLook { $0 = $0.applying(preset) }
                            } label: {
                                PresetCard(preset: preset, selected: look.lightingPreset == preset)
                                    .scaleEffect(0.85)
                                    .frame(width: 104)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preset-\(preset.rawValue)")
                        }
                    }
                }

                SectionHeader(title: "Shading")
                Picker("Shading", selection: Binding(get: { look.shading }, set: { value in editor.updateLook { $0.shading = value } })) {
                    Text("Smooth (soft low-poly)").tag(ShadingStyle.smooth)
                    Text("Flat (faceted)").tag(ShadingStyle.flat)
                }
                .pickerStyle(.segmented)

                paletteSection

                SectionHeader(title: "Atmosphere")
                Toggle("Fog", isOn: Binding(get: { look.fog.enabled }, set: { value in editor.updateLook { $0.fog.enabled = value } }))
                if look.fog.enabled {
                    labeledSlider("Fog distance", value: look.fog.distance, range: 5 ... 200, key: "fog") { value in
                        editor.updateLook(coalesce: "look-fog") { $0.fog.distance = value }
                    }
                }
                labeledSlider("Stars", value: look.sky.stars, range: 0 ... 1, key: "stars") { value in
                    editor.updateLook(coalesce: "look-stars") { $0.sky.stars = value }
                }
                Toggle("Ground", isOn: Binding(get: { look.ground.visible }, set: { value in editor.updateLook { $0.ground.visible = value } }))

                PostSection(editor: editor)

                DisclosureGroup("Fine tune", isExpanded: $showFineTune) {
                    fineTune.padding(.top, 10)
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .padding(18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .panelStyle()
        .alert("Save look", isPresented: $savingLook) {
            TextField("Name", text: $lookName)
            Button("Save") {
                editor.library.saveLook(look, name: lookName.isEmpty ? "My look" : lookName)
                editor.app.show("Look saved to your library")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Palette")
                Button {
                    editor.eyedropperSlot = editingSlot ?? 0
                    editor.eyedropperActive.toggle()
                    if editor.eyedropperActive { editor.app.show("Tap an object to take its colour into slot \((editingSlot ?? 0) + 1)") }
                } label: {
                    Image(systemName: "eyedropper.halffull")
                        .foregroundStyle(editor.eyedropperActive ? Color.black : Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(editor.eyedropperActive ? Theme.accent : Theme.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Eyedropper")
                Button {
                    editor.updateLook { $0.palette.swatches.append(.init(name: "Colour \($0.palette.swatches.count + 1)", color: .blockout)) }
                } label: {
                    Image(systemName: "plus").frame(width: 34, height: 34).background(Circle().fill(Theme.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add colour")
            }
            PaletteRow(palette: look.palette, selected: editingSlot, remove: { slot in
                if editingSlot == slot { editingSlot = nil }
                editor.removePaletteSwatch(slot)
            }) { slot in
                editingSlot = slot
                slotColor = look.palette.color(at: slot).color
            }
            if let slot = editingSlot, look.palette.swatches.indices.contains(slot) {
                HStack {
                    Text(look.palette.swatches[slot].name).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    ColorPicker("", selection: $slotColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: slotColor) { _, value in
                            editor.updateLook(coalesce: "palette-\(slot)") { $0.palette.swatches[slot].color = RGBA(value) }
                        }
                }
                HStack {
                    Text("Everything using this colour updates.").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        editingSlot = nil
                        editor.removePaletteSwatch(slot)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("remove-swatch")
                }
            }
        }
    }

    private var fineTune: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledSlider("Sun height", value: look.lighting.sunElevation, range: 2 ... 90, key: "elev") { value in
                editor.updateLook(coalesce: "look-sun-el") { $0.lighting.sunElevation = value }
            }
            labeledSlider("Sun direction", value: look.lighting.sunAzimuth, range: 0 ... 360, key: "az") { value in
                editor.updateLook(coalesce: "look-sun-az") { $0.lighting.sunAzimuth = value }
            }
            labeledSlider("Sun strength", value: look.lighting.sunIntensity, range: 0 ... 2, key: "sun") { value in
                editor.updateLook(coalesce: "look-sun") { $0.lighting.sunIntensity = value }
            }
            labeledSlider("Ambient", value: look.lighting.ambientIntensity, range: 0 ... 2, key: "amb") { value in
                editor.updateLook(coalesce: "look-amb") { $0.lighting.ambientIntensity = value }
            }
            labeledSlider("Exposure", value: look.lighting.exposure, range: -2 ... 2, key: "exp") { value in
                editor.updateLook(coalesce: "look-exp") { $0.lighting.exposure = value }
            }
            Toggle("Sun shadows", isOn: Binding(get: { look.lighting.sunShadows }, set: { value in editor.updateLook { $0.lighting.sunShadows = value } }))
            colorRow("Sun colour", look.lighting.sunColor) { value in editor.updateLook(coalesce: "sun-color") { $0.lighting.sunColor = value } }
            colorRow("Sky top", look.sky.top) { value in editor.updateLook(coalesce: "sky-top") { $0.sky.top = value } }
            colorRow("Horizon", look.sky.horizon) { value in editor.updateLook(coalesce: "sky-horizon") { $0.sky.horizon = value } }
            colorRow("Below", look.sky.bottom) { value in editor.updateLook(coalesce: "sky-bottom") { $0.sky.bottom = value } }
            colorRow("Fog colour", look.fog.color) { value in editor.updateLook(coalesce: "fog-color") { $0.fog.color = value } }
            colorRow("Ground colour", look.ground.color) { value in editor.updateLook(coalesce: "ground-color") { $0.ground.color = value } }
            labeledSlider("Ground size", value: look.ground.size, range: 5 ... 200, key: "gsize") { value in
                editor.updateLook(coalesce: "ground-size") { $0.ground.size = value }
            }
        }
    }

    private func labeledSlider(_ title: String, value: Double, range: ClosedRange<Double>, key _: String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(NumberFormat.short(value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondaryText)
            }
            Slider(value: Binding(get: { value }, set: set), in: range,
                   onEditingChanged: { editing in if !editing { editor.endGesture() } })
        }
    }

    private func colorRow(_ title: String, _ color: RGBA, set: @escaping (RGBA) -> Void) -> some View {
        ColorPicker(title, selection: Binding(get: { color.color }, set: { set(RGBA($0)) }), supportsOpacity: false)
            .font(.system(size: 14))
    }
}
