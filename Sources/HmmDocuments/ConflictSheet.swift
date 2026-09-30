#if canImport(SwiftUI)
    import HmmDesign
    import SwiftUI

    /// Asks how to settle a sync conflict: both versions with their device and time, three clear choices.
    public struct HmmConflictSheet: View {
        private let documentName: String
        private let thisVersion: ConflictVersion
        private let otherVersion: ConflictVersion
        private let choose: (ConflictChoice) -> Void
        @Environment(\.hmmTheme) private var theme

        public init(documentName: String, thisVersion: ConflictVersion, otherVersion: ConflictVersion,
                    choose: @escaping (ConflictChoice) -> Void) {
            self.documentName = documentName
            self.thisVersion = thisVersion
            self.otherVersion = otherVersion
            self.choose = choose
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.l) {
                VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                    Text("“\(documentName)” was changed on two devices")
                        .font(.hmm(.title3, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Choose which version to keep. Keeping both saves the other one as a copy.")
                        .font(.hmm(.body))
                        .foregroundStyle(theme.text2)
                }
                HStack(spacing: HmmSpacing.m) {
                    card("This version", thisVersion)
                    card("Other version", otherVersion)
                }
                VStack(spacing: HmmSpacing.xs) {
                    HmmPillButton(ConflictChoice.keepBoth.title, systemName: "doc.on.doc", prominent: true) { choose(.keepBoth) }
                    HmmPillButton(ConflictChoice.keepThis.title) { choose(.keepThis) }
                    HmmPillButton(ConflictChoice.keepOther.title) { choose(.keepOther) }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(HmmSpacing.l)
            .frame(maxWidth: 520)
            .background(theme.background)
            .interactiveDismissDisabled()
        }

        private func card(_ title: String, _ version: ConflictVersion) -> some View {
            VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                HmmSectionHeader(title)
                Text(version.deviceName).font(.hmm(.body, weight: .semibold)).foregroundStyle(theme.text)
                Text(version.modified, format: .dateTime.day().month().hour().minute())
                    .font(.hmm(.footnote))
                    .foregroundStyle(theme.text2)
            }
            .padding(HmmSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
        }
    }
#endif
