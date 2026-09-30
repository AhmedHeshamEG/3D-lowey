#if canImport(SwiftUI)
    import SwiftUI

    /// A round icon button: 44 pt (52 pt for primary transport), SF Symbol in medium weight, glass unless it sits on
    /// a panel. The accent fills it only while `isOn` (the active tool, the open panel).
    public struct HmmButton: View {
        private let systemName: String
        private let label: String
        private let isOn: Bool
        private let size: Double
        private let role: ButtonRole?
        private let action: () -> Void
        @Environment(\.hmmInsideGlass) private var insideGlass
        @Environment(\.hmmTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled

        public init(_ systemName: String, label: String, isOn: Bool = false, size: Double = HmmTarget.minimum,
                    role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.systemName = systemName
            self.label = label
            self.isOn = isOn
            self.size = size
            self.role = role
            self.action = action
        }

        public var body: some View {
            Button(role: role) {
                HmmHaptics.play(.selection)
                action()
            } label: {
                Image(systemName: systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: size * 0.4, weight: isOn ? .semibold : .medium))
                    .frame(width: size, height: size)
                    .foregroundStyle(foreground)
                    .background(Circle().fill(isOn ? theme.accent : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(OptionalGlass(enabled: !insideGlass, shape: Circle()))
            .opacity(isEnabled ? 1 : 0.35)
            .accessibilityLabel(label)
            .accessibilityIdentifier(label)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .hoverEffect(.highlight)
        }

        private var foreground: Color {
            if isOn { return theme.onAccent }
            return role == .destructive ? theme.danger : theme.text
        }
    }

    /// A labelled capsule button for panels and sheets. `prominent` = the one primary action on a screen.
    public struct HmmPillButton: View {
        private let title: String
        private let systemName: String?
        private let prominent: Bool
        private let role: ButtonRole?
        private let action: () -> Void
        @Environment(\.hmmTheme) private var theme

        public init(_ title: String, systemName: String? = nil, prominent: Bool = false, role: ButtonRole? = nil,
                    action: @escaping () -> Void) {
            self.title = title
            self.systemName = systemName
            self.prominent = prominent
            self.role = role
            self.action = action
        }

        public var body: some View {
            Button(role: role) {
                HmmHaptics.play(.selection)
                action()
            } label: {
                HStack(spacing: HmmSpacing.xs) {
                    if let systemName { Image(systemName: systemName).symbolRenderingMode(.hierarchical) }
                    Text(title).lineLimit(1)
                }
                .font(.hmm(.body, weight: .semibold))
                .padding(.horizontal, HmmSpacing.m)
                .frame(minHeight: HmmTarget.minimum)
                .foregroundStyle(prominent ? theme.onAccent : (role == .destructive ? theme.danger : theme.text))
                .background(Capsule().fill(prominent ? theme.accent : theme.surface2.opacity(0.9)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(title)
            .hoverEffect(.highlight)
        }
    }

    /// Applies glass only when not already inside a glass panel.
    struct OptionalGlass<S: Shape>: ViewModifier {
        let enabled: Bool
        let shape: S

        func body(content: Content) -> some View {
            if enabled {
                content.hmmGlass(in: shape)
            } else {
                content
            }
        }
    }
#endif
