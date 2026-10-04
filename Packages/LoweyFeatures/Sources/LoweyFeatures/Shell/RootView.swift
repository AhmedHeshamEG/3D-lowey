import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// The app's root: Home, with the open project over it. A card grows into the stage (the system zoom transition from
/// the card's picture) and the stage shrinks back into it. Universal gestures, the toast and the theme live here and
/// in the project's cover.
public struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(HmmThemeMode.storageKey) private var themeMode = HmmThemeMode.dark.rawValue
    /// This window, among the app's windows (Stage Manager).
    @State private var windowID = UUID()
    @Namespace private var zoom

    public init() {}

    public var body: some View {
        if app.primaryWindow == nil || app.primaryWindow == windowID {
            main
                .onAppear { if app.primaryWindow == nil { app.primaryWindow = windowID } }
                .onDisappear { if app.primaryWindow == windowID { app.primaryWindow = nil } }
        } else {
            SecondaryWindowView { app.primaryWindow = windowID }
                .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
        }
    }

    private var main: some View {
        @Bindable var app = app
        return ZStack {
            BackgroundFill()
            TheaterView(zoom: zoom)
        }
        .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
        .hmmToast($app.toast)
        .fullScreenCover(item: $app.editor) { editor in
            ZStack {
                BackgroundFill()
                EditorScreen(editor: editor)
            }
            .environment(app)
            .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
            .hmmToast($app.toast)
            .hmmUniversalGestures(HmmGestureActions(
                undo: { app.editor?.undo() },
                redo: { app.editor?.redo() },
                toggleChrome: { app.editor?.chromeHidden.toggle() }
            ))
            // Pinching and dragging belong to the stage: the project closes from Home in the corner, never by a swipe.
            .interactiveDismissDisabled()
            .navigationTransition(.zoom(sourceID: editor.document.project.id.raw, in: zoom))
        }
        .sheet(item: $app.pendingConflict) { conflict in
            HmmConflictSheet(documentName: conflict.name, thisVersion: conflict.thisVersion,
                             otherVersion: conflict.versions.first ?? conflict.thisVersion) { choice in
                app.resolveConflict(choice)
            }
        }
        .sheet(isPresented: $app.showsSettings) { SettingsSheet(app: app) }
        .onChange(of: app.projects.count) { _, _ in openTourIslandIfNeeded() }
        .onChange(of: app.showTour) { _, _ in openTourIslandIfNeeded() }
        .task { await app.start() }
    }
}

extension RootView {
    /// First launch: the tour happens on the welcome island.
    private func openTourIslandIfNeeded() {
        guard app.showTour, app.editor == nil, let island = app.projects.first(where: { $0.info.name == IslandSample.projectName }) else { return }
        app.open(url: island.url)
    }
}

private struct BackgroundFill: View {
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        theme.background.ignoresSafeArea()
    }
}
