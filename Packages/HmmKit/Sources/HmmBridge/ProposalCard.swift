#if canImport(SwiftUI)
    import HmmDesign
    import SwiftUI
    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    /// A proposal as the user sees it: the preview, what it does, and Apply / Not now.
    public struct HmmProposalCard: View {
        private let proposal: Proposal
        private let apply: () -> Void
        private let decline: () -> Void
        @Binding private var autoApply: Bool
        @Environment(\.hmmTheme) private var theme

        public init(_ proposal: Proposal, autoApply: Binding<Bool>, apply: @escaping () -> Void, decline: @escaping () -> Void) {
            self.proposal = proposal
            _autoApply = autoApply
            self.apply = apply
            self.decline = decline
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if let thumbnail = proposal.thumbnail, let image = PlatformImage(data: thumbnail) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                        .accessibilityLabel("Preview of the change")
                }
                VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                    Text(proposal.title).font(.hmm(.headline, weight: .semibold)).foregroundStyle(theme.text)
                    Text(proposal.summary).font(.hmm(.body)).foregroundStyle(theme.text2)
                    Text("From \(proposal.source)").font(.hmm(.footnote)).foregroundStyle(theme.text3)
                }
                if !proposal.details.isEmpty {
                    VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                        ForEach(Array(proposal.details.prefix(12).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.hmm(.footnote)).foregroundStyle(theme.text2)
                        }
                        if proposal.details.count > 12 {
                            Text("and \(proposal.details.count - 12) more").font(.hmm(.footnote)).foregroundStyle(theme.text3)
                        }
                    }
                }
                Toggle("Auto-apply for this session", isOn: $autoApply)
                    .font(.hmm(.body))
                    .tint(theme.accent)
                HStack(spacing: HmmSpacing.s) {
                    HmmPillButton("Not now", action: decline)
                    HmmPillButton("Apply", systemName: "checkmark", prominent: true, action: apply)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(HmmSpacing.l)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("proposal")
        }
    }

    #if canImport(UIKit)
        typealias PlatformImage = UIImage

        extension Image {
            init(platformImage: UIImage) {
                self.init(uiImage: platformImage)
            }
        }
    #elseif canImport(AppKit)
        typealias PlatformImage = NSImage

        extension Image {
            init(platformImage: NSImage) {
                self.init(nsImage: platformImage)
            }
        }
    #endif
#endif
