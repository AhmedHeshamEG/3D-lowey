import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// Actions ▸ History: a bar floating over the bottom of the stage. Drag back through every step and the stage shows
/// that moment; "Go back here" makes it the present (the state you leave is kept as a version), "Name" keeps the
/// moment as a version, "Versions" lists the named and automatic ones. Editing while it shows an earlier moment
/// branches from there.
struct HistoryScrubberBar: View {
    @Bindable var editor: EditorModel
    let state: HistoryScrubState
    @Environment(\.hmmTheme) private var theme
    @State private var naming = false
    @State private var versionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.s) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("History").font(.hmm(.headline, weight: .semibold))
                    Text(moment).font(.hmm(.footnote)).foregroundStyle(theme.text2).monospacedDigit().lineLimit(1)
                }
                Spacer()
                versionsMenu
                HmmPillButton("Name", systemName: "bookmark") {
                    versionName = ""
                    naming = true
                }
                .accessibilityIdentifier("history-name")
            }
            Slider(value: position, in: 0 ... Double(max(state.count, 1)), step: 1)
                .tint(theme.accent)
                .disabled(state.count == 0)
                .accessibilityLabel("Moment in the history")
                .accessibilityValue(moment)
                .accessibilityIdentifier("history-slider")
            HStack {
                HmmPillButton("Close", systemName: "xmark") { editor.closeHistory() }
                    .accessibilityIdentifier("history-close")
                Spacer()
                if !state.isNow {
                    HmmPillButton("Go back here", systemName: "arrow.uturn.backward", prominent: true) { editor.restoreHistoryHere() }
                        .accessibilityIdentifier("history-restore")
                }
            }
        }
        .padding(HmmSpacing.m)
        .frame(maxWidth: 560)
        .hmmGlass(in: RoundedRectangle(cornerRadius: HmmRadius.panel, style: .continuous), interactive: false)
        .padding(HmmSpacing.m)
        .alert("Name this version", isPresented: $naming) {
            TextField("Name", text: $versionName)
            Button("Save") { editor.nameVersion(versionName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var position: Binding<Double> {
        Binding(get: { Double(state.position) }, set: { editor.scrubHistory(to: Int($0.rounded())) })
    }

    /// "Now", or "12 of 87 · Move Lamp".
    private var moment: String {
        if state.isNow { return String(localized: "Now · \(state.count) steps back are kept") }
        if state.position == 0 { return String(localized: "The start of the kept history") }
        return String(localized: "\(state.position) of \(state.count) · \(state.label ?? "")")
    }

    private var versionsMenu: some View {
        Menu {
            if state.versions.isEmpty {
                Text("No versions yet")
            }
            ForEach(state.versions) { version in
                Button {
                    editor.restoreVersion(version)
                } label: {
                    Label(version.name, systemImage: version.automatic ? "clock" : "bookmark.fill")
                    Text(version.date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        } label: {
            Label("Versions", systemImage: "square.stack")
                .font(.hmm(.body, weight: .semibold))
                .frame(minHeight: HmmTarget.minimum)
        }
        .accessibilityIdentifier("history-versions")
    }
}
