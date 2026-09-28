import LoweyCore
import LoweyRender
import SwiftUI

/// Dark, neutral chrome that doesn't compete with the scene (game-HUD feel).
enum Theme {
    static let background = Color(red: 0.07, green: 0.075, blue: 0.09)
    static let panel = Color(red: 0.11, green: 0.115, blue: 0.135).opacity(0.94)
    static let panelStroke = Color.white.opacity(0.08)
    static let raised = Color.white.opacity(0.07)
    static let raisedStrong = Color.white.opacity(0.14)
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.28)
    static let text = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.55)
    static let danger = Color(red: 1, green: 0.38, blue: 0.36)
    static let corner: CGFloat = 22
    /// Darkens glass just enough for white text over bright skies.
    static let glassTint = Color.black.opacity(0.32)
    static let touch: CGFloat = 48
}

extension View {
    /// Floating panel look: the system's Liquid Glass, tinted dark so text stays legible over any scene.
    func panelStyle(cornerRadius: CGFloat = Theme.corner) -> some View {
        glassEffect(.regular.tint(Theme.glassTint), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A floating control on glass (round buttons, pills that sit on the stage).
    func floatingGlass(in shape: some Shape = Capsule(), interactive: Bool = true) -> some View {
        glassEffect(interactive ? .regular.tint(Theme.glassTint).interactive() : .regular.tint(Theme.glassTint), in: shape)
    }
}

/// Round icon button used on rails and bars.
struct IconButton: View {
    let systemName: String
    var label: String
    var isOn = false
    var isEnabled = true
    var size: CGFloat = Theme.touch
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(isOn ? Color.black : Theme.text)
                .background(Circle().fill(isOn ? Theme.accent : Theme.raised))
                .contentShape(Circle())
                .glassEffect(.regular.tint(isOn ? Theme.accent.opacity(0.6) : Theme.glassTint).interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label)
        .hoverEffect(.lift)
    }
}

/// Pill-shaped labelled button for panels.
struct PillButton: View {
    let title: String
    var systemName: String?
    var prominent = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 6) {
                if let systemName { Image(systemName: systemName) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .foregroundStyle(prominent ? Color.black : (destructive ? Theme.danger : Theme.text))
            .background(Capsule().fill(prominent ? Theme.accent : Theme.raised))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .panelStyle(cornerRadius: 22)
            .accessibilityIdentifier("toast")
    }
}

enum Haptics {
    @MainActor static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension RGBA {
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }

    init(_ color: Color) {
        self.init(UIColor(color))
    }
}

/// Human-friendly number formatting for inspectors.
enum NumberFormat {
    static func short(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(format: "%.2f", rounded)
    }
}
