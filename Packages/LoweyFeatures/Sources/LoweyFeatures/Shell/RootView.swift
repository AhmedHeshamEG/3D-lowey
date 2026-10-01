import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// The app's root: the Theater, or the open project. Universal gestures, the toast and the theme live here.
public struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(HmmThemeMode.storageKey) private var themeMode = HmmThemeMode.dark.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        @Bindable var app = app
        ZStack {
            BackgroundFill()
            if let editor = app.editor {
                EditorScreen(editor: editor)
                    .transition(.opacity)
            } else {
                TheaterView()
                    .transition(.opacity)
            }
        }
        .hmmThemed(.lowey, mode: HmmThemeMode(rawValue: themeMode) ?? .dark)
        .hmmToast($app.toast)
        .hmmUniversalGestures(HmmGestureActions(
            undo: { app.editor?.undo() },
            redo: { app.editor?.redo() },
            toggleChrome: { app.editor?.chromeHidden.toggle() }
        ))
        .animation(HmmMotion.gentle.animation(reduceMotion: reduceMotion), value: app.editor == nil)
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
