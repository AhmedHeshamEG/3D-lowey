import Foundation
import HmmDesign
import LoweyCore

/// The Look: which of the five (or a "My Look") the scene uses, the Mood, the palette, the finish, per-object
/// overrides, and Pick (the eyedropper).
extension EditorModel {
    var look: Look { document.effectiveLook }
    var lookIsSceneOnly: Bool { document.scene.look != nil }
    /// The Look preset in effect for the scene.
    var lookPreset: LookPreset { document.lookPreset }
    var allLooks: [LookPreset] { LookLibrary.all(custom: document.project.customLooks) }

    /// Edits the look (this scene's own look when it has one, else the project's).
    func applyLook(_ look: Look, sceneOnly: Bool? = nil, coalesce: String? = nil) {
        let scoped = sceneOnly ?? lookIsSceneOnly
        perform(.setLook(look, scope: scoped ? .scene : .project), coalesceKey: coalesce)
    }

    func updateLook(coalesce: String? = nil, _ change: (inout Look) -> Void) {
        var copy = look
        change(&copy)
        applyLook(copy, coalesce: coalesce)
    }

    func setLookSceneOnly(_ sceneOnly: Bool) {
        perform(.setLook(sceneOnly ? document.project.look : nil, scope: .scene))
    }

    /// Picks the scene's Look (Ink, Comic, Sketch, Clay, Low-poly or a My Look).
    func setLookPreset(_ id: String) {
        guard id != look.presetID else { return }
        updateLook { $0 = $0.withPreset(id) }
        HmmHaptics.play(.selection)
    }

    func setMood(_ mood: LightingPreset) {
        updateLook { $0 = $0.applying(mood) }
        HmmHaptics.play(.selection)
    }

    // MARK: My Looks

    /// Duplicates a Look as "My <name>" and makes it the scene's Look.
    func duplicateLook(_ preset: LookPreset) {
        let mine = preset.duplicated(id: "my-\(UUID().uuidString.prefix(8).lowercased())",
                                     name: LookLibrary.duplicateName(for: preset, existing: document.project.customLooks))
        perform(.batch("Duplicate \(preset.name)", [.setCustomLooks(document.project.customLooks + [mine]),
                                                    .setLook(look.withPreset(mine.id), scope: lookIsSceneOnly ? .scene : .project)]))
        app.show("“\(mine.name)” is yours to tweak")
    }

    /// Edits a My Look (built-in Looks are read-only: duplicate them first).
    func updateCustomLook(_ id: String, coalesce: String? = nil, _ change: (inout LookPreset) -> Void) {
        var looks = document.project.customLooks
        guard let index = looks.firstIndex(where: { $0.id == id }) else { return }
        change(&looks[index])
        guard looks != document.project.customLooks else { return }
        perform(.setCustomLooks(looks), coalesceKey: coalesce)
    }

    func renameCustomLook(_ id: String, to name: String) {
        guard !name.isEmpty else { return }
        updateCustomLook(id) { $0.name = name }
    }

    /// Removes a My Look; anything using it falls back to the Look it was based on.
    func deleteCustomLook(_ id: String) {
        guard let removed = document.project.customLooks.first(where: { $0.id == id }) else { return }
        let fallback = removed.basedOn ?? LookLibrary.defaultID
        var commands: [EditCommand] = [.setCustomLooks(document.project.customLooks.filter { $0.id != id })]
        if look.presetID == id { commands.append(.setLook(look.withPreset(fallback), scope: lookIsSceneOnly ? .scene : .project)) }
        let overrides = baseScene.objects.values.filter { $0.lookOverride == id }
            .map { PropertyChange(object: $0.id, key: .lookPreset, value: .enumeration(fallback)) }
        if !overrides.isEmpty { commands.append(.setProperties(overrides)) }
        perform(.batch("Delete \(removed.name)", commands))
    }

    // MARK: Per object

    /// The selection's own Look (nil = the scene's).
    func setLookOverride(_ id: String?) {
        setProperty(.lookPreset, id.map { .enumeration($0) })
    }

    // MARK: Palette & Pick

    /// Takes a colour out of the palette; objects painted with it keep their colour (the slot stays, hidden).
    func removePaletteSwatch(_ slot: Int) {
        guard look.palette.swatches.indices.contains(slot) else { return }
        if currentColor == .palette(slot) { currentColor = .rgba(look.palette.color(at: slot)) }
        updateLook { $0.palette.remove(slot: slot) }
    }

    func addPaletteSwatch() {
        updateLook { $0.palette.swatches.append(.init(name: "Colour \($0.palette.swatches.count + 1)", color: .blockout)) }
    }

    /// Pick: take an object's colour into the chosen palette slot and bind the object to it.
    func pick(object id: ObjectID) {
        guard let object = scene.objects[id], let color = object.color?.resolved(in: look.palette) else {
            app.show("That object has no colour of its own")
            return
        }
        let slot = pickSlot
        var newLook = look
        while newLook.palette.swatches.count <= slot {
            newLook.palette.swatches.append(.init(name: "Colour \(newLook.palette.swatches.count + 1)", color: .blockout))
        }
        newLook.palette.swatches[slot].color = color
        perform(.batch("Pick colour", [
            .setLook(newLook, scope: lookIsSceneOnly ? .scene : .project),
            .setProperties([PropertyChange(object: id, key: .color, value: .color(.palette(slot)))])
        ]))
        pickActive = false
        HmmHaptics.play(.commit)
    }

    /// The finish (post) of the look.
    func updatePost(coalesce: String? = nil, _ change: (inout PostSettings) -> Void) {
        updateLook(coalesce: coalesce) { look in change(&look.post) }
    }
}
