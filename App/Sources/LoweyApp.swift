import LoweyFeatures
import SwiftUI
import UIKit

@main
struct LoweyApp: App {
    @State private var app = AppModel()
    @State private var exportReporter = ExportLiveActivity()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // On an iPhone the app is the face companion for the iPad.
                CompanionView()
                    .preferredColorScheme(.dark)
            } else {
                RootView()
                    .environment(app)
                    .onOpenURL { app.handleOpenedFile($0) }
                    .onAppear { app.exportReporter = exportReporter }
            }
        }
        .commands { LoweyMenuCommands(app: app) }
        .onChange(of: phase) { _, phase in
            guard UIDevice.current.userInterfaceIdiom != .phone else { return }
            switch phase {
            case .active: app.sceneDidBecomeActive()
            case .background: app.sceneDidEnterBackground()
            default: break
            }
        }
    }
}
