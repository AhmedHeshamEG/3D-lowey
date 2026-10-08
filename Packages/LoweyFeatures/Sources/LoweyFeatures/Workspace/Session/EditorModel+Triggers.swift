import Foundation
import HmmDesign
import LoweyCore

/// A character's triggers (`TriggerDeck`): making them, and firing them. While a take records a trigger is performed
/// (pressed and let go in time, kept as held keys); otherwise firing one is an edit at the playhead like any other.
extension EditorModel {
    func triggers(of character: ObjectID) -> [Trigger] {
        baseScene.objects[character].map(TriggerDeck.triggers) ?? []
    }

    private func store(_ deck: [Trigger], on character: ObjectID, label: String) {
        perform(.batch(label, [.setProperties([TriggerDeck.storing(deck, on: character)])]))
    }

    func addTrigger(_ expression: FaceExpression, to character: ObjectID) {
        var deck = triggers(of: character)
        deck.append(Trigger(id: UUID().uuidString.lowercased(), name: expression.title, kind: .expression, key: TriggerDeck.freeKey(in: deck),
                            holds: true, expression: expression))
        store(deck, on: character, label: "Add a trigger")
    }

    func addTrigger(_ pose: CharacterPose, to character: ObjectID) {
        var deck = triggers(of: character)
        deck.append(Trigger(id: UUID().uuidString.lowercased(), name: pose.name, kind: .pose, key: TriggerDeck.freeKey(in: deck), holds: true,
                            pose: pose.id))
        store(deck, on: character, label: "Add a trigger")
    }

    /// The things inside the character that could take turns: its own children that aren't joints or face parts.
    func swapChoices(of character: ObjectID) -> [SceneObject] {
        (baseScene.objects[character]?.children ?? []).compactMap { baseScene.objects[$0] }.filter { $0[.bone] == nil && $0[.faceRole] == nil }
    }

    /// One trigger per thing: each shows its own and hides the others.
    func addSwapTriggers(_ objects: [ObjectID], to character: ObjectID) {
        guard objects.count >= 2 else {
            app.show("A swap needs at least two things to take turns")
            return
        }
        var deck = triggers(of: character)
        var ids = IDFactory.random
        deck += TriggerDeck.swap(of: objects, in: baseScene, deck: deck, ids: &ids)
        store(deck, on: character, label: "Add a swap")
    }

    func removeTrigger(_ id: String, of character: ObjectID) {
        store(triggers(of: character).filter { $0.id != id }, on: character, label: "Delete trigger")
    }

    func updateTrigger(_ id: String, of character: ObjectID, label: String, _ change: (inout Trigger) -> Void) {
        var deck = triggers(of: character)
        guard let index = deck.firstIndex(where: { $0.id == id }) else { return }
        change(&deck[index])
        store(deck, on: character, label: label)
    }

    /// Gives a trigger a key, taking it from whichever trigger had it.
    func setTriggerKey(_ key: String?, for id: String, of character: ObjectID) {
        var deck = triggers(of: character)
        for index in deck.indices {
            if deck[index].id == id { deck[index].key = key } else if deck[index].key == key { deck[index].key = nil }
        }
        store(deck, on: character, label: "Trigger key")
    }

    // MARK: Firing

    /// A finger (or a key) comes down on a trigger.
    func pressTrigger(_ trigger: Trigger, on character: ObjectID) {
        guard performPhase == .recording else {
            if performPhase == .idle { fire(trigger, on: character) }
            return
        }
        if live.held.contains(trigger.id) {
            // A trigger that stays is switched off by a second press.
            if !trigger.holds { letGo(trigger) }
            return
        }
        // One of a kind at a time: a new expression replaces the one that's on.
        for other in triggers(of: character) where other.kind == trigger.kind && live.held.contains(other.id) {
            letGo(other)
        }
        let changes = TriggerDeck.changes(for: trigger, on: character, in: displayed.scene, rigs: libraryRigs())
        guard !changes.isEmpty else { return }
        let before = TriggerDeck.restoring(changes, in: displayed.scene)
        for (change, old) in zip(changes, before) {
            guard let value = change.value else { continue }
            if let rest = old.value { performLive(rest, change.key, on: change.object, stepped: true) }
            performLive(value, change.key, on: change.object, stepped: true)
        }
        live.restores[trigger.id] = before
        live.held.insert(trigger.id)
        HmmHaptics.play(.selection)
        refreshDisplay()
    }

    /// The finger lifts: a trigger that only holds goes back to what was there.
    func releaseTrigger(_ trigger: Trigger) {
        guard performPhase == .recording, trigger.holds, live.held.contains(trigger.id) else { return }
        letGo(trigger)
    }

    private func letGo(_ trigger: Trigger) {
        for change in live.restores[trigger.id] ?? [] {
            if let value = change.value {
                performLive(value, change.key, on: change.object, stepped: true)
            } else {
                propertyOverride[change.object]?[change.key] = nil
            }
        }
        live.restores[trigger.id] = nil
        live.held.remove(trigger.id)
        refreshDisplay()
    }

    /// Not recording: the trigger's state is set at the playhead (keys in Keyframe mode, as any edit).
    private func fire(_ trigger: Trigger, on character: ObjectID) {
        let changes = TriggerDeck.changes(for: trigger, on: character, in: displayed.scene, rigs: libraryRigs())
        guard !changes.isEmpty else {
            app.show("That trigger has nothing to show any more")
            return
        }
        perform(.batch("Trigger: \(trigger.name)", [.setProperties(changes)]))
        HmmHaptics.play(.commit)
    }

    /// A key of the keyboard: fires the selected character's trigger with that key (a second press lets it go).
    func fireTriggerKey(_ key: String) {
        guard let character = faceTarget, let trigger = triggers(of: character).first(where: { $0.key == key }) else { return }
        if performPhase == .recording, live.held.contains(trigger.id) {
            letGo(trigger)
        } else {
            pressTrigger(trigger, on: character)
        }
    }

    /// Whether the selected character has a trigger on this key.
    func hasTrigger(key: String) -> Bool {
        faceTarget.map { triggers(of: $0).contains { $0.key == key } } ?? false
    }

    /// The take ends: nothing is held any more.
    func clearTriggers() {
        live.held = []
        live.restores = [:]
    }
}
