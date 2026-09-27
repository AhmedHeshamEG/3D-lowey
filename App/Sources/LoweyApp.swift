import LoweyCore
import LoweyRender
import SwiftUI

@main
struct LoweyApp: App {
    @State private var app = AppModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { url in
                    app.handleOpenedFile(url)
                }
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
        .animation(.easeInOut(duration: 0.25), value: app.editor == nil)
        .animation(.spring(duration: 0.3), value: app.toast)
        .task { await app.start() }
    }
}
