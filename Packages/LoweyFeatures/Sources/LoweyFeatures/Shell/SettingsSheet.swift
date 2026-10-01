import HmmDesign
import SwiftUI

/// Settings: preferences, gestures, the tour, diagnostics, about.
struct SettingsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDiagnostics = false

    var body: some View {
        NavigationStack {
            Form {
                PreferencesForm(app: app)
                Section("Help") {
                    NavigationLink("Gestures & shortcuts") { GestureGuide() }
                    Button("Take the tour") {
                        dismiss()
                        app.startTour()
                    }
                    Button("Diagnostics") { showsDiagnostics = true }
                }
                AboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showsDiagnostics) { DiagnosticsSheet(app: app, editor: app.editor) }
        }
    }
}
