import LoweyCore
import LoweyRender
import SwiftUI

/// The stage with its game-HUD chrome: top bar, mode switcher, tool rail, inspector, panels.
struct EditorView: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            StageContainer(editor: editor)
                .ignoresSafeArea()
                .dropDestination(for: String.self) { items, location in
                    // Library tiles dragged onto the stage land where they're dropped.
                    for id in items {
                        editor.placeLibraryItem(id: id, at: location)
                    }
                    return !items.isEmpty
                }
            StageOverlay(editor: editor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(editor: editor)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 0) {
                if editor.mode == .build {
                    ToolRail(editor: editor)
                        .padding(.leading, 16)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                rightPanel
                    .padding(.trailing, 16)
                    .padding(.top, 76)
                    .padding(.bottom, 16)
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    if editor.mode == .build, !editor.selection.isEmpty, editor.tool == .select {
                        JoystickPad(editor: editor)
                            .padding(.leading, 96)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    if editor.mode == .build, editor.tool == .draw {
                        DrawPanel(editor: editor)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if editor.mode == .build, editor.tool == .scatter {
                        ScatterPanel(editor: editor)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Spacer()
                    ViewControls(editor: editor)
                        .padding(.trailing, rightPanelVisible ? 360 : 16)
                }
                .padding(.bottom, 16)
            }

            if editor.showLibrary {
                HStack {
                    Spacer()
                    LibraryPanel(editor: editor)
                        .frame(width: 420)
                        .padding(.trailing, 16)
                        .padding(.vertical, 16)
                        .transition(.move(edge: .trailing))
                }
                .background(
                    Color.black.opacity(0.001)
                        .onTapGesture { closeLibrary() }
                )
            }
        }
        .animation(.spring(duration: 0.3), value: editor.mode)
        .animation(.spring(duration: 0.3), value: editor.tool)
        .animation(.spring(duration: 0.3), value: editor.showLibrary)
        .animation(.spring(duration: 0.25), value: editor.selection.isEmpty)
        .background(KeyboardShortcuts(editor: editor))
        .dropDestination(for: URL.self) { urls, _ in
            Task { await app.library.importFiles(urls) }
            return true
        }
    }

    private var rightPanelVisible: Bool {
        switch editor.mode {
        case .build: editor.showOutliner || !editor.selection.isEmpty
        case .look, .export, .animate, .camera: true
        }
    }

    @ViewBuilder private var rightPanel: some View {
        switch editor.mode {
        case .build:
            VStack(spacing: 12) {
                if editor.showOutliner {
                    OutlinerPanel(editor: editor)
                        .frame(maxHeight: editor.selection.isEmpty ? .infinity : 300)
                }
                if !editor.selection.isEmpty {
                    InspectorPanel(editor: editor)
                }
            }
            .frame(width: 330)
        case .look:
            LookPanel(editor: editor).frame(width: 340)
        case .export:
            ExportPanel(editor: editor).frame(width: 330)
        case .animate:
            ComingSoonPanel(mode: .animate).frame(width: 330)
        case .camera:
            CameraPanel(editor: editor).frame(width: 330)
        }
    }

    private func closeLibrary() {
        editor.showLibrary = false
        editor.libraryPurpose = .place
    }
}

/// Home, project / scene menu, undo/redo, save state, mode switcher.
struct TopBar: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var renamingScene = false
    @State private var sceneName = ""

    var body: some View {
        HStack(spacing: 10) {
            IconButton(systemName: "house.fill", label: "Home") { app.closeEditor() }
            Menu {
                Section("Scenes") {
                    ForEach(editor.sceneList, id: \.id) { item in
                        Button {
                            editor.switchScene(item.id)
                        } label: {
                            if item.id == editor.scene.id {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                }
                Button("New scene", systemImage: "plus") { editor.addScene() }
                Button("Duplicate scene", systemImage: "plus.square.on.square") { editor.duplicateScene() }
                Button("Rename scene", systemImage: "pencil") {
                    sceneName = editor.scene.name
                    renamingScene = true
                }
                Divider()
                Toggle("Show FPS & stats", isOn: $editor.showStatistics)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(editor.document.project.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        Text(editor.scene.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(height: Theme.touch)
                .panelStyle(cornerRadius: 24)
            }
            .accessibilityIdentifier("scene-menu")
            if editor.isSaving {
                ProgressView().controlSize(.small)
            }
            Spacer()
            ModeSwitcher(mode: $editor.mode)
        }
        .alert("Rename scene", isPresented: $renamingScene) {
            TextField("Name", text: $sceneName)
            Button("Rename") { editor.renameScene(sceneName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Build · Animate · Camera · Look · Export
struct ModeSwitcher: View {
    @Binding var mode: EditorMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorMode.allCases) { item in
                Button {
                    Haptics.select()
                    mode = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                        if item == mode { Text(item.title) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, item == mode ? 14 : 12)
                    .frame(height: 40)
                    .foregroundStyle(item == mode ? Color.black : Theme.text)
                    .background(Capsule().fill(item == mode ? Theme.accent : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("mode-\(item.rawValue)")
            }
        }
        .padding(4)
        .panelStyle(cornerRadius: 26)
        .animation(.spring(duration: 0.25), value: mode)
    }
}

/// Hidden buttons that carry Magic Keyboard shortcuts.
struct KeyboardShortcuts: View {
    let editor: EditorModel

    var body: some View {
        ZStack {
            Button("Undo") { editor.undo() }.keyboardShortcut("z", modifiers: .command)
            Button("Redo") { editor.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Duplicate") { editor.duplicateSelection() }.keyboardShortcut("d", modifiers: .command)
            Button("Copy") { editor.copySelection() }.keyboardShortcut("c", modifiers: .command)
            Button("Paste") { editor.paste() }.keyboardShortcut("v", modifiers: .command)
            Button("Group") { editor.groupSelection() }.keyboardShortcut("g", modifiers: .command)
            Button("Select all") { editor.selectAll() }.keyboardShortcut("a", modifiers: .command)
            Button("Delete") { editor.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
            Button("Frame") { editor.frameSelection() }.keyboardShortcut("f", modifiers: [])
            Button("Library") { editor.showLibrary.toggle() }.keyboardShortcut("l", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
