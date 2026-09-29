import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// "AI proposes, you decide": what a script would do, and Apply / Not now.
struct ProposalSheet: View {
    @Bindable var editor: EditorModel
    let proposal: ScriptProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading) {
                    Text(proposal.title).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("From \(proposal.source)").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(proposal.lines, id: \.self) { line in
                        Label(line, systemImage: "circle.fill").labelStyle(BulletLabelStyle()).font(.system(size: 15, weight: .semibold))
                    }
                    if !proposal.report.isEmpty {
                        SectionHeader(title: "Step by step").padding(.top, 8)
                        ForEach(Array(proposal.report.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("It's one undo step, and everything stays editable by hand.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            HStack {
                PillButton(title: "Not now", systemName: "xmark", destructive: true) { editor.answerProposal(false) }
                Spacer()
                PillButton(title: "Apply", systemName: "checkmark", prominent: true) { editor.answerProposal(true) }
                    .accessibilityIdentifier("apply-proposal")
            }
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

/// The AI & laptop bridge: on/off, the address and pairing code to type on the laptop, scripts from the clipboard.
struct BridgePanel: View {
    @Bindable var bridge: BridgeModel
    let editor: EditorModel
    @State private var importing = false
    @State private var editingCode = false
    @State private var newCode = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("AI & laptop").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    PillButton(title: "Done", prominent: true) { dismiss() }
                }
                Toggle("Bridge on (local network only)", isOn: Binding(get: { bridge.isOn }, set: { bridge.toggle($0) }))
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityIdentifier("bridge-toggle")
                Text(bridge.status).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                if bridge.isOn {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("On the laptop").font(.system(size: 13, weight: .bold))
                        Text("lowey-link pair \(bridge.address) \(bridge.code)")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Text(bridge.oneTimeCode ? "Pairing code (works once)" : "Pairing code (always the same)")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        HStack(alignment: .firstTextBaseline) {
                            Text(bridge.code).font(.system(size: 40, weight: .heavy, design: .rounded)).tracking(6)
                                .accessibilityIdentifier("bridge-code")
                            Spacer()
                            if !bridge.oneTimeCode {
                                PillButton(title: "Change", systemName: "pencil") {
                                    newCode = bridge.code
                                    editingCode = true
                                }
                            }
                        }
                        Toggle("New code after every pairing", isOn: $bridge.oneTimeCode)
                            .font(.system(size: 14, weight: .semibold))
                        Text("A laptop pairs once and stays paired; the code only matters for a new laptop.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.raised))
                    .alert("Pairing code", isPresented: $editingCode) {
                        TextField("6 digits", text: $newCode).keyboardType(.numberPad)
                        Button("Save") {
                            if !bridge.setPermanentCode(newCode) { editor.app.show("The code must be 6 digits") }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Six digits, kept until you change it.")
                    }
                    Toggle("Apply AI scripts without asking", isOn: $bridge.autoApply)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Off: every script from Claude (or any AI) waits for your OK here, with a preview.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                    HStack {
                        Text("\(bridge.pairedCount) paired device\(bridge.pairedCount == 1 ? "" : "s")").font(.system(size: 13))
                        Spacer()
                        PillButton(title: "Forget all", systemName: "xmark.shield", destructive: true) { bridge.forgetDevices() }
                    }
                }
                SectionHeader(title: "Scene Scripts")
                Text("Any AI can write a Scene Script (JSON). Paste it here or open the file; you'll see what it does before it happens.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                HStack {
                    PillButton(title: "Paste script", systemName: "doc.on.clipboard") {
                        dismiss()
                        editor.importScriptFromClipboard()
                    }
                    PillButton(title: "Open file…", systemName: "folder") { importing = true }
                    PillButton(title: "Copy the reference", systemName: "book") { UIPasteboard.general.string = ScriptReference.text }
                }
            }
            .padding(22)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            guard case let .success(url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                dismiss()
                editor.importScript(data, source: url.lastPathComponent)
            }
        }
    }
}
