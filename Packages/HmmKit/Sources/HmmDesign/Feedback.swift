#if canImport(SwiftUI)
    import SwiftUI

    /// A short message that floats over the canvas and leaves by itself.
    public struct HmmToastMessage: Equatable, Identifiable, Sendable {
        public enum Kind: Sendable { case info, success, error }

        public var id = UUID()
        public var text: String
        public var kind: Kind
        /// A recovery action ("Try again", "Open Settings").
        public var actionTitle: String?

        public init(_ text: String, kind: Kind = .info, actionTitle: String? = nil) {
            self.text = text
            self.kind = kind
            self.actionTitle = actionTitle
        }
    }

    public struct HmmToast: View {
        private let message: HmmToastMessage
        private let action: (() -> Void)?
        @Environment(\.hmmTheme) private var theme

        public init(_ message: HmmToastMessage, action: (() -> Void)? = nil) {
            self.message = message
            self.action = action
        }

        public var body: some View {
            HStack(spacing: HmmSpacing.s) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                Text(message.text)
                    .font(.hmm(.body, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.leading)
                if let title = message.actionTitle, let action {
                    Button(title, action: action)
                        .font(.hmm(.body, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, HmmSpacing.m)
            .padding(.vertical, HmmSpacing.s)
            .hmmGlass(in: Capsule(), interactive: false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("toast")
        }

        private var symbol: String? {
            switch message.kind {
            case .info: nil
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        private var tint: Color {
            message.kind == .error ? theme.danger : theme.success
        }
    }

    private struct HmmToastPresenter: ViewModifier {
        @Binding var message: HmmToastMessage?
        let duration: Duration
        let action: ((HmmToastMessage) -> Void)?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.overlay(alignment: .top) {
                if let current = message {
                    HmmToast(current, action: action.map { handler in { handler(current) } })
                        .padding(.top, HmmSpacing.l)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: current.id) {
                            try? await Task.sleep(for: current.actionTitle == nil ? duration : duration * 2)
                            guard !Task.isCancelled, message?.id == current.id else { return }
                            withAnimation(HmmMotion.standard.animation(reduceMotion: reduceMotion)) { message = nil }
                        }
                }
            }
            .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: message)
        }
    }

    public extension View {
        /// Shows `message` as a toast at the top for `duration` (twice as long when it offers an action).
        func hmmToast(_ message: Binding<HmmToastMessage?>, duration: Duration = .seconds(2.5),
                      action: ((HmmToastMessage) -> Void)? = nil) -> some View {
            modifier(HmmToastPresenter(message: message, duration: duration, action: action))
        }
    }

    /// An empty screen with one clear action.
    public struct HmmEmptyState: View {
        private let systemName: String
        private let title: String
        private let message: String
        private let actionTitle: String?
        private let action: (() -> Void)?
        @Environment(\.hmmTheme) private var theme

        public init(_ systemName: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
            self.systemName = systemName
            self.title = title
            self.message = message
            self.actionTitle = actionTitle
            self.action = action
        }

        public var body: some View {
            VStack(spacing: HmmSpacing.s) {
                Image(systemName: systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(theme.text2)
                Text(title)
                    .font(.hmm(.headline, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(message)
                    .font(.hmm(.body))
                    .foregroundStyle(theme.text2)
                    .multilineTextAlignment(.center)
                if let actionTitle, let action {
                    HmmPillButton(actionTitle, prominent: true, action: action)
                        .padding(.top, HmmSpacing.xs)
                }
            }
            .padding(HmmSpacing.xl)
            .frame(maxWidth: 420)
            .accessibilityElement(children: .contain)
        }
    }
#endif
