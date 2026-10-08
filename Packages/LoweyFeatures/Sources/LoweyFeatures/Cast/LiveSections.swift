import HmmDesign
import LoweyCore
import SwiftUI

/// How loud the microphone hears you, while it drives the mouth.
struct VoiceLevel: View {
    let meter: VoiceMeter
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Capsule()
            .fill(theme.surface2)
            .frame(width: 64, height: 6)
            .overlay(alignment: .leading) { Capsule().fill(theme.accent).frame(width: max(64 * meter.level, 3), height: 6) }
            .accessibilityLabel("Microphone level")
            .accessibilityValue(NumberFormat.percent(meter.level))
    }
}

/// A character's triggers: one tap for an expression, a saved pose, or a swap of what it holds. Tapped here they act
/// at the playhead; while a take records they're performed (the bar under the stage holds them under the fingers).
struct TriggersSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID
    @State private var renaming: Trigger?
    @State private var name = ""

    var body: some View {
        PanelSection("Triggers") {
            let deck = editor.triggers(of: character)
            if deck.isEmpty {
                Hint("One tap puts it in an expression or a pose, or swaps what it holds. While a take records, triggers are performed with everything else.")
            } else {
                TileGrid(minimum: 96) {
                    ForEach(deck) { trigger in
                        TileButton(title: trigger.name, systemName: symbol(trigger), identifier: "trigger-\(trigger.name)",
                                   isOn: editor.live.held.contains(trigger.id)) { tap(trigger) }
                            .overlay(alignment: .topTrailing) { if let key = trigger.key { Badge(text: key).padding(4) } }
                            .hmmHoldMenu(menu(for: trigger))
                    }
                }
            }
            addMenu
        }
        .alert("Trigger name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                if let trigger = renaming, !name.isEmpty { editor.updateTrigger(trigger.id, of: character, label: "Rename trigger") { $0.name = name } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func tap(_ trigger: Trigger) {
        if let key = trigger.key {
            editor.fireTriggerKey(key)
        } else {
            editor.pressTrigger(trigger, on: character)
        }
    }

    private func symbol(_ trigger: Trigger) -> String {
        switch trigger.kind {
        case .expression: trigger.expression?.symbol ?? "face.smiling"
        case .pose: "figure.wave"
        case .swap: "arrow.triangle.swap"
        }
    }

    private var addMenu: some View {
        Menu {
            Section("An expression") {
                ForEach(FaceExpression.allCases) { expression in
                    Button(LocalizedStringKey(expression.title), systemImage: expression.symbol) { editor.addTrigger(expression, to: character) }
                }
            }
            let poses = editor.poses(of: character)
            if !poses.isEmpty {
                Section("A saved pose") {
                    ForEach(poses) { pose in
                        Button(pose.name, systemImage: "figure.wave") { editor.addTrigger(pose, to: character) }
                    }
                }
            }
            let things = editor.swapChoices(of: character)
            if things.count >= 2 {
                Section("A swap") {
                    Button("The \(things.count) things inside it take turns", systemImage: "arrow.triangle.swap") {
                        editor.addSwapTriggers(things.map(\.id), to: character)
                    }
                }
            }
        } label: {
            Label("Add a trigger", systemImage: "plus").font(.hmm(.body, weight: .semibold))
        }
        .accessibilityIdentifier("add-trigger")
    }

    private func menu(for trigger: Trigger) -> HmmHoldMenu {
        let keys = [HmmHoldMenu.Item("No key", systemName: "xmark") { editor.setTriggerKey(nil, for: trigger.id, of: character) }]
            + TriggerDeck.keys.map { key in
                HmmHoldMenu.Item(key, id: "key-\(key)", systemName: trigger.key == key ? "checkmark" : "", isVerbatim: true) {
                    editor.setTriggerKey(key, for: trigger.id, of: character)
                }
            }
        return HmmHoldMenu(rename: {
            name = trigger.name
            renaming = trigger
        }, extras: [
            HmmHoldMenu.Item("Keyboard key", systemName: "keyboard", children: keys) {},
            HmmHoldMenu.Item(trigger.holds ? "Stay on when let go" : "Only while held", systemName: trigger.holds ? "pin" : "hand.tap") {
                editor.updateTrigger(trigger.id, of: character, label: "Trigger") { $0.holds.toggle() }
            }
        ], delete: { editor.removeTrigger(trigger.id, of: character) })
    }
}

/// What a character does by itself: breathe, blink. And, for a skeleton that isn't a person's, which bone is its head.
struct LifeSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        PanelSection("Life") {
            LabeledSlider(title: "Breathes", value: editor.breathing(of: character), range: 0 ... 1, format: NumberFormat.percent,
                          set: { editor.setBreathing($0, on: character) }, done: editor.endGesture)
                .accessibilityIdentifier("life-breathe")
            if hasEyes {
                Toggle("Blinks on its own", isOn: Binding(get: { editor.blinksOnItsOwn(character) }, set: { editor.setBlinksOnItsOwn($0, for: character) }))
                    .accessibilityIdentifier("life-blink")
            }
            let joints = editor.headChoices(of: character)
            if !joints.isEmpty {
                Menu {
                    Button("None") { editor.setHead(nil, on: character) }
                    ForEach(joints, id: \.self) { joint in
                        Button(joint) { editor.setHead(joint, on: character) }
                    }
                } label: {
                    Label(head.map { LocalizedStringKey("Head: \($0)") } ?? "Choose the bone that is its head", systemImage: "face.dashed")
                        .font(.hmm(.body, weight: .semibold))
                }
                .accessibilityIdentifier("life-head")
                Hint("The head bone turns with your face. A person's rig knows its own.")
            }
        }
    }

    private var head: String? { editor.baseScene.objects[character]?[.liveHead]?.stringValue }

    private var hasEyes: Bool {
        editor.isBlob(character) || editor.baseScene.subtree(of: character).contains {
            editor.baseScene.objects[$0]?[.faceRole]?.stringValue?.hasPrefix("eye.") == true
        }
    }
}

/// A loose object can become part of a drawn rig (an eye on a drawn head, a hat, something in a hand): it rides the
/// bone nearest to it, and as a face part it answers to the face.
struct PartSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if let object = editor.singleSelection {
            if let bone = object[.attachBone]?.stringValue {
                PanelSection("Part") { part(object, bone: bone) }
            } else {
                let hosts = editor.partHosts(for: object)
                if !hosts.isEmpty {
                    PanelSection("Make it part of") {
                        TileGrid(minimum: 96) {
                            ForEach(hosts, id: \.id) { host in
                                TileButton(title: host.name, systemName: "link", identifier: "part-of-\(host.name)") {
                                    editor.attachPart(object.id, to: host.id)
                                }
                            }
                        }
                        Hint("It will move with the nearest bone. An eye, a brow or a mouth can then follow your face.")
                    }
                }
            }
        }
    }

    @ViewBuilder private func part(_ object: SceneObject, bone: String) -> some View {
        let role = object[.faceRole]?.stringValue.flatMap(PartRole.init)
        Menu {
            Button("Nothing: it just rides the bone") { editor.setPartRole(nil, of: object.id) }
            Section("A part of the face") {
                ForEach(PartRole.features) { item in
                    Button(LocalizedStringKey(item.title)) { editor.setPartRole(item, of: object.id) }
                }
            }
            Section("One mouth of a set (they take turns)") {
                ForEach(PartRole.shapes) { item in
                    Button(LocalizedStringKey(item.title)) { editor.setPartRole(item, of: object.id) }
                }
            }
        } label: {
            Label(LocalizedStringKey(role?.title ?? "It rides its bone"), systemImage: "face.smiling").font(.hmm(.body, weight: .semibold))
        }
        .accessibilityIdentifier("part-role")
        if let parent = object.parent, let rig = editor.baseScene.objects[parent]?.rig {
            Menu {
                ForEach(rig.skeleton.names, id: \.self) { joint in
                    Button(joint) { editor.setPartBone(joint, of: object.id) }
                }
            } label: {
                Label("Bone: \(bone)", systemImage: "point.3.connected.trianglepath.dotted").font(.hmm(.body, weight: .semibold))
            }
            .accessibilityIdentifier("part-bone")
        }
        HmmPillButton("Take it off", systemName: "link.badge.plus", role: .destructive) { editor.detachPart(object.id) }
            .accessibilityIdentifier("part-detach")
    }
}

/// Rig ▸ Pose: the joint last touched on the stage can hang loose (hair, ears, a tail), with everything below it.
struct DangleControl: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        if let joint = editor.live.joint, joint.character == character {
            LabeledSlider(title: "Dangle", value: editor.dangle(of: joint.name, on: character), range: 0 ... 1, format: NumberFormat.percent,
                          set: { editor.setDangle($0, joint: joint.name, on: character) }, done: editor.endGesture)
                .accessibilityIdentifier("rig-dangle")
            Hint("The touched bone and everything below it hang loose: they trail when it moves and swing when it stops.")
        } else {
            Hint("Touch a joint on the stage to let it hang loose here: hair, ears, a tail.")
        }
    }
}

/// Under the stage while the timeline is in Perform: the selected character's triggers under the fingers. Press and
/// hold one that only holds; tap one that stays.
struct TriggerDeckBar: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if editor.timelineMode == .perform, let character = editor.faceTarget {
            let deck = editor.triggers(of: character)
            if !deck.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(deck) { trigger in
                            TriggerPad(editor: editor, trigger: trigger, character: character)
                        }
                    }
                    .padding(HmmSpacing.xs)
                }
                .frame(maxWidth: 520)
                .fixedSize(horizontal: true, vertical: false)
                .hmmPanelBackground()
                .accessibilityIdentifier("trigger-deck")
            }
        }
    }
}

/// One trigger under a finger: down is a press, up lets go.
private struct TriggerPad: View {
    let editor: EditorModel
    let trigger: Trigger
    let character: ObjectID
    @State private var down = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let isOn = editor.live.held.contains(trigger.id)
        HStack(spacing: HmmSpacing.xxs) {
            if let key = trigger.key { Text(key).font(.hmmNumbers(.caption)).foregroundStyle(isOn ? theme.onAccent : theme.text2) }
            Text(trigger.name).font(.hmm(.footnote, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, HmmSpacing.s)
        .frame(minWidth: HmmTarget.primary, minHeight: HmmTarget.primary)
        .foregroundStyle(isOn ? theme.onAccent : theme.text)
        .background(Capsule().fill(isOn || down ? theme.accent : theme.surface2.opacity(0.9)))
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !down else { return }
                down = true
                editor.pressTrigger(trigger, on: character)
            }
            .onEnded { _ in
                down = false
                editor.releaseTrigger(trigger)
            })
        .accessibilityElement()
        .accessibilityLabel(trigger.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { editor.pressTrigger(trigger, on: character) }
        .accessibilityIdentifier("deck-\(trigger.name)")
    }
}
