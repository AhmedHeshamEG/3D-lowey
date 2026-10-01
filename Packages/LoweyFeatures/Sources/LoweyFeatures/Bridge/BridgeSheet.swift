import HmmBridge
import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// The AI & laptop bridge: off until you switch it on; pair a laptop with a single-use code; see and forget paired
/// laptops; Scene Scripts from the clipboard or a file.
struct BridgeSheet: View {
    @Bindable var bridge: BridgeModel
    let editor: EditorModel
    @State private var importing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HmmSheet("AI & laptop") {
            Toggle("Bridge on (this local network only)", isOn: Binding(get: { bridge.isOn }, set: { bridge.setOn($0) }))
                .font(.hmm(.headline, weight: .semibold))
                .accessibilityIdentifier("bridge-toggle")
            Text(bridge.status).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            if bridge.isOn {
                pairing
                clients
                Toggle("Apply AI changes without asking, until the app closes", isOn: $bridge.autoApplyThisSession)
                Hint("Off: every change from Claude waits here as a proposal, with a preview. Each one is a single undo step.")
            }
            HmmSectionHeader("Scene Scripts")
            Hint("Any AI can write a Scene Script (JSON). Paste it or open the file; you see what it does before it happens.")
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Paste script", systemName: "doc.on.clipboard") {
                    dismiss()
                    editor.importScriptFromClipboard()
                }
                HmmPillButton("Open file…", systemName: "folder") { importing = true }
                HmmPillButton("Copy the reference", systemName: "book") { UIPasteboard.general.string = ScriptReference.text }
            }
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
        .onDisappear { bridge.cancelPairing() }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HmmSectionHeader("Pair a laptop")
            if let code = bridge.pairingCode {
                Text(code.digits)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .tracking(8)
                    .accessibilityIdentifier("bridge-code")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(Int(code.expires.timeIntervalSince(context.date)), 0)
                    Text("On the laptop: lowey-link pair \(bridge.address) \(code.digits) · works once, \(left / 60):\(String(format: "%02d", left % 60)) left")
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                }
                HmmPillButton("Cancel", role: .destructive) { bridge.cancelPairing() }
            } else {
                HmmPillButton("Show a pairing code", systemName: "key", prominent: true) { bridge.startPairing() }
                    .accessibilityIdentifier("bridge-pair")
                Hint("A laptop pairs once with a code that works one time, and keeps a token stored in the Keychain here.")
            }
        }
        .padding(HmmSpacing.s)
        .background(RoundedRectangle(cornerRadius: HmmRadius.card).fill(theme.surface2))
    }

    @ViewBuilder private var clients: some View {
        if !bridge.clients.isEmpty {
            HmmSectionHeader("Paired")
            ForEach(bridge.clients) { client in
                HStack {
                    VStack(alignment: .leading) {
                        Text(client.name).font(.hmm(.body, weight: .semibold))
                        Text("Last seen \(client.lastSeen.formatted(.relative(presentation: .named)))").font(.hmm(.caption)).foregroundStyle(theme.text2)
                    }
                    Spacer()
                    HmmPillButton("Forget", role: .destructive) { bridge.revoke(client) }
                }
            }
            HmmPillButton("Forget all", systemName: "xmark.shield", role: .destructive) { bridge.revokeAll() }
        }
    }
}

/// A proposal from the AI (or a pasted script): what it would do, and Apply / Not now.
struct ProposalBanner: View {
    let editor: EditorModel
    let proposal: ScriptProposal
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(proposal.title).font(.hmm(.headline, weight: .semibold))
                    Text("From \(proposal.source)").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                    ForEach(proposal.lines, id: \.self) { line in
                        Label(line, systemImage: "circle.fill").font(.hmm(.body)).labelStyle(BulletLabelStyle())
                    }
                    if !proposal.report.isEmpty {
                        HmmSectionHeader("Step by step").padding(.top, HmmSpacing.xs)
                        ForEach(Array(proposal.report.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.hmm(.footnote)).foregroundStyle(theme.text2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            HStack {
                HmmPillButton("Not now", systemName: "xmark", role: .destructive) { editor.answerProposal(false) }
                Spacer()
                HmmPillButton("Apply", systemName: "checkmark", prominent: true) { editor.answerProposal(true) }
                    .accessibilityIdentifier("apply-proposal")
            }
        }
        .padding(HmmSpacing.m)
        .frame(maxWidth: 560)
        .hmmPanelBackground()
        .padding(HmmSpacing.m)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proposal")
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HmmSpacing.xs) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Color.accentColor)
            configuration.title
        }
    }
}
