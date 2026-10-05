import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Actions, the long tail: export and share, the project's scenes, history, scripts and the AI bridge, help,
/// diagnostics and settings. (Sound and the timeline's settings live in the timeline; photos and videos are added
/// from Model.)
struct ActionsPanel: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @State private var renamingScene = false
    @State private var sceneName = ""
    @State private var sharing: URL?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HmmPanel("Actions", width: 340, sizing: HmmPanelSizing(id: "actions"), close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                PanelSection("Share") {
                    TileGrid {
                        TileButton(title: "Export", systemName: "square.and.arrow.up", identifier: "open-export") { open(.export) }
                        TileButton(title: "Project file", systemName: "doc.zipper") { shareProject() }
                        // The shot in its own window: beside the editor in Stage Manager, or on an external display.
                        TileButton(title: "Monitor", systemName: "rectangle.on.rectangle", identifier: "open-monitor") {
                            openWindow(id: LoweyWindow.monitor)
                        }
                    }
                }
                scenes
                PanelSection("Project") {
                    TileGrid {
                        TileButton(title: "History", systemName: "clock.arrow.circlepath", identifier: "open-history") { editor.openHistory() }
                        TileButton(title: "Scripts", systemName: "curlybraces", identifier: "open-scripts") { editor.openScript(nil) }
                        if FeatureFlags.aiBridge {
                            TileButton(title: "AI & laptop", systemName: "network", identifier: "open-bridge") { open(.bridge) }
                            TileButton(title: "Paste script", systemName: "doc.on.clipboard") { editor.importScriptFromClipboard() }
                        }
                    }
                }
                PanelSection("Help") {
                    TileGrid {
                        TileButton(title: "Gestures", systemName: "hand.draw") { open(.gestures) }
                        TileButton(title: "Tour", systemName: "hand.wave") { app.showTour = true }
                        TileButton(title: "Diagnostics", systemName: "stethoscope") { open(.diagnostics) }
                        TileButton(title: "Settings", systemName: "gearshape") { open(.settings) }
                    }
                }
            }
        }
        .alert("Rename scene", isPresented: $renamingScene) {
            TextField("Name", text: $sceneName)
            Button("Rename") { editor.renameScene(sceneName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
    }

    private var scenes: some View {
        PanelSection("Scenes") {
            ForEach(editor.sceneList, id: \.id) { item in
                Button {
                    editor.switchScene(item.id)
                } label: {
                    HStack {
                        Text(item.name).font(.hmm(.body, weight: item.id == editor.baseScene.id ? .semibold : .regular))
                        Spacer()
                        if item.id == editor.baseScene.id { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("New", systemName: "plus") { editor.addScene() }
                HmmPillButton("Duplicate", systemName: "plus.square.on.square") { editor.duplicateScene() }
                HmmPillButton("Rename", systemName: "pencil") {
                    sceneName = editor.baseScene.name
                    renamingScene = true
                }
            }
            let others = app.projects.filter { $0.url != editor.projectURL }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { project in
                        Button(project.info.name) {
                            Task {
                                await editor.saveNow(thumbnail: false)
                                app.copyScene(editor.baseScene.id, from: editor.projectURL, to: project)
                            }
                        }
                    }
                } label: {
                    Label("Copy this scene to…", systemImage: "doc.on.doc").font(.hmm(.body, weight: .semibold))
                }
            }
        }
    }

    private func open(_ sheet: EditorSheet) {
        editor.openPanel = nil
        editor.sheet = sheet
    }

    private func shareProject() {
        guard let project = app.projects.first(where: { $0.url == editor.projectURL }) else { return }
        Task {
            await editor.saveNow(thumbnail: false)
            sharing = app.package(project)
        }
    }
}
