import LoweyCore
import LoweyRender
import SwiftUI

@main
struct LoweyApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some SwiftUI.Scene {
        WindowGroup {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // On an iPhone the app is the face companion for the iPad.
                CompanionView()
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
            } else {
                RootView()
                    .environment(app)
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
                    .onOpenURL { url in
                        app.handleOpenedFile(url)
                    }
            }
        }
        .commands { LoweyCommands(app: app) }
        .onChange(of: phase) { _, phase in
            if phase == .background { Diagnostics.shared.markClean() } else if phase == .active { Diagnostics.shared.markRunning() }
            guard UIDevice.current.userInterfaceIdiom != .phone else { return }
            if phase == .active { app.bridge.resume() } else if phase == .background { app.bridge.enterBackground() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let editor = app.editor {
                EditorView(editor: editor)
                    .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
            if let toast = app.toast {
                ToastView(message: toast)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: app.showTour) { _, show in
            // The tour happens on the welcome island.
            if show, app.editor == nil, let island = app.projects.first(where: { $0.info.name == IslandSample.projectName }) {
                app.open(url: island.url)
            }
        }
        .onChange(of: app.projects.count) { _, _ in
            if app.showTour, app.editor == nil, let island = app.projects.first(where: { $0.info.name == IslandSample.projectName }) {
                app.open(url: island.url)
            }
        }
        .sheet(isPresented: Binding(get: { app.showGestures }, set: { app.showGestures = $0 })) {
            GestureGuide()
        }
        .animation(.easeInOut(duration: 0.25), value: app.editor == nil)
        .animation(.spring(duration: 0.3), value: app.toast)
        .task { await app.start() }
    }
}
