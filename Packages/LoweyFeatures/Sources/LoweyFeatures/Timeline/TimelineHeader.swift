import HmmDesign
import LoweyCore
import SwiftUI

/// Transport, timecode, Compose · Perform · Keyframe and the mode's own controls, markers, sound and the menu.
struct TimelineHeader: View {
    @Bindable var editor: EditorModel
    let fit: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.s) {
            Transport(editor: editor)
            TimelineClock(editor: editor)
            ModePicker(mode: $editor.timelineMode)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    switch editor.timelineMode {
                    case .perform: PerformControls(editor: editor)
                    case .keyframe: KeyControls(editor: editor)
                    case .compose: composeControls
                    }
                }
            }
            HmmButton("flag", label: "Add marker", size: 40) { editor.addMarker() }
            HmmButton("waveform", label: "Sound and words", size: 40) { editor.sheet = .audio }
            menu
            HmmButton("chevron.down", label: "Collapse the timeline", size: 36) { editor.timelineCollapsed = true }
        }
        .environment(\.hmmInsideGlass, true)
    }

    @ViewBuilder private var composeControls: some View {
        Toggle(isOn: $editor.keyBoxSelect) { Label("Select", systemImage: "rectangle.dashed").font(.hmm(.footnote, weight: .semibold)) }
            .toggleStyle(.button)
        if !editor.selection.isEmpty, editor.selectionHasAnimation {
            HmmPillButton("Clear animation", systemName: "xmark.bin", role: .destructive) { editor.clearAnimation() }
        }
        Hint("Slide whole animations in time.")
    }

    private var menu: some View {
        Menu {
            Section("Loop") {
                Button("Loop starts here", systemImage: "arrow.right.to.line") { editor.setLoopStart() }
                Button("Loop ends here", systemImage: "arrow.left.to.line") { editor.setLoopEnd() }
                if editor.timeline.loop != nil { Button("No loop", systemImage: "xmark") { editor.clearLoop() } }
            }
            Section {
                Button("Show the whole timeline", systemImage: "arrow.left.and.right", action: fit)
                Toggle("Snap to spoken words", isOn: $editor.snapToWords)
                Button("Timeline settings…", systemImage: "slider.horizontal.3") { editor.sheet = .timelineSettings }
            }
        } label: {
            Image(systemName: editor.timeline.loop != nil ? "repeat" : "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(editor.timeline.loop != nil ? theme.accent : theme.text)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Timeline menu")
        .accessibilityIdentifier("timeline-menu")
    }
}

/// Compose · Perform · Keyframe; the current one labelled.
private struct ModePicker: View {
    @Binding var mode: TimelineMode
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TimelineMode.allCases) { item in
                Button {
                    HmmHaptics.play(.selection)
                    withAnimation(.hmmSnappy) { mode = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.systemImage)
                        if item == mode { Text(item.title) }
                    }
                    .font(.hmm(.footnote, weight: .semibold))
                    .padding(.horizontal, item == mode ? 12 : 10)
                    .frame(height: 36)
                    .foregroundStyle(item == mode ? theme.onAccent : theme.text)
                    .background(Capsule().fill(item == mode ? theme.accent : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == mode ? .isSelected : [])
                .accessibilityIdentifier("timeline-mode-\(item.rawValue)")
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.surface2))
    }
}

/// Keyframe: key the selection, auto-key, pick keys, easing and the key menu.
private struct KeyControls: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPillButton("Key", systemName: "diamond.fill", prominent: !editor.selection.isEmpty) { editor.keySelection() }
            .disabled(editor.selection.isEmpty)
        Toggle(isOn: $editor.autoKey) { Text("Auto-key").font(.hmm(.footnote, weight: .semibold)) }
            .toggleStyle(.button)
            .accessibilityIdentifier("auto-key")
        Toggle(isOn: $editor.keyBoxSelect) { Label("Select", systemImage: "rectangle.dashed").font(.hmm(.footnote, weight: .semibold)) }
            .toggleStyle(.button)
            .accessibilityIdentifier("key-select-mode")
        Menu {
            ForEach(KeyQuery.allCases) { query in
                if query != .loop || editor.timeline.loop != nil {
                    Button(query.title, systemImage: query.systemImage) { editor.selectKeys(query) }
                }
            }
        } label: {
            Label(editor.selection.isEmpty ? "Pick" : "Pick in selection", systemImage: "checklist").font(.hmm(.footnote, weight: .semibold))
        }
        .accessibilityIdentifier("key-select-menu")
        if !editor.selectedKeys.isEmpty { selectedKeyMenus }
        if editor.selectedKeys.isEmpty, let key = editor.firstGraphKey {
            HmmButton("point.topleft.down.to.point.bottomright.curvepath", label: "Graph editor", size: 36) { editor.graphKey = key }
                .accessibilityIdentifier("graph-editor")
        }
        if editor.hasKeyClipboard { HmmPillButton("Paste", systemName: "doc.on.clipboard") { editor.pasteKeys() } }
    }

    @ViewBuilder private var selectedKeyMenus: some View {
        Menu {
            ForEach(EasingChoice.allCases) { choice in
                Button(choice.title) { editor.setEasing(choice.easing) }
            }
            Divider()
            Button("Graph editor…", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                editor.graphKey = editor.selectedKeys.min { $0.time < $1.time }
            }
        } label: {
            Label("Easing", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.hmm(.footnote, weight: .semibold))
        }
        Menu {
            Button("Copy", systemImage: "doc.on.doc") { editor.copyKeys() }
            Button("Mirror (there and back)", systemImage: "arrow.left.and.right") { editor.mirrorKeys() }
            Button("Reverse", systemImage: "arrow.uturn.backward") { editor.reverseKeys() }
            Button("Twice as fast", systemImage: "hare") { editor.retimeKeys(0.5) }
            Button("Twice as slow", systemImage: "tortoise") { editor.retimeKeys(2) }
            Button("One frame earlier", systemImage: "chevron.left") { editor.nudgeSelectedKeys(frames: -1) }
            Button("One frame later", systemImage: "chevron.right") { editor.nudgeSelectedKeys(frames: 1) }
            Divider()
            Button("Delete keys", systemImage: "trash", role: .destructive) { editor.deleteSelectedKeys() }
        } label: {
            Label("\(editor.selectedKeys.count) key\(editor.selectedKeys.count == 1 ? "" : "s")", systemImage: "diamond")
                .font(.hmm(.footnote, weight: .semibold))
        }
    }
}

/// Perform: record (3-2-1), filtering and sensitivity live in the sidebar; Pencil roll; a performed number.
private struct PerformControls: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            if editor.performPhase == .recording {
                editor.pause()
            } else {
                editor.armPerform()
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(theme.record).frame(width: 14, height: 14)
                Text(recordTitle).font(.hmm(.body, weight: .semibold))
            }
            .padding(.horizontal, HmmSpacing.s)
            .frame(height: 40)
            .background(Capsule().fill(editor.performPhase == .idle ? theme.surface2 : theme.record.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("perform-record")
        Toggle(isOn: $editor.performSettings.barrelRoll) {
            Label("Pencil roll", systemImage: "applepencil.and.scribble").font(.hmm(.footnote, weight: .semibold))
        }
        .toggleStyle(.button)
        PerformValueSlider(editor: editor)
    }

    private var recordTitle: String {
        switch editor.performPhase {
        case .idle: "Record"
        case let .countdown(count): "Ready… \(count)"
        case .recording: "Stop"
        }
    }
}
